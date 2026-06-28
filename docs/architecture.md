# QuerySense — Intelligent SQL Analytics Agent
### Complete Production-Grade Architectural Blueprint (v1.1 — Reviewed & Corrected)

> **Changelog from v1.0:** Fixed Spring AI 1.0.x API alignment; added `AsyncConfig` thread pool specification; added `introspectDataSource` bean; added SSE emitter lifecycle contract; added `PipelineContext` thread-safety contract; added Flyway multi-datasource binding fix; added Maven wrapper to project structure; minor Docker Compose correction.

---

## 1. Project Title

**QuerySense** — An Intelligent SQL Analytics Agent for Natural Language Business Intelligence

---

## 2. Problem Statement

Non-technical business users — analysts, product managers, executives, and operations teams — cannot query databases directly. Every data question becomes a ticket to the engineering or data team, creating a bottleneck that delays decisions by hours or days. Existing BI tools require training, rigid dashboards, and predefined metrics that don't answer novel questions. QuerySense accepts natural language business questions, translates them into validated, safe SQL, executes them against a read-only analytics database, and returns structured results with a plain-English explanation — eliminating the translation layer between business questions and data answers.

---

## 3. Target Users

- **Business analysts** who know what they want to know but cannot write SQL
- **Product managers** who need ad-hoc metrics without engineering tickets
- **Operations teams** running daily reporting queries through non-technical interfaces
- **Executives** who need on-demand KPI queries without a dashboard refresh cycle
- **Data engineers** who want to expose a governed, safe query interface to internal stakeholders without granting direct database access

---

## 4. Why Companies Care

Text-to-SQL is one of the most commercially valuable AI engineering problems of 2025–2027. It appears in Databricks (natural language to Spark SQL), Snowflake (Cortex Analyst), Google BigQuery (Duet AI), and AWS (Amazon Q for databases). Every mid-to-large company has a BI bottleneck that engineering-driven query interfaces fail to solve. The problem requires genuine backend engineering depth: schema introspection, AST-level SQL validation, read-only isolation, injection prevention, semantic caching, and structured LLM orchestration.

---

## 5. Functional Requirements

**FR-01** — Accept natural language business questions via REST API.
**FR-02** — Introspect the target analytics database schema on startup and on-demand refresh.
**FR-03** — Retrieve only the tables and columns semantically relevant to each query using pgvector DDL pruning.
**FR-04** — Generate a syntactically valid SQL SELECT query using retrieved schema as context.
**FR-05** — Parse every generated SQL query using JSQLParser before execution. Reject non-SELECT statements, DML, DDL, multiple statements, comments, and non-whitelisted tables.
**FR-06** — Execute validated queries via read-only PostgreSQL role with row limit (1000) and timeout (10s).
**FR-07** — Generate a plain-English explanation of results using a second LLM call streamed via SSE.
**FR-08** — Cache query results using semantic similarity of the natural language question.
**FR-09** — Store every query submission, generated SQL, validation result, execution result, and LLM metadata in PostgreSQL.
**FR-10** — Retry with a correction prompt (max 2 retries) on validation or execution failure.
**FR-11** — Allow administrators to configure which tables are queryable via a whitelist.
**FR-12** — Stream the plain-English explanation via SSE progressively.
**FR-13** — JWT-based authentication with data access groups controlling schema whitelist access.
**FR-14** — Per-user query rate limiting via Redis.
**FR-15** — Maintain a golden dataset and expose an evaluation endpoint that reports accuracy metrics.

---

## 6. Non-Functional Requirements

**NFR-01** — No query that modifies data can ever execute. Enforced at PostgreSQL role level.
**NFR-02** — SQL generation and validation complete within 15 seconds; cached responses within 500ms.
**NFR-03** — Generated SQL is syntactically valid 100% before execution (JSQLParser enforced).
**NFR-04** — Every query and its generated SQL must be persisted. Audit logs are append-only.
**NFR-05** — Query execution role has SELECT-only privileges. Introspection uses a separate role.
**NFR-06** — SQL generation pipeline is fully testable without live LLM API calls using Mockito.
**NFR-07** — Complete local development via `docker compose up`.
**NFR-08** — Every LLM call, schema retrieval, validation decision, and query execution is logged.

---

## 7. System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CLIENT LAYER                               │
│              REST Clients / Business Users / Admin UI               │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ HTTPS + JWT
┌───────────────────────────────▼─────────────────────────────────────┐
│                     SPRING BOOT APPLICATION                         │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │  Query API       │  │  Admin API       │  │  Evaluation API   │  │
│  │  Controller      │  │  Controller      │  │  Controller       │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬──────────┘  │
│           │                     │                      │            │
│  ┌────────▼─────────────────────▼──────────────────────▼──────────┐ │
│  │                      SERVICE LAYER                             │ │
│  │  QueryOrchestrationService  │  SchemaService                   │ │
│  │  EvaluationService          │  AuthService                     │ │
│  │  AuditService               │  RateLimitService                │ │
│  └─────────────────────────────┬───────────────────────────────── ┘ │
│                                │                                    │
│  ┌─────────────────────────────▼───────────────────────────────── ┐ │
│  │                    TEXT-TO-SQL PIPELINE                        │ │
│  │                                                                │ │
│  │  [1] QueryPreProcessingStage                                   │ │
│  │  [2] SemanticCacheStage    ──► Redis (exact) + pgvector (sem.) │ │
│  │  [3] SchemaRetrievalStage  ──► pgvector (DDL pruning)          │ │
│  │  [4] SqlGenerationStage    ──► Groq LLM via WebClient (OpenAI-compatible)     │ │
│  │  [5] ASTValidationStage    ──► JSQLParser (deterministic)      │ │
│  │  [6] QueryExecutionStage   ──► PostgreSQL (read-only role)     │ │
│  │  [7] ResultExplanationStage ─► Groq LLM mini model (SSE streaming)     │ │
│  │  [8] CachingAndAuditStage  ──► Redis + PostgreSQL              │ │
│  │                                                                │ │
│  └─────────────────────────────────────────────────────────────── ┘ │
│                                                                     │
│  ┌─────────────┐  ┌──────────────────┐  ┌──────────────────────┐    │
│  │  pgvector   │  │   PostgreSQL     │  │       Redis          │    │
│  │ (DDL embed) │  │ (audit + schema) │  │  (semantic cache +   │    │
│  │             │  │                 │   │   rate limits)        │    │
│  └─────────────┘  └──────────────────┘  └──────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
         │                               │
┌────────▼────────┐             ┌────────▼────────────┐
│    Groq API     │             │  Analytics Database  │
│  (llama/qwen +   │             │  PostgreSQL          │
│   Ollama embed) │             │  (read-only role)    │
└─────────────────┘             └─────────────────────┘
```

---

### Dual-Database Architecture Decision

QuerySense operates against **two PostgreSQL instances** (two separate databases on one instance in local dev).

**Database A — Application Database (QuerySense's own data)**
- Stores users, audit logs, schema metadata, pgvector embeddings, golden dataset, cached results
- Spring Boot connects with full read-write privileges
- Managed by Flyway migrations
- Bound to `appDataSource` (`@Primary`)

**Database B — Analytics Database (the data being queried)**
- The business data users want to query (orders, products, users, events, etc.)
- QuerySense connects via **two separate DataSource beans**:
  - `introspectDataSource` — `querysense_introspect` role — reads `information_schema` only, never on the query execution path
  - `analyticsDataSource` — `querysense_readonly` role — SELECT-only on whitelisted tables, never reads `information_schema`
- **Flyway does NOT run against `introspectDataSource` or `analyticsDataSource`** — see DataSource configuration section

---

## 8. DataSource Configuration (Critical — Prevents AI Inconsistency)

```java
@Configuration
public class DataSourceConfig {

    // PRIMARY: Application database — used by JPA, Flyway, all application repositories
    @Bean
    @Primary
    @ConfigurationProperties("spring.datasource.app")
    public DataSource appDataSource() {
        return DataSourceBuilder.create().build();
    }

    // ANALYTICS QUERY EXECUTION: read-only role, SELECT privileges only
    // Used exclusively by SafeQueryExecutor
    @Bean("analyticsDataSource")
    @ConfigurationProperties("spring.datasource.analytics")
    public DataSource analyticsDataSource() {
        return DataSourceBuilder.create().build();
    }

    // ANALYTICS INTROSPECTION: superuser-adjacent role, reads information_schema
    // Used exclusively by SchemaIntrospector — NEVER on query execution path
    @Bean("introspectDataSource")
    @ConfigurationProperties("spring.datasource.introspect")
    public DataSource introspectDataSource() {
        return DataSourceBuilder.create().build();
    }

    // JdbcTemplate for query execution (analyticsDataSource)
    @Bean("analyticsJdbcTemplate")
    public JdbcTemplate analyticsJdbcTemplate(
            @Qualifier("analyticsDataSource") DataSource analyticsDataSource) {
        return new JdbcTemplate(analyticsDataSource);
    }

    // JdbcTemplate for schema introspection (introspectDataSource)
    @Bean("introspectJdbcTemplate")
    public JdbcTemplate introspectJdbcTemplate(
            @Qualifier("introspectDataSource") DataSource introspectDataSource) {
        return new JdbcTemplate(introspectDataSource);
    }
}
```

**application.yml datasource section:**
```yaml
spring:
  datasource:
    app:
      url: ${APP_DB_URL}
      username: ${APP_DB_USERNAME}
      password: ${APP_DB_PASSWORD}
      driver-class-name: org.postgresql.Driver
      hikari:
        pool-name: AppPool
        maximum-pool-size: 10
        minimum-idle: 2
    analytics:
      url: ${ANALYTICS_DB_URL}
      username: ${ANALYTICS_DB_USERNAME}       # querysense_readonly
      password: ${ANALYTICS_DB_PASSWORD}
      driver-class-name: org.postgresql.Driver
      hikari:
        pool-name: AnalyticsPool
        maximum-pool-size: 5
        minimum-idle: 1
    introspect:
      url: ${ANALYTICS_DB_URL}                 # same host, same DB — different credentials
      username: ${ANALYTICS_INTROSPECT_USERNAME}   # querysense_introspect
      password: ${ANALYTICS_INTROSPECT_PASSWORD}
      driver-class-name: org.postgresql.Driver
      hikari:
        pool-name: IntrospectPool
        maximum-pool-size: 2
        minimum-idle: 1

  # Flyway ONLY runs against appDataSource (the @Primary bean)
  flyway:
    enabled: true
    locations: classpath:db/migration
    # Spring Boot auto-configures Flyway to use the @Primary DataSource
    # No additional configuration needed — do NOT add flyway.url/username/password
```

---

## 9. Async Configuration (Critical — Prevents Race Conditions)

```java
@Configuration
@EnableAsync
public class AsyncConfig implements AsyncConfigurer {

    // Pipeline execution thread pool
    // Bounded to prevent resource exhaustion under load
    @Bean("pipelineExecutor")
    public Executor pipelineExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(4);
        executor.setMaxPoolSize(10);
        executor.setQueueCapacity(50);       // Reject after 50 queued jobs (429 response)
        executor.setThreadNamePrefix("pipeline-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(30);
        executor.initialize();
        return executor;
    }

    @Override
    public Executor getAsyncExecutor() {
        return pipelineExecutor();
    }
}
```

**`TextToSqlPipelineExecutor` dispatches the pipeline:**
```java
@Service
public class TextToSqlPipelineExecutor {

    @Async("pipelineExecutor")
    public CompletableFuture<Void> executePipeline(PipelineContext context) {
        // stages execute sequentially inside this single async task
        // PipelineContext is NOT shared between threads — one context per job
        // ...
    }
}
```

**`PipelineContext` thread-safety contract:**
- One `PipelineContext` instance is created per job, passed only within the single async task
- `PipelineContext` is NOT thread-safe and MUST NOT be shared across tasks
- Fields are plain (non-volatile, non-synchronized) — this is safe because only one thread ever touches a given context instance
- `SseEmitter` is stored in `PipelineContext` and accessed only from the pipeline thread and the SSE registration thread (sequential — registration always completes before pipeline starts)

```java
// PipelineContext — one instance per pipeline execution
public class PipelineContext {
    // Set once at creation, never mutated
    private final UUID jobId;
    private final String userId;
    private final UUID groupId;
    private final String originalQuestion;
    private final SseEmitter emitter;

    // Mutated sequentially by pipeline stages in order
    private String normalizedQuestion;
    private TemporalContext temporalContext;
    private QueryIntent intentClass;
    private boolean cacheHit;
    private RetrievedSchemaContext schemaContext;
    private String generatedSql;
    private int retryCount;
    private ValidationResult lastValidationResult;
    private QueryExecutionResult executionResult;
    private String explanation;
}
```

---

## 10. SSE Emitter Lifecycle Contract

```java
@Component
public class SseEmitterRegistry {

    private final ConcurrentHashMap<UUID, SseEmitter> emitters = new ConcurrentHashMap<>();

    // Called when client opens GET /api/v1/queries/{jobId}/stream
    public SseEmitter register(UUID jobId) {
        // Timeout: 120 seconds — covers the maximum expected pipeline duration
        SseEmitter emitter = new SseEmitter(120_000L);

        emitter.onCompletion(() -> emitters.remove(jobId));
        emitter.onTimeout(() -> {
            emitters.remove(jobId);
            emitter.complete();
        });
        emitter.onError((ex) -> emitters.remove(jobId));

        emitters.put(jobId, emitter);
        return emitter;
    }

    // Called by pipeline stages to publish events
    public void sendEvent(UUID jobId, String stage, Object data) {
        SseEmitter emitter = emitters.get(jobId);
        if (emitter == null) return;   // client disconnected — pipeline still completes for audit
        try {
            emitter.send(SseEmitter.event()
                .name(stage)
                .data(data, MediaType.APPLICATION_JSON));
        } catch (IOException e) {
            emitters.remove(jobId);
            emitter.completeWithError(e);
        }
    }

    // Called after CachingAndAuditStage completes
    public void complete(UUID jobId) {
        SseEmitter emitter = emitters.remove(jobId);
        if (emitter != null) emitter.complete();
    }
}
```

**Contract:**
- SSE emitter is registered before the async pipeline starts (sequential guarantee in controller)
- Pipeline stages call `sendEvent()` — they do NOT hold a reference to the emitter directly; they call the registry
- If the client disconnects mid-stream, the pipeline continues to completion for audit correctness — `sendEvent()` silently drops the event if no emitter is found
- `complete()` is called exactly once, at the end of `CachingAndAuditStage`

---

## 11. AI Provider Integration (Groq + Ollama — Zero recurring API cost)

> **Default Provider:** Groq (chat/SQL/explanation) + Ollama local (embeddings)
> **Cost:** $0 recurring API cost — Groq free tier + Ollama runs locally in Docker
> **Groq API:** OpenAI-compatible REST at `https://api.groq.com/openai/v1` — no OpenAI SDK needed
> **Embedding model:** `nomic-embed-text` via Ollama — 768 dimensions, runs locally, no API cost
> **Embedding dimension:** Controlled by `EMBEDDING_MODEL` env var. Default `nomic-embed-text` = **768 dims**. Update `EMBEDDING_DIMENSION` in config if you ever switch models and re-run migrations. Do not hardcode 384 in application logic — read from config.
> **Model fallback:** All model names are environment variables (`MODEL_SQL`, `MODEL_EXPLANATION`). Switching providers or models requires only a config change, no code change.

**Dependency (pom.xml):**
```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>org.springframework.ai</groupId>
            <artifactId>spring-ai-bom</artifactId>
            <version>1.0.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>

<dependencies>
    <!-- Groq uses OpenAI-compatible REST API — call via Spring WebClient, no OpenAI starter needed -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-webflux</artifactId>
    </dependency>
    <!-- Ollama for local embeddings (nomic-embed-text) -->
    <dependency>
        <groupId>org.springframework.ai</groupId>
        <artifactId>spring-ai-ollama-spring-boot-starter</artifactId>
    </dependency>
    <!-- pgvector support -->
    <dependency>
        <groupId>org.springframework.ai</groupId>
        <artifactId>spring-ai-pgvector-store-spring-boot-starter</artifactId>
    </dependency>
</dependencies>
```

**Spring AI configuration:**
```yaml
spring:
  ai:
    ollama:
      base-url: ${OLLAMA_BASE_URL:http://localhost:11434}
      embedding:
        options:
          model: ${EMBEDDING_MODEL:nomic-embed-text}

app:
  ai:
    provider: groq
    groq:
      api-key: ${GROQ_API_KEY}
      base-url: https://api.groq.com/openai/v1
    model:
      sql: ${MODEL_SQL:llama-3.3-70b-versatile}
      explanation: ${MODEL_EXPLANATION:llama-3.3-70b-versatile}
      temperature-sql: 0.0
      temperature-explanation: 0.3
      max-tokens: 1000
```

**LLMClient wrapper — Groq via WebClient (OpenAI-compatible REST API):**
```java
@Component
public class LLMClient {

    private final WebClient groqWebClient;
    private final ObjectMapper objectMapper;
    private final String sqlModel;
    private final String explanationModel;

    // Groq exposes an OpenAI-compatible API at https://api.groq.com/openai/v1
    // We call it via Spring WebClient — no OpenAI starter needed
    public LLMClient(WebClient.Builder webClientBuilder,
                     ObjectMapper objectMapper,
                     @Value("${app.ai.groq.api-key}") String groqApiKey,
                     @Value("${app.ai.groq.base-url}") String groqBaseUrl,
                     @Value("${app.ai.model.sql}") String sqlModel,
                     @Value("${app.ai.model.explanation}") String explanationModel) {
        this.groqWebClient = webClientBuilder
            .baseUrl(groqBaseUrl)
            .defaultHeader("Authorization", "Bearer " + groqApiKey)
            .defaultHeader("Content-Type", "application/json")
            .build();
        this.objectMapper = objectMapper;
        this.sqlModel = sqlModel;
        this.explanationModel = explanationModel;
    }

    // SQL generation: blocking call, returns parsed SQLGenerationResult
    public SQLGenerationResult generateSql(String systemPrompt, String userPrompt) {
        var requestBody = Map.of(
            "model", sqlModel,
            "temperature", 0.0,
            "max_tokens", 1000,
            "messages", List.of(
                Map.of("role", "system", "content", systemPrompt),
                Map.of("role", "user", "content", userPrompt)
            )
        );

        String rawJson = groqWebClient.post()
            .uri("/chat/completions")
            .bodyValue(requestBody)
            .retrieve()
            .bodyToMono(String.class)
            .block();

        // Parse OpenAI-compatible response, extract content, then deserialize to record
        try {
            JsonNode root = objectMapper.readTree(rawJson);
            String content = root.path("choices").get(0).path("message").path("content").asText();
            String cleaned = content.replaceAll("```json|```", "").trim();
            return objectMapper.readValue(cleaned, SQLGenerationResult.class);
        } catch (Exception e) {
            throw new RuntimeException("Failed to parse SQL generation response", e);
        }
    }

    // Streaming for result explanation — uses Groq SSE (stream: true)
    public Flux<String> streamExplanation(String systemPrompt, String userPrompt) {
        var requestBody = Map.of(
            "model", explanationModel,
            "temperature", 0.3,
            "max_tokens", 1000,
            "stream", true,
            "messages", List.of(
                Map.of("role", "system", "content", systemPrompt),
                Map.of("role", "user", "content", userPrompt)
            )
        );

        return groqWebClient.post()
            .uri("/chat/completions")
            .bodyValue(requestBody)
            .retrieve()
            .bodyToFlux(String.class)
            .filter(line -> line.startsWith("data: ") && !line.contains("[DONE]"))
            .map(line -> line.substring(6))
            .mapNotNull(json -> {
                try {
                    JsonNode node = objectMapper.readTree(json);
                    return node.path("choices").get(0).path("delta").path("content").asText(null);
                } catch (Exception e) { return null; }
            })
            .filter(token -> token != null && !token.isEmpty());
    }
}
```

**EmbeddingClient wrapper — Ollama local embeddings (nomic-embed-text):**
```java
@Component
public class EmbeddingClientWrapper {

    // Spring AI OllamaEmbeddingModel — connects to local Ollama instance
    // Model: nomic-embed-text produces 768-dimension vectors (FREE, local, fast)
    // Pull once: ollama pull nomic-embed-text
    private final EmbeddingModel embeddingModel;

    public EmbeddingClientWrapper(EmbeddingModel embeddingModel) {
        this.embeddingModel = embeddingModel;
    }

    public float[] embed(String text) {
        EmbeddingResponse response = embeddingModel.embedForResponse(List.of(text));
        return response.getResults().get(0).getOutput();
    }

    public List<Double> embedToList(String text) {
        float[] arr = embed(text);
        List<Double> list = new ArrayList<>(arr.length);
        for (float v : arr) list.add((double) v);
        return list;
    }
}
```

> **Note on vector dimensions:** nomic-embed-text produces **768-dimension** vectors, not 1536.
> The Flyway migration `V16–V18` must use `vector(768)` instead of `vector(1536)`.
> See the updated migration note in Section 12.

---

## 12. Database Design

### Application Database Schema (PostgreSQL — managed by Flyway)

```sql
-- V1__create_users.sql
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) UNIQUE NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    role            VARCHAR(50) NOT NULL DEFAULT 'USER',
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- V2__create_data_access_groups.sql
CREATE TABLE data_access_groups (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100) UNIQUE NOT NULL,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- V3__create_user_group_memberships.sql
CREATE TABLE user_group_memberships (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    group_id        UUID NOT NULL REFERENCES data_access_groups(id) ON DELETE CASCADE,
    granted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    granted_by      UUID REFERENCES users(id),
    PRIMARY KEY (user_id, group_id)
);

-- V4__create_registered_tables.sql
CREATE TABLE registered_tables (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schema_name     VARCHAR(255) NOT NULL DEFAULT 'public',
    table_name      VARCHAR(255) NOT NULL,
    description     TEXT,
    row_count_est   BIGINT,
    is_whitelisted  BOOLEAN NOT NULL DEFAULT false,
    last_synced_at  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(schema_name, table_name)
);

-- V5__create_registered_columns.sql
CREATE TABLE registered_columns (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id         UUID NOT NULL REFERENCES registered_tables(id) ON DELETE CASCADE,
    column_name      VARCHAR(255) NOT NULL,
    data_type        VARCHAR(100) NOT NULL,
    is_nullable      BOOLEAN NOT NULL DEFAULT true,
    column_default   TEXT,
    description      TEXT,
    is_pii           BOOLEAN NOT NULL DEFAULT false,
    ordinal_position INTEGER NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(table_id, column_name)
);

-- V6__create_table_relationships.sql
CREATE TABLE table_relationships (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_table_id     UUID NOT NULL REFERENCES registered_tables(id),
    from_column       VARCHAR(255) NOT NULL,
    to_table_id       UUID NOT NULL REFERENCES registered_tables(id),
    to_column         VARCHAR(255) NOT NULL,
    relationship_type VARCHAR(20) NOT NULL DEFAULT 'FK',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- V7__create_group_table_access.sql
CREATE TABLE group_table_access (
    group_id    UUID NOT NULL REFERENCES data_access_groups(id) ON DELETE CASCADE,
    table_id    UUID NOT NULL REFERENCES registered_tables(id) ON DELETE CASCADE,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, table_id)
);

-- V8__create_query_jobs.sql
-- Append-only: no UPDATE or DELETE ever issued against this table
CREATE TABLE query_jobs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    group_id            UUID REFERENCES data_access_groups(id),
    natural_language    TEXT NOT NULL,
    normalized_question TEXT,
    question_hash       VARCHAR(64) NOT NULL,
    intent_class        VARCHAR(50),
    status              VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    rejection_reason    TEXT,
    cache_hit           BOOLEAN NOT NULL DEFAULT false,
    retry_count         INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ
);

-- V9__create_query_results.sql
CREATE TABLE query_results (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id                   UUID NOT NULL REFERENCES query_jobs(id),
    generated_sql            TEXT NOT NULL,
    sql_generation_attempt   INTEGER NOT NULL DEFAULT 1,
    ast_validation_passed    BOOLEAN NOT NULL,
    execution_success        BOOLEAN NOT NULL,
    row_count                INTEGER,
    execution_ms             INTEGER,
    result_data              JSONB,
    explanation              TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- V10__create_sql_generation_attempts.sql
CREATE TABLE sql_generation_attempts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id           UUID NOT NULL REFERENCES query_jobs(id),
    attempt_number   INTEGER NOT NULL,
    raw_sql          TEXT NOT NULL,
    validation_passed BOOLEAN NOT NULL,
    validation_error TEXT,
    execution_error  TEXT,
    prompt_tokens    INTEGER,
    completion_tokens INTEGER,
    latency_ms       INTEGER,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- V11__create_llm_call_logs.sql
CREATE TABLE llm_call_logs (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id            UUID REFERENCES query_jobs(id),
    call_type         VARCHAR(50) NOT NULL,
    model             VARCHAR(100) NOT NULL,
    prompt_tokens     INTEGER NOT NULL,
    completion_tokens INTEGER NOT NULL,
    total_tokens      INTEGER NOT NULL,
    latency_ms        INTEGER NOT NULL,
    cache_hit         BOOLEAN NOT NULL DEFAULT false,
    error             TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- V12__create_golden_queries.sql
CREATE TABLE golden_queries (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question     TEXT NOT NULL,
    expected_sql TEXT NOT NULL,
    description  TEXT,
    category     VARCHAR(100),
    is_active    BOOLEAN NOT NULL DEFAULT true,
    created_by   UUID REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- V13__create_evaluation_runs.sql
CREATE TABLE evaluation_runs (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_by       UUID REFERENCES users(id),
    total_cases  INTEGER NOT NULL,
    passed       INTEGER NOT NULL,
    failed       INTEGER NOT NULL,
    accuracy_pct NUMERIC(5,2) NOT NULL,
    model_used   VARCHAR(100),
    notes        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- V14__create_evaluation_results.sql
CREATE TABLE evaluation_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id          UUID NOT NULL REFERENCES evaluation_runs(id) ON DELETE CASCADE,
    golden_query_id UUID NOT NULL REFERENCES golden_queries(id),
    generated_sql   TEXT,
    expected_sql    TEXT NOT NULL,
    passed          BOOLEAN NOT NULL,
    failure_reason  TEXT,
    execution_match BOOLEAN,
    latency_ms      INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- V15__create_pgvector_extension.sql
CREATE EXTENSION IF NOT EXISTS vector;

-- V16__create_table_embeddings.sql
CREATE TABLE table_embeddings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id      UUID NOT NULL REFERENCES registered_tables(id) ON DELETE CASCADE,
    embed_content TEXT NOT NULL,
    embedding     vector(768) NOT NULL,   -- nomic-embed-text = 768 dims
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(table_id)
);

CREATE INDEX idx_table_embeddings_hnsw
    ON table_embeddings
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- V17__create_column_embeddings.sql
CREATE TABLE column_embeddings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    column_id     UUID NOT NULL REFERENCES registered_columns(id) ON DELETE CASCADE,
    embed_content TEXT NOT NULL,
    embedding     vector(768) NOT NULL,   -- nomic-embed-text = 768 dims
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(column_id)
);

CREATE INDEX idx_column_embeddings_hnsw
    ON column_embeddings
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- V18__create_question_embeddings.sql
CREATE TABLE question_embeddings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id        UUID NOT NULL REFERENCES query_jobs(id) ON DELETE CASCADE,
    embedding     vector(768) NOT NULL,   -- nomic-embed-text = 768 dims
    cached_sql    TEXT,
    cached_result JSONB,
    cache_valid   BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_question_embeddings_hnsw
    ON question_embeddings
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- V19__create_relational_indexes.sql
CREATE INDEX idx_query_jobs_user_id       ON query_jobs(user_id);
CREATE INDEX idx_query_jobs_status        ON query_jobs(status);
CREATE INDEX idx_query_jobs_question_hash ON query_jobs(question_hash);
CREATE INDEX idx_query_jobs_created_at    ON query_jobs(created_at DESC);
CREATE INDEX idx_query_jobs_group_id      ON query_jobs(group_id);
CREATE INDEX idx_sql_attempts_job_id      ON sql_generation_attempts(job_id);
CREATE INDEX idx_registered_columns_table ON registered_columns(table_id);
CREATE INDEX idx_registered_tables_whitelist ON registered_tables(is_whitelisted)
    WHERE is_whitelisted = true;
CREATE INDEX idx_eval_results_run_id      ON evaluation_results(run_id);
CREATE INDEX idx_eval_results_passed      ON evaluation_results(passed);
CREATE INDEX idx_llm_logs_job_id          ON llm_call_logs(job_id);
CREATE INDEX idx_llm_logs_created_at      ON llm_call_logs(created_at DESC);
CREATE INDEX idx_llm_logs_call_type       ON llm_call_logs(call_type);
CREATE INDEX idx_query_results_data       ON query_results USING GIN(result_data);
```

---

## 13. Redis Usage

```
Key Pattern                                  TTL        Purpose
──────────────────────────────────────────────────────────────────────────────
query:exact:{question_hash}                  1h         Exact hash → cached result JSON
query:semantic:{embedding_hash}              1h         Semantic hit pointer → job_id
rate_limit:user:{user_id}                   60s        Sliding window per-user (20/hour)
rate_limit:ip:{ip_address}                  60s        IP-level unauthenticated limit
job:status:{job_id}                          2h         Status for polling (SSE-less clients)
schema:version                               —          Schema version counter (busts cache on sync)
```

---

## 14. Read-Only Role Setup (Analytics Database)

```sql
-- Run as superuser against the analytics database

CREATE ROLE querysense_readonly WITH LOGIN PASSWORD 'strong_password_here';
GRANT SELECT ON TABLE orders TO querysense_readonly;
GRANT SELECT ON TABLE order_items TO querysense_readonly;
GRANT SELECT ON TABLE products TO querysense_readonly;
GRANT SELECT ON TABLE customers TO querysense_readonly;
-- DO NOT: GRANT SELECT ON ALL TABLES IN SCHEMA public TO querysense_readonly
REVOKE ALL ON TABLE user_credentials FROM querysense_readonly;
REVOKE ALL ON TABLE payment_methods FROM querysense_readonly;
ALTER ROLE querysense_readonly SET statement_timeout = '10s';

CREATE ROLE querysense_introspect WITH LOGIN PASSWORD 'different_strong_password';
GRANT SELECT ON ALL TABLES IN SCHEMA information_schema TO querysense_introspect;
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO querysense_introspect;
-- This role is NEVER used for query execution
```

---

## 15. AI Pipeline — Detailed Stage Breakdown

### Stage 1 — Query Pre-Processing

Responsibilities: normalize whitespace; extract temporal signals deterministically; classify query intent; early injection guard.

```java
public record TemporalContext(
    LocalDate startDate,
    LocalDate endDate,
    String originalPhrase
) {}
```

`TemporalExtractor` maps phrases to concrete date ranges using `java.time`. Resolved dates are injected into the prompt as explicit context. Intent classification (`AGGREGATION | RANKING | FILTER | TREND | COMPARISON`) uses keyword-based classification (no LLM call) at v1. `InjectionGuard` rejects questions containing SQL keywords early with status `REJECTED`.

---

### Stage 2 — Semantic Cache Lookup

**Exact Cache (Redis):** SHA-256 of normalized question → `query:exact:{hash}`. Returns in <50ms on hit.

**Semantic Cache (pgvector):** Embed normalized question, query with cosine similarity threshold `0.93`:

```sql
SELECT
    qe.job_id,
    qe.cached_sql,
    qe.cached_result,
    1 - (qe.embedding <=> $1::vector) AS similarity
FROM question_embeddings qe
JOIN query_jobs qj ON qj.id = qe.job_id
WHERE qe.cache_valid = true
  AND qj.group_id = $2
  AND qj.status = 'COMPLETED'
ORDER BY qe.embedding <=> $1::vector
LIMIT 1
HAVING 1 - (qe.embedding <=> $1::vector) >= 0.93;
```

Note: the access group filter (`qj.group_id = $2`) is mandatory — never return a cached result from a different access group. Threshold is `0.93` (stricter than general RAG) because SQL correctness is brittle.

---

### Stage 3 — Schema Retrieval (DDL Pruning)

**Phase A — Table Retrieval (top 8 candidate tables by cosine similarity):**
```sql
SELECT
    rt.id,
    rt.table_name,
    rt.description,
    te.embed_content,
    1 - (te.embedding <=> $1::vector) AS similarity
FROM table_embeddings te
JOIN registered_tables rt ON rt.id = te.table_id
JOIN group_table_access gta ON gta.table_id = rt.id
WHERE gta.group_id = $2
  AND rt.is_whitelisted = true
ORDER BY te.embedding <=> $1::vector
LIMIT 8;
```

**Phase B — Column Retrieval (top 10 columns per table, PII excluded):**
```sql
SELECT
    rc.column_name,
    rc.data_type,
    rc.description,
    rc.is_pii,
    1 - (ce.embedding <=> $1::vector) AS similarity
FROM column_embeddings ce
JOIN registered_columns rc ON rc.id = ce.column_id
WHERE rc.table_id = $2
  AND rc.is_pii = false
ORDER BY ce.embedding <=> $1::vector
LIMIT 10;
```

**Relationship expansion:** After retrieving top-8 tables, query `table_relationships` to include transitive join-path tables (e.g., if `orders` and `products` are retrieved, `order_items` is automatically included). This prevents missing intermediate join tables.

**DDL Reconstruction:** `DdlReconstructionService` assembles a minimal DDL string from retrieved tables and columns. `ContextBudgetManager` enforces 2500-token ceiling — lowest-similarity tables dropped first if budget exceeded.

---

### Stage 4 — SQL Generation

**Prompt template (resources/prompts/sql-generation-system-prompt.st):**
```
You are a PostgreSQL expert. Generate a single, read-only SELECT query
that answers the user's business question using ONLY the tables and columns
provided in the schema below. Rules:
- Generate only a single SELECT statement
- Do not use any DML or DDL
- Do not include comments in the SQL (no -- or /* */)
- Do not reference tables not in the provided schema
- Use explicit column names, never SELECT *
- Always include appropriate LIMIT clause
- Current date context: {temporalContext}
- Database dialect: PostgreSQL 16

[SCHEMA]
{ddlSubset}

[RELATIONSHIPS]
{relationships}

[EXAMPLES]
{fewShotExamples}

[USER QUESTION]
<user_question>
{normalizedQuestion}
</user_question>

Return JSON with exactly this structure:
{
  "sql": "<single valid SELECT statement>",
  "confidence": <0.0-1.0>,
  "tablesUsed": ["table1", "table2"],
  "reasoning": "<one sentence explaining the approach>"
}
Return only the JSON object. No markdown, no explanation outside the JSON.
```

**Structured output record:**
```java
public record SQLGenerationResult(
    String sql,
    double confidence,
    List<String> tablesUsed,
    String reasoning
) {}
```

Spring AI 1.0.x maps the JSON response to this record via `.call().entity(SQLGenerationResult.class)`.

---

### Stage 5 — AST Validation (JSQLParser)

```java
@Component
public class ASTValidator {

    private final Set<String> whitelistedTables;    // injected from SchemaService

    public ValidationResult validate(String rawSql) {
        Statement statement;
        try {
            statement = CCJSqlParserUtil.parse(rawSql);
        } catch (JSQLParserException e) {
            return ValidationResult.fail("PARSE_ERROR", e.getMessage());
        }

        if (!(statement instanceof Select)) {
            return ValidationResult.fail("NON_SELECT",
                "Only SELECT statements are permitted. Got: " +
                statement.getClass().getSimpleName());
        }

        if (rawSql.trim().contains(";")) {
            return ValidationResult.fail("MULTIPLE_STATEMENTS",
                "Multiple statements detected via semicolon");
        }

        TablesNamesFinder finder = new TablesNamesFinder();
        List<String> referencedTables = finder.getTableList(statement);

        for (String table : referencedTables) {
            if (!whitelistedTables.contains(table.toLowerCase())) {
                return ValidationResult.fail("TABLE_NOT_WHITELISTED",
                    "Table '" + table + "' is not in the allowed whitelist");
            }
        }

        if (rawSql.contains("--") || rawSql.contains("/*")) {
            return ValidationResult.fail("COMMENT_INJECTION",
                "SQL comments are not permitted in generated queries");
        }

        String lowerSql = rawSql.toLowerCase();
        for (String pattern : List.of(
            "information_schema", "pg_catalog", "pg_tables",
            "pg_class", "pg_namespace", "pg_user")) {
            if (lowerSql.contains(pattern)) {
                return ValidationResult.fail("SYSTEM_TABLE_ACCESS",
                    "Access to system tables is not permitted: " + pattern);
            }
        }

        Select select = (Select) statement;
        SelectBody body = select.getSelectBody();
        if (body instanceof PlainSelect plainSelect) {
            for (SelectItem item : plainSelect.getSelectItems()) {
                if (item instanceof AllColumns || item instanceof AllTableColumns) {
                    return ValidationResult.fail("SELECT_STAR",
                        "SELECT * is not permitted. Use explicit column names.");
                }
            }
        }

        return ValidationResult.pass(referencedTables);
    }
}
```

**On failure — correction prompt adds:** original question, rejected SQL, specific error reason, whitelisted table list.

**Max retries: 2.** After 2 failed attempts, job status → `FAILED`, reason stored in `rejection_reason`.

---

### Stage 6 — Safe Query Execution

```java
@Component
public class SafeQueryExecutor {

    private final JdbcTemplate analyticsJdbcTemplate;

    public SafeQueryExecutor(
            @Qualifier("analyticsJdbcTemplate") JdbcTemplate analyticsJdbcTemplate) {
        this.analyticsJdbcTemplate = analyticsJdbcTemplate;
    }

    public QueryExecutionResult execute(String validatedSql, int maxRows) {
        String boundedSql = SqlLimitInjector.ensureLimit(validatedSql, maxRows);

        long startMs = System.currentTimeMillis();
        try {
            // JdbcTemplate uses the analyticsDataSource connection pool
            // querysense_readonly role has statement_timeout=10s at DB level
            List<Map<String, Object>> rows = analyticsJdbcTemplate.queryForList(boundedSql);
            long executionMs = System.currentTimeMillis() - startMs;
            return QueryExecutionResult.success(rows, executionMs);
        } catch (QueryTimeoutException e) {
            return QueryExecutionResult.fail("TIMEOUT",
                "Query exceeded 10-second execution limit");
        } catch (DataAccessException e) {
            return QueryExecutionResult.fail("SQL_ERROR", e.getMessage());
        }
    }
}
```

Note: `JdbcTemplate.queryForList()` is used instead of raw `PreparedStatement` to stay within Spring conventions. The PostgreSQL role-level `statement_timeout` provides the primary timeout enforcement. `JdbcTemplate` throws `QueryTimeoutException` when the role-level timeout fires, which is caught above.

---

### Stage 7 — Result Explanation (SSE Streaming)

```java
// In ResultExplanationStage
public void execute(PipelineContext context) {
    Flux<String> tokenStream = llmClient.streamExplanation(
        systemPrompt,
        buildUserPrompt(context)
    );

    StringBuilder fullExplanation = new StringBuilder();

    tokenStream.subscribe(
        token -> {
            fullExplanation.append(token);
            sseEmitterRegistry.sendEvent(
                context.getJobId(),
                "EXPLANATION_TOKEN",
                Map.of("token", token)
            );
        },
        error -> { /* log, mark job failed */ },
        () -> {
            context.setExplanation(fullExplanation.toString());
            // Stage 8 begins after subscription completes
        }
    );
}
```

**Why only first 20 rows in explanation prompt:** sufficient for pattern recognition; sending 1000 rows costs thousands of tokens for no quality improvement. Configurable via `app.explanation.max-sample-rows=20`.

---

### Stage 8 — Caching, Audit, and Delivery

All writes are non-blocking after SSE stream begins closing:
- Update `query_jobs.status` → `COMPLETED`, set `completed_at`
- Insert `query_results` record
- Insert `question_embeddings` with question embedding and cached result
- Write to Redis: `query:exact:{hash}` → serialized result, TTL 1h
- Write to Redis: `job:status:{jobId}` → `COMPLETED`
- Call `sseEmitterRegistry.complete(jobId)`

---

## 16. REST API Contract

```
# Authentication
POST   /api/v1/auth/register
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh

# Query Execution
POST   /api/v1/queries                       Submit natural language question
GET    /api/v1/queries/{jobId}               Poll job status + full result
GET    /api/v1/queries/{jobId}/stream        SSE stream for live pipeline updates
GET    /api/v1/queries                       List query history (paginated, own queries)

# Schema Management (ADMIN only)
POST   /api/v1/schema/sync                   Trigger schema introspection
GET    /api/v1/schema/tables                 List registered tables with whitelist status
PATCH  /api/v1/schema/tables/{id}/whitelist  Toggle table whitelist status
PUT    /api/v1/schema/tables/{id}/description Update table description
PUT    /api/v1/schema/columns/{id}/description Update column description
POST   /api/v1/schema/columns/{id}/pii       Mark column as PII

# Access Control (ADMIN only)
POST   /api/v1/groups                        Create data access group
POST   /api/v1/groups/{id}/tables            Add table to group whitelist
POST   /api/v1/users/{id}/groups             Assign user to group

# Evaluation (ADMIN only)
POST   /api/v1/evaluation/golden             Add golden query test case
GET    /api/v1/evaluation/golden             List golden queries
POST   /api/v1/evaluation/run                Trigger evaluation run
GET    /api/v1/evaluation/runs               List evaluation run history
GET    /api/v1/evaluation/runs/{id}          Evaluation run detail

# Observability
GET    /api/v1/analytics/cost                LLM cost summary
GET    /api/v1/analytics/accuracy            Query success rate, cache hit rate, retry rate
GET    /actuator/health
GET    /actuator/metrics
```

---

## 17. Complete Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Java | 21 (LTS) |
| Framework | Spring Boot | 3.3.x |
| AI Framework | Spring AI | 1.0.0 |
| Build | Maven | 3.9.x + Maven Wrapper (mvnw) |
| AST Validator | JSQLParser | 4.9 |
| Application DB | PostgreSQL | 16 (pgvector/pgvector:pg16 image) |
| Vector Store | pgvector | 0.7 (HNSW) |
| Cache / Rate Limit | Redis | 7 |
| Migrations | Flyway | Auto-configured via Spring Boot |
| Analytics DB | PostgreSQL | 16 (postgres:16-alpine image) |
| SQL Generation | Groq (llama-3.3-70b-versatile) | via WebClient |
| Explanation | Groq (llama-3.3-70b-versatile) | via WebClient |
| Embeddings | nomic-embed-text | via Ollama (local) |
| Resilience | Resilience4j | via Spring Boot starter |
| Testing | JUnit 5 + Mockito + Testcontainers | — |
| Containerization | Docker + Docker Compose | — |
| CI/CD | GitHub Actions | — |
| Deployment | Railway | — |

---

## 18. Package Structure

```
querysense/
├── mvnw                                          # Maven wrapper (required for Docker build)
├── mvnw.cmd
├── .mvn/wrapper/maven-wrapper.properties
├── pom.xml
├── src/
│   └── main/
│       ├── java/
│       │   └── com/querysense/
│       │       ├── QuerySenseApplication.java
│       │       ├── config/
│       │       │   ├── SecurityConfig.java
│       │       │   ├── AsyncConfig.java
│       │       │   ├── DataSourceConfig.java
│       │       │   ├── GroqConfig.java          (WebClient bean for Groq)
│       │       │   ├── RedisConfig.java
│       │       │   └── OpenApiConfig.java
│       │       ├── api/
│       │       │   ├── controller/
│       │       │   │   ├── AuthController.java
│       │       │   │   ├── QueryController.java
│       │       │   │   ├── SchemaController.java
│       │       │   │   ├── AccessGroupController.java
│       │       │   │   ├── EvaluationController.java
│       │       │   │   └── AnalyticsController.java
│       │       │   ├── dto/
│       │       │   │   ├── request/
│       │       │   │   │   ├── QueryRequest.java
│       │       │   │   │   ├── GoldenQueryRequest.java
│       │       │   │   │   └── TableDescriptionRequest.java
│       │       │   │   └── response/
│       │       │   │       ├── QueryJobResponse.java
│       │       │   │       ├── QueryResultResponse.java
│       │       │   │       ├── EvaluationRunResponse.java
│       │       │   │       └── SchemaTableResponse.java
│       │       │   └── exception/
│       │       │       ├── GlobalExceptionHandler.java
│       │       │       ├── QueryRejectionException.java
│       │       │       ├── SchemaNotFoundException.java
│       │       │       └── RateLimitExceededException.java
│       │       ├── domain/
│       │       │   ├── entity/
│       │       │   │   ├── User.java
│       │       │   │   ├── DataAccessGroup.java
│       │       │   │   ├── UserGroupMembership.java
│       │       │   │   ├── RegisteredTable.java
│       │       │   │   ├── RegisteredColumn.java
│       │       │   │   ├── TableRelationship.java
│       │       │   │   ├── GroupTableAccess.java
│       │       │   │   ├── QueryJob.java
│       │       │   │   ├── QueryResult.java
│       │       │   │   ├── SqlGenerationAttempt.java
│       │       │   │   ├── LlmCallLog.java
│       │       │   │   ├── GoldenQuery.java
│       │       │   │   ├── EvaluationRun.java
│       │       │   │   └── EvaluationResult.java
│       │       │   ├── enums/
│       │       │   │   ├── JobStatus.java
│       │       │   │   ├── QueryIntent.java
│       │       │   │   ├── ValidationFailureReason.java
│       │       │   │   └── EvaluationFailureReason.java
│       │       │   └── repository/
│       │       │       ├── UserRepository.java
│       │       │       ├── DataAccessGroupRepository.java
│       │       │       ├── RegisteredTableRepository.java
│       │       │       ├── RegisteredColumnRepository.java
│       │       │       ├── TableRelationshipRepository.java
│       │       │       ├── QueryJobRepository.java
│       │       │       ├── QueryResultRepository.java
│       │       │       ├── SqlGenerationAttemptRepository.java
│       │       │       ├── LlmCallLogRepository.java
│       │       │       ├── GoldenQueryRepository.java
│       │       │       ├── EvaluationRunRepository.java
│       │       │       └── EvaluationResultRepository.java
│       │       ├── service/
│       │       │   ├── QueryOrchestrationService.java
│       │       │   ├── SchemaService.java
│       │       │   ├── EvaluationService.java
│       │       │   ├── AccessGroupService.java
│       │       │   ├── AuditService.java
│       │       │   ├── RateLimitService.java
│       │       │   └── AuthService.java
│       │       ├── pipeline/
│       │       │   ├── TextToSqlPipelineExecutor.java
│       │       │   ├── stage/
│       │       │   │   ├── QueryPreProcessingStage.java
│       │       │   │   ├── SemanticCacheStage.java
│       │       │   │   ├── SchemaRetrievalStage.java
│       │       │   │   ├── SqlGenerationStage.java
│       │       │   │   ├── ASTValidationStage.java
│       │       │   │   ├── QueryExecutionStage.java
│       │       │   │   ├── ResultExplanationStage.java
│       │       │   │   └── CachingAndAuditStage.java
│       │       │   ├── context/
│       │       │   │   ├── PipelineContext.java
│       │       │   │   └── ContextBudgetManager.java
│       │       │   └── retry/
│       │       │       ├── CorrectionPromptBuilder.java
│       │       │       └── RetryPolicy.java
│       │       ├── ai/
│       │       │   ├── client/
│       │       │   │   ├── LLMClient.java
│       │       │   │   └── EmbeddingClientWrapper.java
│       │       │   ├── model/
│       │       │   │   ├── SQLGenerationResult.java
│       │       │   │   └── ExplanationResult.java
│       │       │   ├── prompt/
│       │       │   │   ├── SqlGenerationPromptTemplate.java
│       │       │   │   └── ResultExplanationPromptTemplate.java
│       │       │   └── cache/
│       │       │       ├── ExactQueryCacheManager.java
│       │       │       └── SemanticQueryCacheManager.java
│       │       ├── schema/
│       │       │   ├── introspection/
│       │       │   │   ├── SchemaIntrospector.java        # uses introspectJdbcTemplate
│       │       │   │   └── SchemaIntrospectionResult.java
│       │       │   ├── embedding/
│       │       │   │   ├── SchemaEmbeddingService.java
│       │       │   │   └── DdlReconstructionService.java
│       │       │   └── retrieval/
│       │       │       ├── SemanticSchemaRetriever.java
│       │       │       └── RetrievedSchemaContext.java
│       │       ├── validation/
│       │       │   ├── ASTValidator.java
│       │       │   ├── ValidationResult.java
│       │       │   ├── WhitelistEnforcer.java
│       │       │   └── SqlLimitInjector.java
│       │       ├── execution/
│       │       │   ├── SafeQueryExecutor.java             # uses analyticsJdbcTemplate
│       │       │   ├── QueryExecutionResult.java
│       │       │   └── ResultSetMapper.java
│       │       ├── preprocessing/
│       │       │   ├── QueryNormalizer.java
│       │       │   ├── TemporalExtractor.java
│       │       │   ├── IntentClassifier.java
│       │       │   └── InjectionGuard.java
│       │       ├── security/
│       │       │   ├── JwtTokenProvider.java
│       │       │   ├── JwtAuthenticationFilter.java
│       │       │   └── UserPrincipal.java
│       │       └── infrastructure/
│       │           ├── sse/
│       │           │   └── SseEmitterRegistry.java
│       │           └── hashing/
│       │               └── QuestionHasher.java
│       └── resources/
│           ├── application.yml
│           ├── application-local.yml
│           ├── application-prod.yml
│           ├── prompts/
│           │   ├── sql-generation-system-prompt.st
│           │   └── result-explanation-system-prompt.st
│           └── db/migration/
│               ├── V1__create_users.sql
│               ├── V2__create_data_access_groups.sql
│               ├── V3__create_user_group_memberships.sql
│               ├── V4__create_registered_tables.sql
│               ├── V5__create_registered_columns.sql
│               ├── V6__create_table_relationships.sql
│               ├── V7__create_group_table_access.sql
│               ├── V8__create_query_jobs.sql
│               ├── V9__create_query_results.sql
│               ├── V10__create_sql_generation_attempts.sql
│               ├── V11__create_llm_call_logs.sql
│               ├── V12__create_golden_queries.sql
│               ├── V13__create_evaluation_runs.sql
│               ├── V14__create_evaluation_results.sql
│               ├── V15__create_pgvector_extension.sql
│               ├── V16__create_table_embeddings.sql
│               ├── V17__create_column_embeddings.sql
│               ├── V18__create_question_embeddings.sql
│               └── V19__create_relational_indexes.sql
├── src/test/
│   └── java/com/querysense/
│       ├── integration/
│       │   ├── QueryApiIntegrationTest.java
│       │   ├── SchemaIntrospectionIntegrationTest.java
│       │   └── EvaluationIntegrationTest.java
│       ├── pipeline/
│       │   ├── QueryPreProcessingStageTest.java
│       │   ├── SemanticCacheStageTest.java
│       │   ├── SchemaRetrievalStageTest.java
│       │   ├── SqlGenerationStageTest.java
│       │   ├── ASTValidationStageTest.java
│       │   ├── QueryExecutionStageTest.java
│       │   └── CorrectionLoopTest.java
│       ├── validation/
│       │   ├── ASTValidatorTest.java
│       │   ├── WhitelistEnforcerTest.java
│       │   └── SqlLimitInjectorTest.java
│       └── preprocessing/
│           ├── TemporalExtractorTest.java
│           ├── IntentClassifierTest.java
│           └── InjectionGuardTest.java
├── evaluation/
│   ├── evaluate.py
│   ├── sql_similarity.py
│   ├── golden_dataset.json
│   └── requirements.txt
├── docker/
│   ├── postgres-app/
│   │   └── init.sql
│   ├── postgres-analytics/
│   │   ├── init.sql
│   │   └── seed.sql
│   └── redis/
│       └── redis.conf
├── docker-compose.yml
├── docker-compose.prod.yml
└── Dockerfile
```

---

## 19. Docker Compose (Corrected)

```yaml
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      SPRING_PROFILES_ACTIVE: local
      APP_DB_URL: jdbc:postgresql://postgres-app:5432/querysense
      APP_DB_USERNAME: querysense
      APP_DB_PASSWORD: ${APP_DB_PASSWORD}
      ANALYTICS_DB_URL: jdbc:postgresql://postgres-analytics:5432/analytics
      ANALYTICS_DB_USERNAME: querysense_readonly
      ANALYTICS_DB_PASSWORD: ${ANALYTICS_READONLY_PASSWORD}
      ANALYTICS_INTROSPECT_USERNAME: querysense_introspect
      ANALYTICS_INTROSPECT_PASSWORD: ${ANALYTICS_INTROSPECT_PASSWORD}
      REDIS_HOST: redis
      GROQ_API_KEY: ${GROQ_API_KEY}
      MODEL_SQL: ${MODEL_SQL:-llama-3.3-70b-versatile}
      MODEL_EXPLANATION: ${MODEL_EXPLANATION:-llama-3.3-70b-versatile}
      OLLAMA_BASE_URL: http://ollama:11434
    depends_on:
      postgres-app:
        condition: service_healthy
      postgres-analytics:
        condition: service_healthy
      redis:
        condition: service_healthy
      ollama:
        condition: service_healthy

  postgres-app:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: querysense
      POSTGRES_USER: querysense
      POSTGRES_PASSWORD: ${APP_DB_PASSWORD}
    ports:
      - "5432:5432"
    volumes:
      - postgres_app_data:/var/lib/postgresql/data
      - ./docker/postgres-app/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U querysense"]
      interval: 5s
      timeout: 5s
      retries: 5

  postgres-analytics:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: analytics
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${ANALYTICS_SUPERUSER_PASSWORD}
    ports:
      - "5433:5432"
    volumes:
      - postgres_analytics_data:/var/lib/postgresql/data
      - ./docker/postgres-analytics/init.sql:/docker-entrypoint-initdb.d/01-init.sql
      - ./docker/postgres-analytics/seed.sql:/docker-entrypoint-initdb.d/02-seed.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    command: redis-server
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:11434/api/tags || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
    # Pull the embedding model on first start
    # Run manually once: docker exec querysense-ollama-1 ollama pull nomic-embed-text

volumes:
  postgres_app_data:
  postgres_analytics_data:
  redis_data:
  ollama_data:
```

**Dockerfile (corrected — uses mvnw):**
```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /build
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .
RUN ./mvnw dependency:go-offline -q
COPY src ./src
RUN ./mvnw package -DskipTests -q

FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app
COPY --from=builder /build/target/querysense-*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java",
  "-XX:+UseContainerSupport",
  "-XX:MaxRAMPercentage=75.0",
  "-Djava.security.egd=file:/dev/./urandom",
  "-jar", "app.jar"]
```

---

## 20. Security Considerations

**Database Isolation (Most Important):** Three independent layers:
1. PostgreSQL role privileges: `querysense_readonly` has only SELECT on explicitly whitelisted tables
2. JSQLParser AST validation: all non-SELECT statements rejected at application layer
3. DataSource isolation: `analyticsDataSource` bean is configured with `querysense_readonly` credentials only

**JWT:** RS256 asymmetric signing. Access token TTL: 15 minutes. Refresh token TTL: 7 days, stored hashed (BCrypt). Refresh token rotation on every use.

**PII Exclusion:** `is_pii = true` columns excluded from all LLM prompts via `WHERE rc.is_pii = false` in schema retrieval queries.

**Prompt Injection:** Natural language question wrapped in `<user_question>` XML delimiters. `InjectionGuard` provides early-reject on SQL keyword detection.

**Rate Limiting:** 20 queries/hour per user, 5/hour per IP unauthenticated. Redis `INCR` + `EXPIRE` with atomic Lua script.

**Audit Immutability:** `query_jobs`, `query_results`, `sql_generation_attempts` are append-only by application convention and by PostgreSQL role privilege (application role has no DELETE on audit tables).

---

## 21. Concepts Intentionally Excluded

- **Multi-Agent Systems:** Not needed for single-question analytical queries at v1
- **LangChain4j / LangGraph4j:** Abstractions hide design decisions that are the interview talking points
- **Dedicated Vector Databases (Pinecone, Qdrant):** pgvector's SQL-native access group filtering is architecturally superior for this relational-vector join requirement
- **BM25 / Hybrid Retrieval:** v2 candidate; semantic similarity sufficient for schema retrieval at v1
- **Fine-Tuning:** Requires hundreds of labeled schema-specific pairs; few-shot prompting achieves comparable accuracy with zero training overhead
- **Streaming SQL Results:** Result sets capped at 1000 rows; streaming explanation provides the progressive UX value instead
- **Python for Orchestration:** Entire application runtime in Java; Python only for offline evaluation script

---

*Architecture v1.1 — reviewed, corrected, and ready for AI-assisted implementation.*
