# MASTER_PROMPTS.md — QuerySense AI Development Playbook
### Version 1.1 | Use this file to control every AI coding session for this project

---

## HOW TO USE THIS FILE

1. Every AI coding session MUST begin with PROMPT_00 + PROMPT_00_5 (copy-paste both, back to back).
2. Then add the prompt for the current phase you are implementing.
3. Never skip a phase. Never run two phases in the same session unless the phase explicitly says it can be combined.
4. If the AI generates something outside the scope of the current prompt, stop it and redirect using the rules in PROMPT_00_5.
5. After each phase, run the manual verification checklist from the roadmap before starting the next phase.

---

## PROMPT_00 — Project Context (Send at the start of EVERY session)

```
You are implementing QuerySense — an Intelligent SQL Analytics Agent built with Java 21 and Spring Boot 3.3.x.

This project is governed by a single architectural source of truth. You must follow it exactly. Do not suggest improvements to the architecture. Do not introduce technologies not listed. Do not restructure packages. Do not add files not specified.

TECHNOLOGY STACK (authoritative — do not deviate):
- Language: Java 21 (use records, sealed interfaces, pattern matching where appropriate)
- Framework: Spring Boot 3.3.x
- AI Framework: Spring AI 1.0.0 (used for Ollama embeddings only — inject EmbeddingModel, NOT ChatClient or ChatClient.Builder)
- LLM Client: Groq API via Spring WebClient (OpenAI-compatible REST) — NOT OpenAI SDK, NOT spring-ai-openai-starter
- Embedding: Ollama local (nomic-embed-text, 768 dims) — runs in Docker, zero recurring API cost
- Build: Maven 3.9.x with Maven Wrapper (mvnw)
- AST Validation: JSQLParser 4.9
- Application DB: PostgreSQL 16 with pgvector extension (pgvector/pgvector:pg16 image)
- Cache: Redis 7
- Migrations: Flyway (auto-configured, bound to @Primary DataSource only)
- Testing: JUnit 5 + Mockito + Testcontainers
- Resilience: Resilience4j

DATASOURCE ARCHITECTURE (critical — never violate):
There are THREE DataSource beans:
1. appDataSource (@Primary) — application database, all JPA repositories, Flyway
2. analyticsDataSource — analytics DB, querysense_readonly role, used ONLY by SafeQueryExecutor via analyticsJdbcTemplate
3. introspectDataSource — analytics DB, querysense_introspect role, used ONLY by SchemaIntrospector via introspectJdbcTemplate

Flyway runs ONLY against appDataSource. Never configure flyway.url/username/password separately.
JPA repositories use ONLY appDataSource.
Never inject a JdbcTemplate without specifying which DataSource it wraps.

ASYNC ARCHITECTURE (critical):
- Pipeline dispatched via @Async("pipelineExecutor") in TextToSqlPipelineExecutor
- One PipelineContext instance per job — never shared between threads
- PipelineContext fields are plain (non-volatile, non-synchronized) — safe because accessed by one thread only
- ThreadPoolTaskExecutor: core=4, max=10, queue=50

AI PROVIDER API (critical):
- Groq chat: inject WebClient (built from GroqConfig bean), call POST /chat/completions with OpenAI-compatible JSON body
- SQL generation: blocking WebClient call, parse JSON response manually, deserialize to SQLGenerationResult record
- Streaming explanation: WebClient bodyToFlux(String.class) with stream:true, parse SSE lines manually
- Embeddings: Spring AI OllamaEmbeddingModel — inject EmbeddingModel (not EmbeddingClient), call embedForResponse(List.of(text))
- Vector dimensions: nomic-embed-text = 768 — all vector columns must be vector(768), NOT vector(1536)

SSE LIFECYCLE:
- SseEmitter timeout: 120_000ms
- Register emitter BEFORE dispatching async pipeline
- Pipeline stages send events via SseEmitterRegistry.sendEvent() — never hold direct emitter reference in stage
- SseEmitterRegistry.complete() called exactly once at end of CachingAndAuditStage

PACKAGE ROOT: com.querysense
All classes go in the package structure defined in the architecture. Do not create new packages.

NAMING CONVENTIONS:
- Entities: singular PascalCase (User, QueryJob, RegisteredTable)
- DTOs: [Name]Request, [Name]Response
- Services: [Name]Service
- Pipeline stages: [Name]Stage
- All UUID primary keys, generated with gen_random_uuid()
- All timestamps: TIMESTAMPTZ with DEFAULT now()

CODE QUALITY RULES:
- No field injection (@Autowired on fields) — constructor injection only
- No Lombok — write constructors, getters, setters manually or use Java records
- All repository methods return Optional<T> for single-result queries
- Every service method that writes data must be @Transactional
- No @Transactional on read-only methods unless explicitly needed
- Exception handling: throw domain-specific exceptions, caught by GlobalExceptionHandler
- No System.out.println — use SLF4J Logger
```

---

## PROMPT_00_5 — Rules Confirmation (Send immediately after PROMPT_00 in every session)

```
Before writing any code, confirm you understand these rules by answering YES or NO to each:

1. Will you add any technology not in the stack above? (Expected: NO)
2. Will you create any package not in the defined package structure? (Expected: NO)
3. Will you use @Autowired field injection anywhere? (Expected: NO)
4. Will you use Lombok? (Expected: NO)
5. Will you configure Flyway to run against analyticsDataSource or introspectDataSource? (Expected: NO)
6. Will you use spring-ai-openai-starter or OpenAI ChatClient instead of Groq WebClient + Ollama EmbeddingModel? (Expected: NO)
7. Will you share a PipelineContext instance between two pipeline executions? (Expected: NO)
8. Will you use JdbcTemplate in SafeQueryExecutor without the @Qualifier("analyticsJdbcTemplate") annotation? (Expected: NO)

If you answered YES to any of these, stop and re-read PROMPT_00.

After confirming, state: "Rules confirmed. Ready to implement [PHASE NAME]."
Then wait for the phase prompt before generating any code.
```

---

## PROMPT_01 — Project Scaffolding & Infrastructure

```
PHASE: 01 — Project Scaffolding & Infrastructure
PREREQUISITE: None (first phase)

GOAL: Create a compiling, running Spring Boot project with all dependencies, three DataSource beans, Flyway migrations V1–V7 (users through group_table_access), Docker Compose, and a passing health endpoint.

GENERATE EXACTLY THESE FILES (no others):
- pom.xml
- mvnw, mvnw.cmd, .mvn/wrapper/maven-wrapper.properties
- src/main/resources/application.yml
- src/main/resources/application-local.yml
- src/main/java/com/querysense/QuerySenseApplication.java
- src/main/java/com/querysense/config/DataSourceConfig.java
- src/main/java/com/querysense/config/AsyncConfig.java
- src/main/java/com/querysense/config/RedisConfig.java
- src/main/java/com/querysense/config/OpenApiConfig.java
- src/main/resources/db/migration/V1__create_users.sql through V7__create_group_table_access.sql
- docker/postgres-app/init.sql
- docker/postgres-analytics/init.sql
- docker/postgres-analytics/seed.sql
- docker-compose.yml
- Dockerfile
- .env.example

IMPLEMENTATION RULES:
- pom.xml must include: spring-boot-starter-web, spring-boot-starter-security, spring-boot-starter-data-jpa, spring-boot-starter-data-redis, spring-boot-starter-validation, spring-boot-starter-actuator, spring-boot-starter-webflux (for Groq WebClient), spring-ai-bom (1.0.0), spring-ai-ollama-spring-boot-starter (for local embeddings), spring-ai-pgvector-store-spring-boot-starter, jsqlparser (4.9), flyway-core, postgresql, resilience4j-spring-boot3, testcontainers, spring-boot-testcontainers, java-version: 21
- DO NOT add spring-ai-openai-spring-boot-starter — Groq is called via WebClient
- DataSourceConfig.java must define exactly three beans: appDataSource (@Primary @ConfigurationProperties("spring.datasource.app")), analyticsDataSource (@ConfigurationProperties("spring.datasource.analytics")), introspectDataSource (@ConfigurationProperties("spring.datasource.introspect")), plus analyticsJdbcTemplate and introspectJdbcTemplate
- AsyncConfig.java must implement AsyncConfigurer, define pipelineExecutor bean: core=4, max=10, queue=50, CallerRunsPolicy, waitForTasksToCompleteOnShutdown=true, awaitTermination=30s
- application.yml must define spring.datasource.app, spring.datasource.analytics, spring.datasource.introspect connection pool sections — NO flyway.url or flyway.username
- Flyway must auto-configure from @Primary DataSource — no explicit flyway datasource properties
- docker-compose.yml must use pgvector/pgvector:pg16 for postgres-app and postgres:16-alpine for postgres-analytics
- docker/postgres-app/init.sql must NOT create vector extension (Flyway migration V15 handles it)
- The analytics init.sql must create querysense_readonly and querysense_introspect roles and a sample schema (orders, order_items, products, customers tables) with appropriate GRANT statements
- Dockerfile must use mvnw (not bare mvn), copy .mvn directory, run dependency:go-offline before COPY src

VALIDATION REQUIREMENTS:
- Project must compile: ./mvnw compile -q
- docker compose up must start all four services healthy
- GET /actuator/health must return {"status":"UP"}
- Flyway must run V1–V7 automatically on startup and create all seven tables in the querysense DB

STOPPING POINT: Stop after generating all listed files. Do not begin Phase 02 work.
```

---

## PROMPT_02 — Domain Layer (Entities & Repositories)

```
PHASE: 02 — Domain Layer
PREREQUISITE: Phase 01 complete and verified (project compiles, health endpoint returns UP, Flyway ran V1–V7)

GOAL: Create all JPA entities, enums, and Spring Data JPA repositories for the application database.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/domain/entity/ — all 14 entity classes
- src/main/java/com/querysense/domain/enums/ — JobStatus, QueryIntent, ValidationFailureReason, EvaluationFailureReason
- src/main/java/com/querysense/domain/repository/ — all 12 repository interfaces

DO NOT generate:
- Service classes (Phase 03)
- DTOs (Phase 04)
- Controllers (Phase 04)
- Any Flyway migrations (already defined in architecture)

IMPLEMENTATION RULES FOR ENTITIES:
- All entities use @Entity, @Table(name="...") with exact table names from the schema
- All PKs: @Id @GeneratedValue(strategy = GenerationType.AUTO) @Column(columnDefinition = "uuid") private UUID id
- All timestamps: @Column(columnDefinition = "TIMESTAMPTZ") private OffsetDateTime createdAt (use @CreationTimestamp for createdAt, @UpdateTimestamp for updatedAt where applicable)
- Relationships: use @ManyToOne(fetch = FetchType.LAZY) by default — NEVER FetchType.EAGER
- Use @Column(nullable = false) where NOT NULL is defined in schema
- No @Data (no Lombok) — generate explicit constructors, getters, setters
- Use Java records for value objects that are not entities (TemporalContext, ValidationResult, QueryExecutionResult, RetrievedSchemaContext)
- QueryJob entity: status field is JobStatus enum, mapped with @Enumerated(EnumType.STRING)
- No bidirectional relationships unless absolutely necessary — use unidirectional @ManyToOne

IMPLEMENTATION RULES FOR REPOSITORIES:
- All repositories extend JpaRepository<Entity, UUID>
- QueryJobRepository: add findByUserId(UUID userId, Pageable pageable), findByQuestionHash(String hash), findByStatus(JobStatus status)
- RegisteredTableRepository: add findByIsWhitelistedTrue(), findBySchemaNameAndTableName(String schema, String table)
- RegisteredColumnRepository: add findByTableIdAndIsPiiFalse(UUID tableId), findByTableId(UUID tableId)
- No @Query annotations with native SQL unless absolutely necessary — prefer Spring Data method names
- All repositories are in package com.querysense.domain.repository

VALIDATION REQUIREMENTS:
- ./mvnw compile -q must pass
- All entities must map cleanly to existing Flyway migrations (no missing columns, no wrong types)
- Write ONE test: EntityMappingTest.java in src/test — use @DataJpaTest with Testcontainers PostgreSQL to verify all entities load without LazyInitializationException or mapping errors

STOPPING POINT: Stop after all entity, enum, and repository files are generated. Do not begin Phase 03.
```

---

## PROMPT_03 — Security Layer (JWT + Spring Security)

```
PHASE: 03 — Security Layer
PREREQUISITE: Phase 02 complete and verified

GOAL: Implement complete JWT authentication with Spring Security. Register/login endpoints working. All other endpoints return 401 without valid JWT.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/security/JwtTokenProvider.java
- src/main/java/com/querysense/security/JwtAuthenticationFilter.java
- src/main/java/com/querysense/security/UserPrincipal.java
- src/main/java/com/querysense/config/SecurityConfig.java
- src/main/java/com/querysense/service/AuthService.java
- src/main/java/com/querysense/api/controller/AuthController.java
- src/main/java/com/querysense/api/dto/request/RegisterRequest.java
- src/main/java/com/querysense/api/dto/request/LoginRequest.java
- src/main/java/com/querysense/api/dto/response/AuthResponse.java
- src/main/java/com/querysense/api/exception/GlobalExceptionHandler.java
- src/main/java/com/querysense/api/exception/QueryRejectionException.java
- src/main/java/com/querysense/api/exception/SchemaNotFoundException.java
- src/main/java/com/querysense/api/exception/RateLimitExceededException.java

ADD TO pom.xml:
- jjwt-api, jjwt-impl, jjwt-jackson (io.jsonwebtoken, version 0.12.x)
- spring-security-test (test scope)

IMPLEMENTATION RULES:
- JWT signing: HS256 with a secret key loaded from ${JWT_SECRET} environment variable
- Access token TTL: 15 minutes
- Refresh token TTL: 7 days, stored hashed (BCrypt, strength 12) in users table — add a refresh_tokens table via a new Flyway migration V20__create_refresh_tokens.sql
- JwtAuthenticationFilter extends OncePerRequestFilter, reads Bearer token from Authorization header
- SecurityConfig: permit POST /api/v1/auth/register and POST /api/v1/auth/login without auth; require auth for all other paths; stateless session management; add JwtAuthenticationFilter before UsernamePasswordAuthenticationFilter
- UserPrincipal implements UserDetails, wraps User entity, exposes userId (UUID) and groupId (UUID) as additional fields
- AuthService: register() creates User, login() validates credentials and returns JWTs, refresh() rotates refresh token
- GlobalExceptionHandler: handle QueryRejectionException (400), SchemaNotFoundException (404), RateLimitExceededException (429), MethodArgumentNotValidException (400), AccessDeniedException (403), AuthenticationException (401), generic Exception (500) — all return structured ErrorResponse with timestamp, status, message

VALIDATION REQUIREMENTS:
- POST /api/v1/auth/register with valid JSON returns 201 + AuthResponse (accessToken, refreshToken, userId)
- POST /api/v1/auth/login returns 200 + AuthResponse
- GET /actuator/health (no token) returns 200
- GET /api/v1/queries (no token) returns 401
- GET /api/v1/queries (invalid token) returns 401
- Write JwtTokenProviderTest: verify token generation, parsing, and expiry

STOPPING POINT: Security layer only. Do not begin schema or pipeline work.
```

---

## PROMPT_04 — Schema Registry & Introspection

```
PHASE: 04 — Schema Registry & Introspection
PREREQUISITE: Phase 03 complete and verified

GOAL: Implement schema discovery from the analytics database, schema registry CRUD, and the admin API for schema management.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/schema/introspection/SchemaIntrospector.java
- src/main/java/com/querysense/schema/introspection/SchemaIntrospectionResult.java
- src/main/java/com/querysense/service/SchemaService.java
- src/main/java/com/querysense/api/controller/SchemaController.java
- src/main/java/com/querysense/api/controller/AccessGroupController.java
- src/main/java/com/querysense/service/AccessGroupService.java
- src/main/java/com/querysense/api/dto/response/SchemaTableResponse.java
- src/main/java/com/querysense/api/dto/request/TableDescriptionRequest.java

IMPLEMENTATION RULES:
- SchemaIntrospector uses @Qualifier("introspectJdbcTemplate") JdbcTemplate — NEVER appDataSource or analyticsDataSource
- SchemaIntrospector queries information_schema.tables and information_schema.columns to discover tables and columns in the analytics DB
- SchemaIntrospector also queries information_schema.table_constraints and information_schema.key_column_usage to discover foreign key relationships
- SchemaService.syncSchema(): calls SchemaIntrospector, upserts results into registered_tables and registered_columns using appDataSource (via JPA repositories), updates last_synced_at, increments schema:version counter in Redis
- SchemaService is @Transactional for syncSchema() method
- All newly discovered tables have is_whitelisted = false by default — admin must explicitly whitelist
- SchemaController requires ADMIN role (use @PreAuthorize("hasRole('ADMIN')") — ensure @EnableMethodSecurity in SecurityConfig)
- PATCH /api/v1/schema/tables/{id}/whitelist toggles is_whitelisted
- PUT /api/v1/schema/tables/{id}/description and PUT /api/v1/schema/columns/{id}/description update description fields
- POST /api/v1/schema/columns/{id}/pii toggles is_pii
- AccessGroupController: POST /api/v1/groups (create group), POST /api/v1/groups/{id}/tables (add table to group whitelist → inserts into group_table_access), POST /api/v1/users/{id}/groups (assign user to group)

VALIDATION REQUIREMENTS:
- POST /api/v1/schema/sync (as ADMIN) must discover all tables from analytics DB and populate registered_tables and registered_columns
- Verify in DB: SELECT count(*) FROM registered_tables returns 4 (orders, order_items, products, customers from seed data)
- Verify all new tables have is_whitelisted = false
- Write SchemaIntrospectionTest: uses @Autowired introspectJdbcTemplate and verifies it connects to analytics DB (Testcontainers), discovers tables, and confirms it does NOT connect to appDataSource

STOPPING POINT: Schema registry only. Do not begin embedding or pipeline work.
```

---

## PROMPT_05 — Flyway Migrations V8–V19 & pgvector Setup

```
PHASE: 05 — Remaining Migrations & pgvector
PREREQUISITE: Phase 04 complete and verified

GOAL: Add Flyway migrations V8–V19 (query jobs through indexes and vector tables).

GENERATE EXACTLY THESE FILES:
- src/main/resources/db/migration/V8__create_query_jobs.sql through V19__create_relational_indexes.sql

IMPLEMENTATION RULES:
- Generate each migration file exactly as defined in the architecture database design section
- V15__create_pgvector_extension.sql must contain ONLY: CREATE EXTENSION IF NOT EXISTS vector;
- This extension is enabled on the application DB (querysense), which uses the pgvector/pgvector:pg16 Docker image — it is already available, just needs to be created
- V16–V18 define table_embeddings, column_embeddings, question_embeddings — use vector(768) type (nomic-embed-text = 768 dims)
- V16–V18 must also include the HNSW index CREATE INDEX statements (WITH m=16, ef_construction=64, vector_cosine_ops)
- V19 contains all relational indexes from the architecture — copy exactly
- Migrations must be idempotent where possible (use IF NOT EXISTS)
- Do NOT add any columns or constraints not in the architecture

VALIDATION REQUIREMENTS:
- ./mvnw compile -q passes
- docker compose down -v && docker compose up — Flyway must run V1–V19 successfully
- SELECT count(*) FROM information_schema.tables WHERE table_schema='public' in querysense DB returns 19 tables
- \d table_embeddings in psql shows embedding column as vector(768)
- SELECT * FROM pg_indexes WHERE tablename='table_embeddings' shows the HNSW index

STOPPING POINT: Migrations only. Do not begin AI client or pipeline work.
```

---

## PROMPT_06 — AI Clients & Embedding Service

```
PHASE: 06 — AI Clients & Embedding Service
PREREQUISITE: Phase 05 complete and verified

GOAL: Implement LLMClient (Spring AI 1.0.x), EmbeddingClientWrapper, SchemaEmbeddingService, and DdlReconstructionService.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/ai/client/LLMClient.java
- src/main/java/com/querysense/ai/client/EmbeddingClientWrapper.java
- src/main/java/com/querysense/ai/model/SQLGenerationResult.java
- src/main/java/com/querysense/ai/model/ExplanationResult.java
- src/main/java/com/querysense/config/GroqConfig.java   (WebClient bean configured with Groq base URL + API key)
- src/main/java/com/querysense/schema/embedding/SchemaEmbeddingService.java
- src/main/java/com/querysense/schema/embedding/DdlReconstructionService.java
- src/main/resources/prompts/sql-generation-system-prompt.st
- src/main/resources/prompts/result-explanation-system-prompt.st

IMPLEMENTATION RULES FOR LLMClient:
- Inject WebClient (built in GroqConfig from ${app.ai.groq.api-key} and ${app.ai.groq.base-url}) — NOT ChatClient, NOT OpenAI SDK
- Inject @Value("${app.ai.model.sql}") sqlModel and @Value("${app.ai.model.explanation}") explanationModel
- generateSql(String systemPrompt, String userPrompt):
  * POST to /chat/completions with body: { model, temperature: 0.0, max_tokens: 1000, messages: [{system}, {user}] }
  * Use WebClient.post().bodyValue(requestBody).retrieve().bodyToMono(String.class).block()
  * Parse OpenAI-compatible JSON response: choices[0].message.content → strip ```json fences → ObjectMapper.readValue → SQLGenerationResult
- streamExplanation(String systemPrompt, String userPrompt):
  * POST with stream: true → WebClient bodyToFlux(String.class)
  * Filter lines starting with "data: ", strip prefix, parse delta.content, return Flux<String>
- LlmCallLog saving happens in CachingAndAuditStage (simpler) — LLMClient returns token metadata via a wrapper record

IMPLEMENTATION RULES FOR SQLGenerationResult:
- Java record: SQLGenerationResult(String sql, double confidence, List<String> tablesUsed, String reasoning)
- JSON field names must match exactly: "sql", "confidence", "tablesUsed", "reasoning"
- Use @JsonProperty if needed for camelCase matching

IMPLEMENTATION RULES FOR EmbeddingClientWrapper:
- Inject EmbeddingModel (Spring AI OllamaEmbeddingModel — auto-configured from spring-ai-ollama-spring-boot-starter)
- The model is nomic-embed-text (768 dims) running locally in Ollama Docker container
- embed(String text): returns float[] from embeddingModel.embedForResponse(List.of(text)).getResults().get(0).getOutput()
- embedToList(String text): returns List<Double> (for pgvector JDBC insert compatibility)
- IMPORTANT: all vector columns are vector(768) — do NOT pass 1536-element arrays

IMPLEMENTATION RULES FOR SchemaEmbeddingService:
- embedAllTables(): for each whitelisted registered_table, build embed_content string as "table_name: {name}\ndescription: {desc}\ncolumns: {col1 (type), col2 (type)...}", call EmbeddingClientWrapper.embed(), upsert into table_embeddings
- embedAllColumns(): for each registered_column (is_pii=false), build embed_content as "table.column (type): description", upsert into column_embeddings
- Both methods called by SchemaService.syncSchema() after schema discovery
- Use native @Query or JdbcTemplate (appDataSource) for the upsert into table_embeddings and column_embeddings — Spring Data JPA save() is acceptable

IMPLEMENTATION RULES FOR DdlReconstructionService:
- reconstructDdl(RetrievedSchemaContext context): builds a DDL string from retrieved tables and columns
- Format: "-- Table: {table_name} ({description})\nCREATE TABLE {table_name} (\n  {col} {type},  -- {description}\n  ...\n);\n"
- Also append relationships: "-- Relationship: {from_table}.{from_col} → {to_table}.{to_col} (FK)"
- Returns the string only — ContextBudgetManager truncates it

IMPLEMENTATION RULES FOR PROMPT TEMPLATES:
- sql-generation-system-prompt.st uses Spring AI's PromptTemplate format with {variables}
- Include all variables: temporalContext, ddlSubset, relationships, fewShotExamples, normalizedQuestion
- result-explanation-system-prompt.st variables: originalQuestion, rowCount, resultSample

VALIDATION REQUIREMENTS:
- LLMClient can be instantiated in a unit test with a mocked WebClient and WebClient.Builder (no ChatClient involved)
- SchemaEmbeddingService can be tested with mocked EmbeddingClientWrapper — verify embed_content is non-empty for each table
- DdlReconstructionService unit test: given 2 tables and 5 columns each, reconstructed DDL contains all table names and column names
- GroqConfig WebClient bean initializes without error even if GROQ_API_KEY is a dummy value in local test profile (no eager API call at startup)
- Ollama EmbeddingModel fails gracefully if Ollama is not running — application starts but embedding calls return error (acceptable for unit tests)

STOPPING POINT: AI clients and embedding only. Do not begin pipeline stages.
```

---

## PROMPT_07 — Pipeline Infrastructure (Context, Executor, SSE Registry)

```
PHASE: 07 — Pipeline Infrastructure
PREREQUISITE: Phase 06 complete and verified

GOAL: Implement PipelineContext, TextToSqlPipelineExecutor, SseEmitterRegistry, ContextBudgetManager, CorrectionPromptBuilder, RetryPolicy, and QuestionHasher.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/pipeline/context/PipelineContext.java
- src/main/java/com/querysense/pipeline/context/ContextBudgetManager.java
- src/main/java/com/querysense/pipeline/TextToSqlPipelineExecutor.java
- src/main/java/com/querysense/pipeline/retry/CorrectionPromptBuilder.java
- src/main/java/com/querysense/pipeline/retry/RetryPolicy.java
- src/main/java/com/querysense/infrastructure/sse/SseEmitterRegistry.java
- src/main/java/com/querysense/infrastructure/hashing/QuestionHasher.java
- src/main/java/com/querysense/service/QueryOrchestrationService.java

IMPLEMENTATION RULES FOR PipelineContext:
- Plain Java class (not a record — it has mutable state)
- All final fields set via constructor: jobId (UUID), userId (String), groupId (UUID), originalQuestion (String), emitter (SseEmitter)
- All mutable fields (normalizedQuestion, temporalContext, intentClass, cacheHit, schemaContext, generatedSql, retryCount, lastValidationResult, executionResult, explanation) initialized to null/false/0 — set by stages
- No thread-safety annotations — one instance per async task, never shared
- Provide standard getters and setters

IMPLEMENTATION RULES FOR SseEmitterRegistry:
- ConcurrentHashMap<UUID, SseEmitter> — thread-safe container
- register(UUID jobId): create SseEmitter(120_000L), attach onCompletion, onTimeout, onError listeners (all call emitters.remove(jobId)), put in map, return emitter
- sendEvent(UUID jobId, String eventName, Object data): get emitter, if null return (client disconnected), try send, catch IOException → remove and completeWithError
- complete(UUID jobId): remove from map, call emitter.complete() if not null

IMPLEMENTATION RULES FOR TextToSqlPipelineExecutor:
- @Service class, inject all 8 stage beans
- @Async("pipelineExecutor") CompletableFuture<Void> executePipeline(PipelineContext context)
- Execute stages in order 1–8
- After Stage 2 (SemanticCacheStage): if context.isCacheHit() == true, skip stages 3–7 and go directly to Stage 8
- Around stages 4 and 5 (SqlGenerationStage + ASTValidationStage): implement retry loop (max 2 retries) — if validation fails, call CorrectionPromptBuilder.buildValidationCorrectionPrompt() and re-run Stage 4, then Stage 5 again
- Around stage 6 (QueryExecutionStage): if execution fails, call CorrectionPromptBuilder.buildExecutionCorrectionPrompt() and re-run Stage 4+5+6 (counts toward same retry limit)
- If all retries exhausted: set job status FAILED via AuditService, send FAILED SSE event, return
- Catch all unhandled exceptions: set job status FAILED, log, send FAILED SSE event

IMPLEMENTATION RULES FOR QueryOrchestrationService:
- submitQuery(String question, UserPrincipal principal): create QueryJob (status=PENDING), save to DB, return jobId immediately
- startPipeline(UUID jobId, UserPrincipal principal): build PipelineContext, get SseEmitter from registry, call textToSqlPipelineExecutor.executePipeline(context) (async)
- These two steps are called from QueryController sequentially before returning the SSE emitter to the client

IMPLEMENTATION RULES FOR CorrectionPromptBuilder:
- buildValidationCorrectionPrompt(String originalQuestion, String rejectedSql, ValidationResult result, Set<String> whitelistedTables): returns a String prompt for Stage 4
- buildExecutionCorrectionPrompt(String originalQuestion, String rejectedSql, String dbError, Set<String> whitelistedTables): returns a String prompt for Stage 4

IMPLEMENTATION RULES FOR ContextBudgetManager:
- estimateTokens(String text): rough estimate = text.length() / 4 (standard approximation)
- truncateDdlToTokenBudget(String ddl, int maxTokens): if estimateTokens(ddl) <= maxTokens, return as-is. Otherwise, truncate by removing lowest-similarity tables from the end of the DDL string — tables are separated by blank lines, so split on "\n\n", drop from the end, rejoin.

VALIDATION REQUIREMENTS:
- SseEmitterRegistry unit test: register, sendEvent, complete — verify no exceptions; verify sendEvent silently drops if no emitter exists
- CorrectionPromptBuilder unit test: verify output contains rejected SQL and error message
- ContextBudgetManager unit test: verify DDL above 2500 tokens is truncated, below is returned unchanged
- TextToSqlPipelineExecutor: write a unit test with all 8 stages mocked — verify stage execution order, verify cache-hit path skips stages 3–7, verify retry loop calls stage 4 again on validation failure

STOPPING POINT: Pipeline infrastructure only. No stage implementations yet.
```

---

## PROMPT_08 — Pipeline Stages 1–3 (Pre-Processing, Cache, Schema Retrieval)

```
PHASE: 08 — Pipeline Stages 1–3
PREREQUISITE: Phase 07 complete and verified

GOAL: Implement QueryPreProcessingStage, SemanticCacheStage, and SchemaRetrievalStage.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/preprocessing/QueryNormalizer.java
- src/main/java/com/querysense/preprocessing/TemporalExtractor.java
- src/main/java/com/querysense/preprocessing/IntentClassifier.java
- src/main/java/com/querysense/preprocessing/InjectionGuard.java
- src/main/java/com/querysense/pipeline/stage/QueryPreProcessingStage.java
- src/main/java/com/querysense/ai/cache/ExactQueryCacheManager.java
- src/main/java/com/querysense/ai/cache/SemanticQueryCacheManager.java
- src/main/java/com/querysense/pipeline/stage/SemanticCacheStage.java
- src/main/java/com/querysense/schema/retrieval/SemanticSchemaRetriever.java
- src/main/java/com/querysense/schema/retrieval/RetrievedSchemaContext.java
- src/main/java/com/querysense/pipeline/stage/SchemaRetrievalStage.java

IMPLEMENTATION RULES FOR QueryNormalizer:
- normalize(String input): strip leading/trailing whitespace, collapse multiple spaces, normalize quotes (curly to straight), lowercase for hashing, preserve original case for display
- Returns a NormalizedQuery record: normalizedText (String), originalText (String)

IMPLEMENTATION RULES FOR TemporalExtractor:
- extract(String normalizedText): scan for known temporal phrases using a static Map<String, BiFunction<LocalDate, LocalDate>>
- Supported: "last quarter", "last month", "last week", "past 30 days", "past 7 days", "this year", "this month", "today", "yesterday"
- All resolved using LocalDate.now() at the time of the request
- Unrecognized phrases: return TemporalContext with null dates and the original phrase preserved
- TemporalContext is a Java record: startDate (LocalDate), endDate (LocalDate), originalPhrase (String)

IMPLEMENTATION RULES FOR IntentClassifier:
- classify(String normalizedText): keyword-based classification, no LLM call
- RANKING: contains "top", "highest", "lowest", "most", "least", "best", "worst", "rank"
- AGGREGATION: contains "total", "sum", "count", "average", "avg", "how many", "how much"
- TREND: contains "over time", "by month", "by week", "by day", "weekly", "monthly", "daily", "trend"
- COMPARISON: contains "vs", "versus", "compared to", "difference between", "compare"
- FILTER: default if none of the above match
- Returns QueryIntent enum value

IMPLEMENTATION RULES FOR InjectionGuard:
- check(String normalizedText): scan for SQL DML/DDL keywords in the text (case-insensitive): DROP, DELETE, INSERT, UPDATE, EXEC, EXECUTE, TRUNCATE, ALTER, CREATE, GRANT, REVOKE
- Returns true if injection detected (reject), false if clean

IMPLEMENTATION RULES FOR ExactQueryCacheManager:
- Uses Spring Data Redis (RedisTemplate<String, String>)
- get(String questionHash): returns Optional<QueryCacheResult> (deserialized from JSON)
- put(String questionHash, QueryCacheResult result): set with TTL 1 hour
- QueryCacheResult record: sql (String), resultData (String JSON), explanation (String)

IMPLEMENTATION RULES FOR SemanticQueryCacheManager:
- Uses JdbcTemplate (appDataSource @Primary — inject as plain JdbcTemplate, no qualifier needed since it binds to @Primary)
- findSimilar(float[] queryEmbedding, UUID groupId, double threshold): executes pgvector cosine similarity query against question_embeddings joined to query_jobs, returns Optional<QueryCacheResult>
- The query: SELECT qe.cached_sql, qe.cached_result::text, qj.id FROM question_embeddings qe JOIN query_jobs qj ON qj.id = qe.job_id WHERE qe.cache_valid = true AND qj.group_id = ? AND qj.status = 'COMPLETED' ORDER BY qe.embedding <=> ?::vector LIMIT 1
- After fetching, filter in Java: if similarity < threshold, return Optional.empty()
- Threshold: configurable via @Value("${app.cache.semantic.threshold:0.93}")

IMPLEMENTATION RULES FOR SemanticSchemaRetriever:
- Uses JdbcTemplate (appDataSource — plain JdbcTemplate, no qualifier)
- retrieveTables(float[] queryEmbedding, UUID groupId, int limit): executes Phase A query (top-8 tables by cosine similarity, filtered by group access and whitelist)
- retrieveColumns(float[] queryEmbedding, UUID tableId, int limit): executes Phase B query (top-10 columns per table, is_pii=false)
- retrieveRelationships(List<UUID> tableIds): queries table_relationships for all relationships between the retrieved tables (transitive closure)
- Returns RetrievedSchemaContext record: tables (List), columnsByTableId (Map), relationships (List)

VALIDATION REQUIREMENTS:
- TemporalExtractorTest: test all supported phrases return correct date ranges. Test "last quarter" returns Q1/Q2/Q3/Q4 dates depending on current month
- IntentClassifierTest: test each intent class with at least 3 example questions
- InjectionGuardTest: test "DROP TABLE orders" returns true; "top 10 products" returns false
- SemanticCacheStageTest: mock ExactQueryCacheManager (hit) → verify pipeline context cacheHit=true, stage 3 never called. Mock SemanticQueryCacheManager (miss) → verify pipeline continues
- Write a manual test: POST /api/v1/queries twice with identical question — second call must return CACHED status

STOPPING POINT: Stages 1–3 only. Do not implement Stage 4 (SQL generation) yet.
```

---

## PROMPT_09 — Pipeline Stages 4–6 (Generation, Validation, Execution)

```
PHASE: 09 — Pipeline Stages 4–6
PREREQUISITE: Phase 08 complete and verified

GOAL: Implement SqlGenerationStage, ASTValidationStage, and QueryExecutionStage — the core safety-critical stages.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/ai/prompt/SqlGenerationPromptTemplate.java
- src/main/java/com/querysense/ai/prompt/ResultExplanationPromptTemplate.java
- src/main/java/com/querysense/pipeline/stage/SqlGenerationStage.java
- src/main/java/com/querysense/validation/ASTValidator.java
- src/main/java/com/querysense/validation/ValidationResult.java
- src/main/java/com/querysense/validation/WhitelistEnforcer.java
- src/main/java/com/querysense/validation/SqlLimitInjector.java
- src/main/java/com/querysense/pipeline/stage/ASTValidationStage.java
- src/main/java/com/querysense/execution/SafeQueryExecutor.java
- src/main/java/com/querysense/execution/QueryExecutionResult.java
- src/main/java/com/querysense/execution/ResultSetMapper.java
- src/main/java/com/querysense/pipeline/stage/QueryExecutionStage.java

IMPLEMENTATION RULES FOR SqlGenerationStage:
- Inject LLMClient and SqlGenerationPromptTemplate
- Receives a correctionPrompt parameter (null on first attempt, non-null on retry)
- If correctionPrompt is null: build systemPrompt from sql-generation-system-prompt.st with context from PipelineContext (DDL, temporal context, few-shot examples by intent class)
- If correctionPrompt is non-null: use correctionPrompt directly as the user message, keep same systemPrompt
- Call llmClient.generateSql(systemPrompt, userPrompt) → SQLGenerationResult
- Set context.setGeneratedSql(result.sql())
- SqlGenerationPromptTemplate: loads sql-generation-system-prompt.st via ClassPathResource or Spring AI PromptTemplate; provides buildPrompt(PipelineContext) method

IMPLEMENTATION RULES FOR ASTValidator (exact implementation as architecture):
- Inject Set<String> whitelistedTables — loaded at startup from RegisteredTableRepository, refreshed after schema sync
- validate(String rawSql) implements all 7 rules: parse failure, non-SELECT, semicolons, table whitelist, comment injection, system catalog access, SELECT *
- ValidationResult: Java record with passed (boolean), failureReason (String), validationError (String), referencedTables (List<String>)
- WhitelistEnforcer: provides getWhitelistedTableNames() → Set<String>, refreshed by SchemaService.syncSchema()

IMPLEMENTATION RULES FOR SqlLimitInjector:
- ensureLimit(String validatedSql, int maxRows): parse with JSQLParser, check if LIMIT clause exists on the outermost SELECT
- If LIMIT missing: use JSQLParser API to add LIMIT {maxRows} programmatically (do not use string concatenation)
- If LIMIT present and > maxRows: replace with maxRows
- Return modified SQL as string via JSQLParser's .toString()

IMPLEMENTATION RULES FOR SafeQueryExecutor:
- Inject @Qualifier("analyticsJdbcTemplate") JdbcTemplate analyticsJdbcTemplate
- execute(String validatedSql, int maxRows): calls SqlLimitInjector.ensureLimit first, then analyticsJdbcTemplate.queryForList(boundedSql)
- Catch QueryTimeoutException → QueryExecutionResult.fail("TIMEOUT", ...)
- Catch DataAccessException → QueryExecutionResult.fail("SQL_ERROR", e.getMessage())
- QueryExecutionResult: Java record with success (boolean), rows (List<Map<String,Object>>), executionMs (long), failureReason (String), errorMessage (String)

VALIDATION REQUIREMENTS:
- ASTValidatorTest (at least 20 test cases):
  * Valid SELECT → passes
  * INSERT INTO → fails NON_SELECT
  * DROP TABLE → fails NON_SELECT (JSQLParser parses DROP as non-Select statement)
  * SELECT with comment (-- comment) → fails COMMENT_INJECTION
  * SELECT * → fails SELECT_STAR
  * SELECT from non-whitelisted table → fails TABLE_NOT_WHITELISTED
  * SELECT from information_schema.tables → fails SYSTEM_TABLE_ACCESS
  * Two statements separated by ; → fails MULTIPLE_STATEMENTS
  * Valid multi-table JOIN with whitelisted tables → passes
  * SELECT with subquery → passes (subquery from whitelisted tables)
- SqlLimitInjectorTest: verify LIMIT added when missing, verify existing LIMIT > maxRows is replaced
- SafeQueryExecutor integration test with Testcontainers: set up analytics DB with read-only role, execute valid SELECT, verify results returned; execute long-running query, verify TIMEOUT returned

STOPPING POINT: Stages 4–6 only. Do not implement Stage 7 or 8 yet.
```

---

## PROMPT_10 — Pipeline Stages 7–8 (Explanation, Caching, Audit)

```
PHASE: 10 — Pipeline Stages 7–8
PREREQUISITE: Phase 09 complete and verified

GOAL: Implement ResultExplanationStage, CachingAndAuditStage, AuditService, and RateLimitService. Complete the full pipeline.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/pipeline/stage/ResultExplanationStage.java
- src/main/java/com/querysense/pipeline/stage/CachingAndAuditStage.java
- src/main/java/com/querysense/service/AuditService.java
- src/main/java/com/querysense/service/RateLimitService.java

IMPLEMENTATION RULES FOR ResultExplanationStage:
- Inject LLMClient, ResultExplanationPromptTemplate, SseEmitterRegistry
- Build user prompt with: original question, row count, first 20 rows of result as JSON string (use ObjectMapper to serialize)
- Call llmClient.streamExplanation(systemPrompt, userPrompt) → Flux<String>
- Subscribe to Flux: each token → call sseEmitterRegistry.sendEvent(jobId, "EXPLANATION_TOKEN", Map.of("token", token))
- On complete: set context.setExplanation(fullExplanation.toString()), proceed to Stage 8
- On error: log error, set explanation to "Explanation unavailable." (do not fail the job for explanation errors)
- Send SSE event "EXPLANATION_START" before subscribing, "EXPLANATION_COMPLETE" after

IMPLEMENTATION RULES FOR CachingAndAuditStage:
- Inject AuditService, ExactQueryCacheManager, SemanticQueryCacheManager (for writing), EmbeddingClientWrapper, SseEmitterRegistry, QueryResultRepository, LlmCallLogRepository
- Sequence (non-blocking where possible):
  1. Update QueryJob: status=COMPLETED, completedAt=now() via AuditService
  2. Save QueryResult entity
  3. Save SqlGenerationAttempt entity for each attempt (retryCount+1 total)
  4. Embed the normalized question, save to question_embeddings with cached_sql and cached_result
  5. Write to Redis exact cache: query:exact:{hash} → QueryCacheResult, TTL 1h
  6. Write to Redis job status: job:status:{jobId} → COMPLETED, TTL 2h
  7. Send SSE event "COMPLETED" with full payload: { jobId, sql, rowCount, explanation, executionMs, retryCount }
  8. Call sseEmitterRegistry.complete(jobId)
- AuditService is @Transactional — handles all DB writes atomically

IMPLEMENTATION RULES FOR AuditService:
- updateJobStatus(UUID jobId, JobStatus status, String rejectionReason): updates query_jobs — status, completedAt (if terminal), rejectionReason
- saveQueryResult(PipelineContext context): constructs and saves QueryResult entity
- saveGenerationAttempts(PipelineContext context): constructs and saves SqlGenerationAttempt entities
- markJobFailed(UUID jobId, String reason): sets status=FAILED, rejection_reason

IMPLEMENTATION RULES FOR RateLimitService:
- Uses RedisTemplate<String, String>
- checkAndIncrement(String userId): Lua script for atomic check-and-increment on key rate_limit:user:{userId} with EXPIRE 60s (sliding window 20 requests/hour → check against 20)
- If limit exceeded, throw RateLimitExceededException (caught by GlobalExceptionHandler → 429)

VALIDATION REQUIREMENTS:
- Full end-to-end pipeline test (integration test with mocked LLMClient):
  1. POST /api/v1/auth/login → get token
  2. POST /api/v1/queries with question "Show me total orders by status" → get jobId
  3. Open SSE stream → receive CACHE_LOOKUP, SCHEMA_RETRIEVAL, SQL_GENERATION, AST_VALIDATION, QUERY_EXECUTION, EXPLANATION_START, EXPLANATION_TOKEN..., EXPLANATION_COMPLETE, COMPLETED events in order
  4. GET /api/v1/queries/{jobId} → returns full result including SQL and row data
  5. Check DB: query_jobs status=COMPLETED, query_results has one row, question_embeddings has one row
- Rate limit test: send 21 identical requests with same user token → 21st returns 429
- Cache test: send same question twice → second response has cache_hit=true in SSE COMPLETED event

STOPPING POINT: Complete the pipeline. Do not start Query API controller or Evaluation in this session.
```

---

## PROMPT_11 — Query API Controller & History

```
PHASE: 11 — Query API Controller & History
PREREQUISITE: Phase 10 complete and verified (full pipeline runs end-to-end)

GOAL: Implement QueryController with all endpoints: submit query, poll status, SSE stream, query history.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/api/controller/QueryController.java
- src/main/java/com/querysense/api/dto/request/QueryRequest.java
- src/main/java/com/querysense/api/dto/response/QueryJobResponse.java
- src/main/java/com/querysense/api/dto/response/QueryResultResponse.java

IMPLEMENTATION RULES:
- POST /api/v1/queries: validate @Valid QueryRequest (question: @NotBlank, max 500 chars), check rate limit, call QueryOrchestrationService.submitQuery(), return 202 Accepted with { jobId, status: "PENDING" }
- GET /api/v1/queries/{jobId}: fetch QueryJob + QueryResult (if COMPLETED), return QueryJobResponse. Enforce that user can only fetch their own jobs (unless ADMIN role)
- GET /api/v1/queries/{jobId}/stream: call SseEmitterRegistry.register(jobId) first, then call QueryOrchestrationService.startPipeline(jobId, principal), return SseEmitter with ResponseEntity<SseEmitter>. Register BEFORE startPipeline.
- GET /api/v1/queries: return paginated list of caller's QueryJobs. @RequestParam int page=0, int size=20. Use Pageable.
- QueryRequest: { question: String } with @NotBlank @Size(max=500)
- QueryJobResponse: { jobId, status, naturalLanguage, createdAt, completedAt, cacheHit, retryCount, result: QueryResultResponse (nullable) }
- QueryResultResponse: { generatedSql, rowCount, executionMs, explanation, resultData (List<Map<String,Object>>) }
- All endpoints require authentication (@AuthenticationPrincipal UserPrincipal)

VALIDATION REQUIREMENTS:
- POST /api/v1/queries with empty question returns 400
- POST /api/v1/queries with question > 500 chars returns 400
- GET /api/v1/queries/{someoneElsesJobId} returns 403
- GET /api/v1/queries returns paginated list with correct total count
- GET /api/v1/queries/{jobId}/stream: SSE connection established before pipeline starts (verify by checking job status in DB at moment of SSE connection open — must be PENDING, not yet PROCESSING)

STOPPING POINT: Query controller only. Do not implement Evaluation in this session.
```

---

## PROMPT_12 — Evaluation Framework

```
PHASE: 12 — Evaluation Framework
PREREQUISITE: Phase 11 complete and verified

GOAL: Implement golden dataset management and evaluation runner.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/service/EvaluationService.java
- src/main/java/com/querysense/api/controller/EvaluationController.java
- src/main/java/com/querysense/api/dto/request/GoldenQueryRequest.java
- src/main/java/com/querysense/api/dto/response/EvaluationRunResponse.java
- evaluation/evaluate.py
- evaluation/sql_similarity.py
- evaluation/golden_dataset.json
- evaluation/requirements.txt

IMPLEMENTATION RULES FOR EvaluationService:
- runEvaluation(UserPrincipal principal): for each active golden_query, run the full Text-to-SQL pipeline synchronously (not async — evaluation runs sequentially), compare generated_sql to expected_sql using SQLSimilarity
- SQLSimilarity comparison: normalize both SQLs (lowercase, strip extra whitespace), check if they are textually identical OR if they produce the same query structure (table names match, column names match, aggregation functions match) — use JSQLParser AST comparison for structural match
- Create EvaluationRun record with total, passed, failed, accuracy_pct
- Create EvaluationResult for each golden query: passed/failed, failure_reason, latency_ms
- EvaluationController: all endpoints require ADMIN role

IMPLEMENTATION RULES FOR PYTHON EVALUATION:
- evaluate.py: reads golden_dataset.json, calls POST /api/v1/queries for each item, polls GET /api/v1/queries/{jobId} until COMPLETED, compares generated SQL to expected SQL using sql_similarity.py
- sql_similarity.py: tokenizes both SQLs (split on whitespace and SQL keywords), computes token overlap — if overlap > 0.8, consider passing
- golden_dataset.json: include at least 10 example golden queries covering AGGREGATION, RANKING, FILTER, TREND intents using the seed analytics DB schema (orders, products, customers, order_items)
- requirements.txt: requests, python-dotenv

VALIDATION REQUIREMENTS:
- POST /api/v1/evaluation/golden (ADMIN) creates a golden query
- POST /api/v1/evaluation/run (ADMIN) runs all golden queries and returns accuracy_pct
- GET /api/v1/evaluation/runs/{id} returns per-case pass/fail results
- python evaluation/evaluate.py with a running local server returns accuracy report

STOPPING POINT: Evaluation framework complete. Do not start observability in this session.
```

---

## PROMPT_13 — Observability & Analytics Endpoints

```
PHASE: 13 — Observability & Analytics
PREREQUISITE: Phase 12 complete and verified

GOAL: Implement AnalyticsController (cost + accuracy endpoints), configure Spring Boot Actuator properly, and add structured JSON logging.

GENERATE EXACTLY THESE FILES:
- src/main/java/com/querysense/api/controller/AnalyticsController.java
- src/main/resources/logback-spring.xml

IMPLEMENTATION RULES FOR AnalyticsController:
- GET /api/v1/analytics/cost: queries llm_call_logs table with the cost SQL from architecture section 18. Returns daily breakdown for last 7 days. ADMIN only.
- GET /api/v1/analytics/accuracy: queries query_jobs for cache hit rate, retry rate, failure rate grouped by day for last 30 days. ADMIN only.
- Use JdbcTemplate (appDataSource) for these queries — the GROUP BY + computed fields are easier with native SQL than JPQL
- Return results as List<Map<String, Object>> serialized to JSON

IMPLEMENTATION RULES FOR LOGGING:
- logback-spring.xml: JSON format for production profile, human-readable for local profile
- Every pipeline stage logs at INFO level: jobId, stage name, latency
- LLMClient logs at INFO level: model, prompt_tokens, completion_tokens, latency_ms after each call
- ASTValidator logs at DEBUG level: validation result and rule that triggered
- SafeQueryExecutor logs at INFO level: executionMs, rowCount

VALIDATION REQUIREMENTS:
- GET /api/v1/analytics/cost returns valid JSON with daily cost breakdown after running a few queries
- GET /api/v1/analytics/accuracy returns valid JSON with daily stats
- Verify in logs that a complete pipeline run produces structured log entries for each stage with jobId traceable across all entries

STOPPING POINT: Observability complete.
```

---

## PROMPT_14 — CI/CD & Final Deployment

```
PHASE: 14 — CI/CD & Final Deployment
PREREQUISITE: Phase 13 complete and verified

GOAL: Set up GitHub Actions CI pipeline, Railway production deployment configuration.

GENERATE EXACTLY THESE FILES:
- .github/workflows/ci.yml
- .github/workflows/deploy.yml
- docker-compose.prod.yml
- src/main/resources/application-prod.yml

IMPLEMENTATION RULES FOR CI:
- ci.yml triggers on push to main and develop, and on PRs to main
- Jobs: postgres-app (pgvector/pgvector:pg16), postgres-analytics (postgres:16-alpine), redis (redis:7-alpine) as service containers
- Steps: checkout, setup-java (21, temurin, maven cache), setup analytics DB roles and schema (psql commands), run ./mvnw verify, upload surefire-reports as artifact
- Use github.com secrets for GROQ_API_KEY (Groq free tier — no cost in CI)
- Add ollama as a service container: image ollama/ollama:latest, pull nomic-embed-text as a setup step
- After ./mvnw verify: run python evaluate.py --fail-below 0.80 (fails build if accuracy < 80%)
- deploy.yml: runs only after ci.yml passes on main branch, deploys to Railway

IMPLEMENTATION RULES FOR application-prod.yml:
- Sets logging level INFO (not DEBUG)
- Redis connection from ${REDIS_URL}
- Actuator: expose health and metrics endpoints only
- No debug SQL logging

VALIDATION REQUIREMENTS:
- Push to a feature branch → CI runs, tests pass
- Verify evaluate.py runs in CI and would fail the build if accuracy < 80%

STOPPING POINT: This is the final phase. All work complete.
```

---

## QUICK REFERENCE — Common AI Mistakes to Watch For

When reviewing AI-generated code, immediately reject and redirect if you see:

| Pattern | Problem | Correct Approach |
|---|---|---|
| `@Autowired private ChatClient chatClient` (or `ChatClient.Builder`) | Wrong API — OpenAI pattern, not Groq | Inject `WebClient` bean from `GroqConfig`; for embeddings inject `EmbeddingModel` |
| `@Autowired private JdbcTemplate jdbcTemplate` in SafeQueryExecutor | Uses wrong DataSource | `@Qualifier("analyticsJdbcTemplate")` |
| `spring.flyway.url=...` in application.yml | Flyway runs against wrong DB | Remove — Flyway auto-binds to @Primary |
| `@Data` on any entity | Lombok not in stack | Explicit getters/setters/constructors |
| `new SseEmitter()` in a stage class | Stage should not create emitter | Use SseEmitterRegistry.sendEvent() |
| `FetchType.EAGER` on any @ManyToOne | N+1 problem | Always LAZY |
| `context.getEmitter().send(...)` in a stage | Breaks SSE lifecycle contract | Always go through SseEmitterRegistry |
| `PipelineContext` stored in a static field | Thread-safety violation | One instance per async task, never stored statically |
| Raw string concatenation for LIMIT injection | SQL injection risk | Use JSQLParser API to modify AST |
| `spring-ai-openai-spring-boot-starter` in pom.xml | Paid OpenAI dependency | Use `spring-ai-ollama-spring-boot-starter` + WebClient for Groq |
| `vector(1536)` in migrations | Wrong dimension for BGE | nomic-embed-text = 768 dims — use `vector(768)` |
| OPENAI_API_KEY in env | OpenAI cost | Use `GROQ_API_KEY` + `OLLAMA_BASE_URL` |
| Missing `@Transactional` on AuditService write methods | Non-atomic audit writes | Add @Transactional |
