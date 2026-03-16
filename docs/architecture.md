# AI Misinformation Detector for Social Media

## Architecture and Development Roadmap

---

## 1. Project Overview

### Project Name

AI Misinformation Detector for Social Media

### Goal

Build a backend system that detects potentially misleading or false claims in YouTube videos by analyzing spoken content, extracting factual claims, and verifying them against trusted information sources.

The system acts as an **AI Credibility Assistant**. It does not declare absolute truth. Instead, it returns:

- A credibility score on a continuous scale
- Supporting or contradicting evidence
- A plain-language explanation
- Links to trusted sources

### Why This Framing

AI models can hallucinate and evidence can be incomplete. Presenting results as credibility assessments rather than binary verdicts avoids overconfidence and reflects real-world uncertainty.

---

## 2. Problem Statement

Short-form video platforms allow misinformation to spread rapidly. Users consume information without verifying accuracy.

This system addresses the problem by:

1. Detecting factual claims spoken in videos
2. Automatically verifying those claims against trusted sources
3. Presenting evidence and credibility scores to the user

### Example Output

```
Claim:     "Hot water cures cancer"
Verdict:   Likely False
Confidence: 92%
Sources:   World Health Organization, Cancer Research UK
Explanation: Medical organizations confirm there is no evidence
             that hot water cures cancer.
```

---

## 3. Scope for MVP

### Included in V1

- YouTube videos only (Shorts and standard videos)
- Spring Boot monolith as the sole backend service
- AI services accessed through external hosted APIs
- Async job processing pipeline
- Claim extraction with two-stage classification
- Search-based evidence retrieval (RAG)
- LLM reasoning with structured output validation
- Redis caching and claim deduplication
- PostgreSQL storage with normalized schema
- Idempotent video submission
- Web UI or Swagger API interface
- Evaluation dataset for accuracy measurement
- Docker Compose deployment

### Excluded from V1

These are intentionally deferred to control scope:

- Browser extension (Chrome, Firefox)
- Instagram, TikTok, or other platform support
- Python microservice / FastAPI sidecar
- Local Whisper model inference
- Vector database / embedding-based retrieval
- User accounts or authentication

---

## 4. System Architecture

### High-Level Flow

```
User (Web UI / Swagger)
   |
   v
Spring Boot Backend
   |
   v
Async Job Pipeline
   |
   +---> Transcript Extraction (yt-dlp + Whisper API)
   |
   +---> Claim Extraction (LLM: classify + normalize)
   |
   +---> Evidence Retrieval (parallel)
   |        |
   |        +---> Google Fact Check API
   |        +---> Search API (Tavily / SerpAPI)
   |
   +---> LLM Reasoning (all evidence combined)
   |
   +---> Response Validation
   |
   v
PostgreSQL (persistent storage)
Redis (cache + deduplication)
```

### Key Architectural Decisions

**Monolith over microservices.** All AI service calls are HTTP requests to external hosted APIs. There is no Python-specific processing that requires a separate service. A single Spring Boot application reduces deployment complexity, eliminates inter-service communication overhead, and simplifies debugging for a solo developer.

**Polling over WebSockets/SSE.** The extension polls `GET /api/jobs/{id}` for status. Polling is simpler to implement, debug, and cache. SSE may be considered in a future version for reduced latency.

**Credibility scores over binary verdicts.** A continuous 0-100 scale with labeled ranges avoids the false precision of true/false labels and reflects the inherent uncertainty of AI-based analysis.

---

## 5. Technology Stack

### Backend

| Technology | Role |
|------------|------|
| Spring Boot | Application framework, orchestration |
| Spring Async (`@Async` + `CompletableFuture`) | Async job processing |
| Resilience4j | Circuit breakers, retry, rate limiting |
| Springdoc OpenAPI | API documentation |
| Spring Data JPA | Database access |
| Spring Cache + Redis | Caching layer |

### Data Layer

| Technology | Role |
|------------|------|
| PostgreSQL | Persistent storage for jobs, claims, sources |
| Redis | Claim result caching, deduplication |

### External AI Services

| Service | Role |
|---------|------|
| OpenAI Whisper API (`whisper-1`) | Speech-to-text transcription |
| LLM API (GPT-4o / GPT-4o-mini) | Claim extraction and reasoning |
| Google Fact Check Tools API | Verified fact-check database |
| Tavily API | Search-based evidence retrieval |

### Infrastructure

| Technology | Role |
|------------|------|
| Docker + Docker Compose | Local deployment |
| GitHub Actions | CI pipeline (build + test) |
| yt-dlp | YouTube audio/caption extraction |

### Frontend

A simple web interface where users paste a YouTube URL and view results. Implementation options:

- Single HTML + JavaScript page (recommended for V1)
- React single-page application
- Swagger UI (acceptable for demo purposes)

---

## 6. Asynchronous Processing Architecture

Video analysis takes 10-20 seconds. The system uses an async job pipeline to avoid blocking HTTP requests.

### Job Lifecycle

```
Client: POST /api/analyze { "videoUrl": "..." }
Server: 202 Accepted { "jobId": "uuid" }

Client: GET /api/jobs/{jobId}   (poll every 3 seconds)
Server: 200 { "status": "PROCESSING" }

Client: GET /api/jobs/{jobId}
Server: 200 { "status": "COMPLETED", "claims": [...] }
```

### Job States

```
PENDING     Job created, not yet started
PROCESSING  Pipeline is running
COMPLETED   Analysis finished successfully
FAILED      Pipeline failed (error message attached)
```

### Implementation

- `@Async` annotation on the pipeline method
- `CompletableFuture` for composing pipeline stages
- `@Scheduled(fixedRate = 60000)` reaper task marks jobs stuck in PROCESSING for more than 5 minutes as FAILED

### Idempotent Submission

When a video URL is submitted:

1. Query for an existing completed job with the same `video_url` created within the last 24 hours
2. If found, return the existing job immediately
3. If not found, create a new job and start the pipeline

This avoids redundant AI processing and reduces cost.

```java
Optional<Job> recent = jobRepository
    .findByVideoUrlAndStatusAndCreatedAtAfter(
        url, JobStatus.COMPLETED, Instant.now().minus(24, HOURS));
if (recent.isPresent()) {
    return recent.get();
}
```

---

## 7. Processing Pipeline

### Step 1 -- Transcript Extraction

**Input:** YouTube video URL

**Process:**

1. Attempt to download YouTube auto-generated captions using `yt-dlp --write-auto-sub`
2. If captions are unavailable, download audio and send to OpenAI Whisper API

**Output:** Plain text transcript stored in the `jobs.transcript` column

**Rationale:** YouTube auto-captions are free and fast. Whisper API is the fallback for videos without captions. This avoids running a local Whisper model while keeping transcription quality high.

### Step 2 -- Claim Extraction (Two-Stage)

This is the most challenging step in the pipeline. A single "extract claims" prompt is unreliable because videos mix facts, opinions, sarcasm, hypotheticals, and predictions.

#### Stage 1: Sentence Classification

Each sentence in the transcript is classified into one of:

```
factual_claim   A verifiable statement of fact
opinion         A subjective belief or preference
question        An interrogative statement
narrative       Storytelling or descriptive context
prediction      A claim about future events (not verifiable)
```

#### Stage 2: Claim Normalization

Sentences classified as `factual_claim` are normalized into standalone, searchable statements:

- Strip hedging language ("I think", "some say")
- Resolve pronouns to their referents
- Split compound claims into individual statements

**Example:**

```
Input:    "I think hot water cures cancer and the government hides it."
Output:   ["Hot water cures cancer", "The government hides cancer cures"]
```

**LLM choice:** Use GPT-4o-mini for claim extraction. It is 10-15x cheaper than GPT-4o and performs well on classification tasks.

**Output format:** Request structured JSON output from the LLM.

```json
{
  "sentences": [
    {
      "text": "Doctors don't want you to know that hot water cures cancer.",
      "classification": "factual_claim",
      "normalized_claim": "Hot water cures cancer"
    },
    {
      "text": "I really believe in natural medicine.",
      "classification": "opinion",
      "normalized_claim": null
    }
  ]
}
```

### Step 3 -- Evidence Retrieval (Parallel)

For each extracted claim, two evidence sources are queried **in parallel**:

**Google Fact Check Tools API**
- Returns verdicts from trusted fact-checking organizations (WHO, Snopes, PolitiFact)
- Free to use
- Limited coverage: many claims will return zero results

**Tavily Search API**
- Returns relevant web documents with content snippets
- Designed for AI retrieval use cases
- Free tier: 1,000 searches per month

Both results are collected and passed together to the LLM reasoning stage. The Fact Check API result is treated as one source of evidence, not as a final answer.

### Step 4 -- LLM Reasoning

The LLM evaluates each claim using all retrieved evidence.

**Input:**

```json
{
  "claim": "Hot water cures cancer",
  "fact_check_results": [...],
  "search_results": [...]
}
```

**Expected output:**

```json
{
  "verdict": "LIKELY_FALSE",
  "confidence": 92,
  "explanation": "Medical organizations including WHO and Cancer Research UK confirm there is no scientific evidence that hot water cures cancer.",
  "sources": [
    {
      "name": "World Health Organization",
      "url": "https://...",
      "snippet": "..."
    }
  ]
}
```

**LLM choice:** Use GPT-4o for reasoning. This step requires stronger analytical capability than classification.

### Step 5 -- Response Validation

LLM output is validated before storage:

```java
AnalysisResult result = objectMapper.readValue(llmResponse, AnalysisResult.class);

// Validate verdict is a known enum value
if (!VALID_VERDICTS.contains(result.verdict())) {
    throw new InvalidLlmResponseException("Unknown verdict: " + result.verdict());
}

// Validate confidence is within range
if (result.confidence() < 0 || result.confidence() > 100) {
    throw new InvalidLlmResponseException("Confidence out of range: " + result.confidence());
}

// Validate explanation is not empty
if (result.explanation() == null || result.explanation().isBlank()) {
    throw new InvalidLlmResponseException("Explanation is empty");
}
```

On validation failure, retry the LLM call once with a stricter prompt. If the retry also fails, mark the individual claim as `ANALYSIS_FAILED` rather than failing the entire job.

**LLM JSON mode:** Use OpenAI's `response_format: { type: "json_object" }` to enforce valid JSON responses and reduce parsing failures.

### Step 6 -- Persist and Cache

1. Write claims and sources to PostgreSQL (normalized tables)
2. Update job status to `COMPLETED`
3. Write `claim_text_hash -> result` to Redis with a 24-hour TTL

---

## 8. Credibility Scoring

Instead of binary true/false labels, the system uses a continuous credibility scale:

```
 0 - 30   LIKELY_FALSE    Strong evidence contradicts the claim
30 - 60   MISLEADING      Claim is partially true but missing context
60 - 80   UNCERTAIN       Insufficient evidence to determine accuracy
80 - 100  LIKELY_TRUE     Strong evidence supports the claim
```

Valid verdict enum values:

```
LIKELY_FALSE
MISLEADING
UNCERTAIN
LIKELY_TRUE
ANALYSIS_FAILED
```

---

## 9. API Design

### POST /api/analyze

Submit a video for analysis.

**Request:**

```json
{
  "videoUrl": "https://www.youtube.com/shorts/abc123"
}
```

**Response (202 Accepted):**

```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "PENDING"
}
```

**Response (200 OK -- idempotent hit):**

```json
{
  "jobId": "existing-job-uuid",
  "status": "COMPLETED"
}
```

### GET /api/jobs/{jobId}

Poll for job status and results.

**Response (processing):**

```json
{
  "jobId": "...",
  "status": "PROCESSING",
  "videoUrl": "...",
  "createdAt": "2026-03-16T10:00:00Z"
}
```

**Response (completed):**

```json
{
  "jobId": "...",
  "status": "COMPLETED",
  "videoUrl": "...",
  "createdAt": "...",
  "completedAt": "...",
  "claims": [
    {
      "claimId": "...",
      "text": "Hot water cures cancer",
      "verdict": "LIKELY_FALSE",
      "confidence": 92,
      "explanation": "Medical organizations confirm there is no evidence...",
      "sources": [
        {
          "name": "World Health Organization",
          "url": "https://...",
          "snippet": "..."
        }
      ]
    }
  ]
}
```

**Response (failed):**

```json
{
  "jobId": "...",
  "status": "FAILED",
  "errorMessage": "Transcription service unavailable"
}
```

### Input Validation Rules

| Rule | Detail |
|------|--------|
| URL format | Must be a valid YouTube URL (youtube.com or youtu.be domain) |
| Reject playlists | URLs containing `list=` parameter are rejected |
| Reject channels | URLs pointing to `/channel/` or `/c/` paths are rejected |
| Reject live streams | Live stream URLs are rejected |
| Video length | Maximum 3 minutes (validated after metadata download) |
| Rate limit | 5 requests per minute per IP |

Invalid requests return `400 Bad Request` with a descriptive error message.

---

## 10. Database Design

### Jobs Table

Tracks pipeline execution state and stores the transcript.

```sql
CREATE TABLE jobs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_url       TEXT NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    transcript      TEXT,
    error_message   TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMP
);

CREATE INDEX idx_jobs_video_url_created ON jobs (video_url, created_at);
CREATE INDEX idx_jobs_status ON jobs (status);
```

### Claims Table

Stores individual extracted claims. Each claim belongs to one job.

```sql
CREATE TABLE claims (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id           UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    text             TEXT NOT NULL,
    text_hash        VARCHAR(64) NOT NULL,
    verdict          VARCHAR(20),
    confidence_score INTEGER,
    explanation      TEXT,
    created_at       TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_claims_job_id ON claims (job_id);
CREATE INDEX idx_claims_text_hash ON claims (text_hash);
```

### Sources Table

Stores evidence sources referenced by claims.

```sql
CREATE TABLE sources (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_name  VARCHAR(255) NOT NULL,
    url          TEXT,
    snippet_text TEXT
);
```

### Claim_Sources Table

Join table for the many-to-many relationship between claims and sources.

```sql
CREATE TABLE claim_sources (
    claim_id  UUID NOT NULL REFERENCES claims(id) ON DELETE CASCADE,
    source_id UUID NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    PRIMARY KEY (claim_id, source_id)
);
```

### Entity Relationships

```
jobs 1 --- * claims
claims * --- * sources  (through claim_sources)
```

---

## 11. Caching Strategy

Redis caches claim analysis results to avoid redundant AI processing.

### Cache Key

```
claim:<sha256_hash_of_normalized_claim_text>
```

### Cache Value

Serialized JSON of the claim analysis result (verdict, confidence, explanation, sources).

### TTL

24 hours.

### Lookup Order

```
1. Compute text hash of the normalized claim
2. Check Redis for cached result
3. If cache hit: use cached result, skip evidence retrieval and LLM reasoning
4. If cache miss: run full pipeline, then write result to Redis
```

### Cache Scope

Caching happens at the **individual claim level**, not the job level. This means if two different videos make the same claim, the second video benefits from the cached result even though the jobs are different.

---

## 12. Error Handling Strategy

### Per-Stage Error Handling

| Stage | On Failure | Behavior |
|-------|-----------|----------|
| YouTube caption download | Fallback to Whisper API | Degraded mode: slower but functional |
| Whisper API | Retry once, then fail job | Mark job FAILED: "Transcription unavailable" |
| Claim extraction (LLM) | Retry once with stricter prompt | Mark job FAILED if retry also fails |
| Google Fact Check API | Skip, proceed without fact-check data | Degraded mode: less evidence but functional |
| Tavily Search API | Retry once, then fail job | Mark job FAILED: "Evidence retrieval unavailable" |
| LLM reasoning | Retry once, then mark claim failed | Individual claim marked ANALYSIS_FAILED; other claims in job still processed |
| Response validation | Retry LLM once with stricter prompt | Mark individual claim ANALYSIS_FAILED on second failure |

### Circuit Breaker Configuration (Resilience4j)

| Service | Failure Threshold | Wait Duration | Fallback |
|---------|-------------------|---------------|----------|
| Whisper API | 3 failures in 60s | 30s half-open | Mark job FAILED |
| Google Fact Check API | 5 failures in 60s | 30s half-open | Skip fact check, proceed with search only |
| Tavily Search API | 3 failures in 60s | 30s half-open | Mark job FAILED |
| LLM API (extraction) | 3 failures in 60s | 60s half-open | Mark job FAILED |
| LLM API (reasoning) | 3 failures in 60s | 60s half-open | Mark job FAILED |

### Job Timeout Reaper

A scheduled task runs every 60 seconds to detect and fail stuck jobs:

```java
@Scheduled(fixedRate = 60_000)
public void reapStaleJobs() {
    Instant cutoff = Instant.now().minus(5, ChronoUnit.MINUTES);
    List<Job> stale = jobRepository
        .findByStatusAndCreatedAtBefore(JobStatus.PROCESSING, cutoff);
    for (Job job : stale) {
        job.setStatus(JobStatus.FAILED);
        job.setErrorMessage("Job timed out after 5 minutes");
        job.setUpdatedAt(Instant.now());
        jobRepository.save(job);
    }
}
```

---

## 13. Observability

### Structured Logging

Every pipeline step logs with the job ID as a correlation identifier using SLF4J MDC:

```java
MDC.put("jobId", jobId.toString());
log.info("Transcript extracted, length={}", transcript.length());
log.info("Claims detected: {}", claims.size());
log.info("Fact check results: {}", factCheckResults.size());
log.info("Search results retrieved: {}", searchResults.size());
log.info("LLM reasoning complete for claim: {}", claimText);
MDC.clear();
```

### Log Format

```
2026-03-16 10:01:23 INFO [jobId=abc-123] Transcript extracted, length=342
2026-03-16 10:01:25 INFO [jobId=abc-123] Claims detected: 3
2026-03-16 10:01:26 INFO [jobId=abc-123] Fact check results: 1
2026-03-16 10:01:28 INFO [jobId=abc-123] Search results retrieved: 5
2026-03-16 10:01:32 INFO [jobId=abc-123] LLM reasoning complete for claim: "Hot water cures cancer"
```

### Future Observability Improvements

- Metrics endpoint via Spring Actuator + Micrometer
- Grafana dashboard: job throughput, latency percentiles, cache hit rate
- Request latency tracking per pipeline stage

---

## 14. Rate Limiting

Public endpoints that trigger LLM calls require rate limiting to prevent cost explosions and abuse.

### Configuration

```
5 requests per minute per IP address
```

### Implementation

Use Bucket4j with Spring Boot:

```java
@Bean
public RateLimiterConfig rateLimiterConfig() {
    return RateLimiterConfig.custom()
        .limitForPeriod(5)
        .limitRefreshPeriod(Duration.ofMinutes(1))
        .timeoutDuration(Duration.ZERO)
        .build();
}
```

### Response on Limit Exceeded

```
HTTP 429 Too Many Requests
{
  "error": "Rate limit exceeded. Maximum 5 requests per minute."
}
```

---

## 15. System Constraints

| Constraint | Value | Rationale |
|------------|-------|-----------|
| Supported platforms | YouTube only | Other platforms actively resist scraping |
| Maximum video length | 3 minutes | Controls transcription cost and processing time |
| Maximum claims per video | 5 | Caps per-request LLM and search API costs |
| Job timeout | 5 minutes | Prevents stuck jobs from consuming resources |
| Cache TTL | 24 hours | Balances freshness with cost savings |
| Idempotency window | 24 hours | Same URL reuses recent results |
| Rate limit | 5 requests / minute / IP | Prevents API cost abuse |
| Tavily free tier | 1,000 searches / month | Hard budget constraint; track usage |

---

## 16. Cost Considerations

### Estimated Cost Per Request (Cache Miss)

| Step | API | Cost | Latency |
|------|-----|------|---------|
| Transcript (Whisper API, 1 min) | OpenAI | ~$0.006 | 2-3s |
| Claim extraction (GPT-4o-mini) | OpenAI | ~$0.003 | 1-2s |
| Fact Check API | Google | Free | <1s |
| Search retrieval (per claim) | Tavily | ~$0.01 | 1-2s |
| LLM reasoning (GPT-4o, per claim) | OpenAI | ~$0.02 | 3-5s |
| **Total (1 claim)** | | **~$0.04** | **8-13s** |
| **Total (3 claims, worst case)** | | **~$0.10** | **10-20s** |

### Cost Mitigation

- **Redis caching** at the claim level avoids repeat analysis of identical claims
- **Idempotent submission** avoids reprocessing the same video within 24 hours
- **YouTube auto-captions** used first, Whisper API only as fallback
- **GPT-4o-mini** for classification (cheaper), GPT-4o only for reasoning
- **Claim cap** of 5 per video limits worst-case cost
- **Video length cap** of 3 minutes limits transcription cost

---

## 17. Evaluation Framework

### Purpose

Measure system accuracy against a known dataset to demonstrate engineering maturity and quantify output quality.

### Dataset

Create a dataset of 30 claims with known verdicts:

```
10 claims that are clearly false
10 claims that are clearly true
5 claims that are misleading or lack context
5 claims that are ambiguous or hard to verify
```

Each entry includes:

```json
{
  "claim": "Hot water cures cancer",
  "expected_verdict": "LIKELY_FALSE",
  "expected_confidence_range": [80, 100],
  "source": "WHO"
}
```

### Evaluation Process

1. Run each claim through the pipeline
2. Compare system verdict against expected verdict
3. Check if confidence falls within expected range
4. Compute accuracy metrics

### Metrics

```
verdict_accuracy:     % of claims where system verdict matches expected verdict
confidence_calibration: average distance between actual and expected confidence
source_relevance:     % of claims where system cites a relevant source
```

### Automation

A Spring Boot test class or standalone script runs the evaluation suite and produces a summary report. This can run as part of the CI pipeline to detect regressions.

---

## 18. Development Roadmap

### Week 1 -- Backend Foundation

- Initialize Spring Boot project with Spring Web, Data JPA, Validation
- Configure PostgreSQL connection and Flyway/Liquibase migrations
- Create database schema: jobs, claims, sources, claim_sources tables
- Implement `POST /api/analyze` with input validation
- Implement `GET /api/jobs/{id}` with status polling
- Implement async job pipeline skeleton (`@Async` + `CompletableFuture`)
- Implement idempotent video submission (24-hour dedup on URL)
- Implement transcript extraction: YouTube captions via yt-dlp, Whisper API fallback
- Set up Springdoc OpenAPI for automatic API documentation

### Week 2 -- AI Pipeline

- Implement two-stage claim extraction (classify + normalize) using GPT-4o-mini
- Design and test the claim extraction prompt against sample transcripts
- Integrate Google Fact Check Tools API
- Integrate Tavily Search API
- Implement parallel evidence retrieval (Fact Check + Search run concurrently)
- Implement LLM reasoning step using GPT-4o with structured JSON output
- Implement response validation layer (enum check, range check, retry logic)
- Store results in normalized PostgreSQL tables

### Week 3 -- System Hardening

- Configure Redis and implement claim-level caching with `@Cacheable`
- Implement rate limiting with Bucket4j (5 req/min/IP)
- Configure Resilience4j circuit breakers for all external API calls
- Implement job timeout reaper (`@Scheduled`)
- Add structured logging with MDC job correlation
- Add input validation: URL format, playlist/channel/live rejection
- Add video length validation (reject >3 minutes after metadata fetch)

### Week 4 -- Polish and Delivery

- Build simple web UI (HTML + JavaScript page for URL submission and result display)
- Create evaluation dataset (30 claims) and run accuracy test
- Write Dockerfiles for Spring Boot app, PostgreSQL, Redis
- Write docker-compose.yml for one-command local setup
- Set up GitHub Actions CI (build + test on push)
- Write README with architecture diagram, setup instructions, and sample output
- Write 3 Architecture Decision Records:
  - "Why monolith over microservices"
  - "Why polling over WebSockets"
  - "Why credibility scores over binary verdicts"

---

## 19. Resume Value

### Engineering Skills Demonstrated

| Skill Area | What This Project Shows |
|------------|------------------------|
| Backend architecture | Async job pipeline, structured API design, input validation |
| AI integration | Multi-stage LLM pipeline with structured output validation |
| RAG implementation | Search-based retrieval augmented generation |
| Data engineering | Normalized relational schema, claim deduplication |
| Caching strategy | Redis claim-level caching with hash-based keys |
| Resilience | Circuit breakers, retry logic, job timeout reaper |
| Observability | Structured logging with correlation IDs |
| Cost optimization | Tiered LLM usage, caching, deduplication, input constraints |
| Quality engineering | Evaluation dataset with accuracy metrics |
| DevOps | Docker Compose, CI/CD, API documentation |

### Resume Bullet Points

```
Designed and built an async AI pipeline that processes YouTube video
claims through speech-to-text, two-stage claim extraction, parallel
search-based RAG, and LLM reasoning -- with circuit breakers, Redis
deduplication, and a 30-claim evaluation suite measuring verdict accuracy.
```

```
Implemented a Spring Boot backend orchestrating five external AI services
with Resilience4j circuit breakers, structured LLM output validation,
claim-level Redis caching, and normalized PostgreSQL storage.
```

### Additional Portfolio Differentiators

- **Architecture Decision Records** in `/docs/decisions/` demonstrating senior-level tradeoff reasoning
- **Docker Compose one-command setup** allowing reviewers to run the system in under 60 seconds
- **OpenAPI documentation** with example requests and responses
- **Measurable accuracy metrics** (e.g., "85% verdict accuracy on 30-claim test suite")
- **CI pipeline** running tests on every push

---

## 20. Future Improvements

These items are excluded from V1 but represent natural extensions:

| Improvement | Value |
|-------------|-------|
| Chrome browser extension | Seamless UX: analyze videos without leaving the platform |
| Server-Sent Events (SSE) | Replace polling with real-time status updates |
| Instagram / TikTok support | Broader platform coverage |
| Local Whisper inference | Eliminate transcription API costs at scale |
| Vector database (FAISS / Pinecone) | Embedding-based retrieval for claims not covered by search APIs |
| Confidence decomposition | Break score into sub-scores: source agreement, source quality, claim specificity |
| Grafana dashboard | Visualize job throughput, latency, cache hit rates |
| Load test results (k6) | Demonstrate performance under concurrent load |
| User feedback loop | Let users flag incorrect verdicts to improve prompt quality over time |

---

## Appendix: Technology Reference

| Technology | Version (recommended) | Purpose |
|------------|----------------------|---------|
| Java | 21 (LTS) | Runtime |
| Spring Boot | 3.x | Application framework |
| PostgreSQL | 16 | Persistent storage |
| Redis | 7.x | Caching |
| Resilience4j | 2.x | Fault tolerance |
| Bucket4j | 8.x | Rate limiting |
| Springdoc OpenAPI | 2.x | API documentation |
| yt-dlp | latest | YouTube media extraction |
| Docker | latest | Containerization |
| GitHub Actions | -- | CI/CD |
