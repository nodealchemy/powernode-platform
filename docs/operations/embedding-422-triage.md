# Triage: recurring `WorkerEmbeddingClient` 422 "Failed to generate embedding"

**Status:** Root-caused — action required is **configuration** (and an optional
worker-side error-message improvement). No safe server-code fix was applied; see
"Why no code change" below.

## Symptom

The server development log shows bursts (many per second) of:

```
[WorkerEmbeddingClient] Request failed (422): {"error":"Failed to generate embedding"}
```

## Root cause

The 422 originates in the **worker** (`worker/app/controllers/jobs_controller.rb#generate_embedding`):
it returns `422 "Failed to generate embedding"` when `Ai::EmbeddingService#generate`
returns `nil`. That nil happens when the account has **no embedding-capable AI
provider with a resolvable credential** — the worker's `resolve_api_key` returns
nil, so `generate_openai_embedding` short-circuits to nil.

- The server request is **correct**: `WorkerEmbeddingClient#generate`
  (`server/app/services/worker_embedding_client.rb:25-32`) sends `{ text, account_id }`,
  which exactly matches the worker's required params. **Do not** add `model`/
  `dimensions` — the worker intentionally owns model selection.
- The real failure detail is logged **only in the worker** log
  (`[EmbeddingService] Failed to generate embedding: …`); the server sees only the
  opaque 422.

The burst is the same single failure multiplied across the many callers of
`Ai::Memory::EmbeddingService` (RAG indexing, knowledge-graph extraction, agent
memory, semantic discovery — ~25 services). The tight RAG loops
(`server/app/services/ai/rag_service.rb#embed_chunks`, `#perform_sync`) raise and
abort on first failure, but memory/discovery callers that swallow-and-continue keep
re-attempting, producing the per-second storm.

## Fix (in priority order)

1. **Configure an embedding-capable provider for the affected account** (the actual
   fix). Add an OpenAI provider with a valid credential, or an Ollama provider with
   an embedding model. Once `default_provider`/credential resolves, the 422 stops.
   Confirm the precise cause in the **worker** log line above.
2. *(Optional, worker-side — for a worker maintainer)* Make the worker return a
   specific message/status so the server log shows *why* (e.g.
   `422 "No embedding credential configured for account"` vs a `502` for upstream
   provider errors). Per the worker-boundary rule this must be done in `worker/`,
   not from a server task.
3. *(Optional, server-side resilience — needs explicit sign-off)* Add a short
   negative-cache / fail-fast in `Ai::Memory::EmbeddingService` so an unconfigured
   account short-circuits before the worker round-trip (caps the storm to ~1 call/
   minute/account). Deferred here because a naive provider-capability guard could
   wrongly short-circuit valid Ollama/edge configurations — it needs a deliberate
   capability-detection decision before shipping.

## Why no code change was applied here

The root cause is **configuration**, not a server bug; the request contract is
correct; the diagnostic gap is **worker-side**; and the only server-side code option
(a guard in the shared `EmbeddingService`) carries embedding-regression risk that is
out of scope for the AI-navigation refactor this was found alongside. Following
"Audit = report only" and the worker-boundary rule, this is documented for an
explicit decision rather than changed speculatively.

## Key files

- `server/app/services/worker_embedding_client.rb` (request contract)
- `server/app/services/ai/memory/embedding_service.rb` (`generate_from_provider`, `default_provider`)
- `server/app/services/ai/rag_service.rb` (`embed_chunks`, `generate_embedding`, `perform_sync`)
- `server/app/controllers/api/v1/internal/ai/execution_contexts_controller.rb#embedding_config`
- `worker/app/controllers/jobs_controller.rb#generate_embedding` (worker-side; emits the 422)
- `worker/app/services/ai/embedding_service.rb` (worker-side; returns nil → 422)
