# Data Sources

> Status: active
>
> When to use this runbook: registering, rotating, and troubleshooting external data-API integrations consumed by AI agents and workflows.

## Table of Contents

- [Prerequisites](#prerequisites)
- [When to use this](#when-to-use-this)
- [Overview](#overview)
- [Supported Source Types](#supported-source-types)
- [Models](#models)
- [HTTP API](#http-api)
- [Procedure — register a new source](#procedure--register-a-new-source)
- [Procedure — rotate a credential](#procedure--rotate-a-credential)
- [Quota Enforcement Pattern](#quota-enforcement-pattern)
- [Discovery & effectiveness (Phase 2a)](#discovery--effectiveness-phase-2a)
- [Quality, drift & contracts (Phase 2b)](#quality-drift--contracts-phase-2b)
- [Monitoring a source for changes (Phase 3)](#monitoring-a-source-for-changes-phase-3)
- [Stale-while-revalidate & stale-if-error](#stale-while-revalidate--stale-if-error)
- [Sync & Health Jobs](#sync--health-jobs)
- [Verification](#verification)
- [Rollback](#rollback)
- [Troubleshooting](#troubleshooting)
- [Key Files](#key-files)

## Prerequisites

- Backend running and reachable.
- `ai.data_sources.read` + `ai.data_sources.manage` permissions for admin operators.
- Vault accessible (credentials are stored encrypted).
- For external APIs requiring auth: a vendor-issued API key with sufficient quota.

## When to use this

- Adding a new external data integration (weather, market data, news, etc.).
- Rotating an API key after expiry / leak.
- Diagnosing rate-limit or quota errors hit by an AI agent.
- Investigating a source whose health status flipped to `degraded` / `critical`.

## Overview

Data Sources is the unified registry for external data providers that the platform consumes — weather, economic indicators, sports, news, etc. Each source has a stable configuration (capabilities, rate limits, default parameters), separately-encrypted credentials with first-class multi-credential support, and per-source health tracking. Rate-limiting is enforced client-side via `check_quota!` before outbound calls, and admins can test connections and rotate credentials without redeploying.

> **Live fetches (Phase 1).** This runbook covers the *registry* — defining sources and credentials. The governed *fetch pipeline* that agents and workflows use to actually read data (kill flag, per-agent fairness, response cache, circuit breaker, SSRF guard, decode/normalize, cost attribution, and the hash-chained query log) is documented in [data-source-fetch-pipeline.md](data-source-fetch-pipeline.md).
>
> **Discovery & effectiveness (Phase 2a).** On top of the registry, each source now carries a learned `effectiveness_score` (accrued from real fetches) and is semantically discoverable. The operational side — monitoring scores/usage, backfilling knowledge-graph nodes, and what the ranking weights mean — is in [Discovery & effectiveness (Phase 2a)](#discovery--effectiveness-phase-2a) below.
>
> **Quality, drift & contracts (Phase 2b).** Each *endpoint* can opt into response schema-drift tracking, data-quality expectations, and quarantine-on-failure, with an aggregate contract verdict and an OpenAPI importer. **All three stages are OFF by default** — zero overhead until enabled. Operating them — monitoring the `data_source_schema_drift` signal, quarantine + last-known-good behavior, tuning expectations, and SLA/contract ownership — is in [Quality, drift & contracts (Phase 2b)](#quality-drift--contracts-phase-2b). The enable-and-configure walkthrough is in [../guides/data-sources.md](../guides/data-sources.md#enabling-quality--drift-per-endpoint-phase-2b).
>
> **Monitoring & stale-serving (Phase 3).** A pull-based **monitor** can poll a chosen endpoint on a cadence (a `subscription`), change-detect the result, and emit a `data_source_changed` signal — driven by two thin worker crons (monitor `*/5`, health `*/10`) over server-side `Ai::DataSources::MonitorService`. Separately, endpoints can opt into **stale-while-revalidate** and **stale-if-error** cache policies (both nullable columns, **OFF by default**). The operating side — the cron, `due_for_poll` auto-recovery, quota-aware polling, the change signal, and SWR/SIE behavior — is in [Monitoring a source for changes (Phase 3)](#monitoring-a-source-for-changes-phase-3) and [Stale-while-revalidate & stale-if-error](#stale-while-revalidate--stale-if-error). The create-a-subscription / enable-the-policy walkthrough is in [../guides/data-sources.md](../guides/data-sources.md#monitoring-a-source-for-changes-phase-3).

## Supported Source Types

From `Ai::DataSource::SOURCE_TYPES`:

| Type | Description |
|------|-------------|
| `noaa_ncei` | NOAA National Centers for Environmental Information — historical climate data |
| `noaa_gfs` | NOAA Global Forecast System — numerical weather prediction |
| `noaa_observations` | NOAA current observations |
| `open_meteo` | Open-Meteo — free weather API (no key for historical / forecast) |
| `fred` | Federal Reserve Economic Data — macroeconomic indicators |
| `yahoo_finance` | Yahoo Finance — market data |
| `espn` | ESPN — sports data |
| `newsapi` | NewsAPI — news aggregation |
| `custom` | Arbitrary custom-adapter source |

Health status values: `healthy`, `degraded`, `critical`, `unknown`.

## Models

### `Ai::DataSource` (`ai_data_sources`)

```ruby
belongs_to :account
has_many :credentials,
         class_name: "Ai::DataSourceCredential",
         foreign_key: "ai_data_source_id",
         dependent: :destroy

# Identity / typing
name                  # unique per account (case-insensitive)
slug                  # auto-generated from name on create; URL param
source_type           # one of SOURCE_TYPES
priority_order        # ordering when multiple sources serve similar capabilities

# Behavior
is_active             # global on/off
requires_auth         # whether this source needs a credential
health_status         # healthy | degraded | critical | unknown

# JSON columns (lambda defaults)
capabilities          # [] — list of capability strings this source provides
configuration         # {} — source-specific config (endpoints, timeouts, etc.)
rate_limits           # { "requests_per_minute": N, "requests_per_hour": N, "requests_per_day": N }
default_parameters    # {} — merged into each outbound request
metadata              # {} — free-form annotations
```

**Key methods:**

- `active_credential` — returns the active+default credential, else the most recent active credential
- `api_key` — convenience delegate to `active_credential.decrypted_api_key`
- `healthy?` — active + health status in `{healthy, unknown}`
- `check_quota!` — returns `{ allowed: true }` or `{ allowed: false, retry_after: N, limit: "name" }` based on current per-minute / per-hour / per-day usage

**Scopes:** `active`, `by_type(type)`, `for_account(account)`, `ordered_by_priority`, `requiring_auth`.

### `Ai::DataSourceCredential` (`ai_data_source_credentials`)

Encrypted credential records bound to a `DataSource`. Each data source can hold multiple credentials (e.g. rotating keys, per-environment keys). Exactly one can be marked `default` per source. `decrypted_api_key` returns the plaintext for outbound requests — handled inside services only, never exposed on the wire.

## HTTP API

All endpoints require `ai.data_sources.*` permissions. CRUD requires `create` / `update` / `delete` respectively; read paths require `read`.

### Data Sources

| Method | Path | Purpose | Permission |
|--------|------|---------|------------|
| `GET` | `/api/v1/ai/data_sources` | List with filters, sort, pagination | `ai.data_sources.read` |
| `GET` | `/api/v1/ai/data_sources/:id` | Detail with embedded credentials | `ai.data_sources.read` |
| `POST` | `/api/v1/ai/data_sources` | Create | `ai.data_sources.create` |
| `PATCH` | `/api/v1/ai/data_sources/:id` | Update | `ai.data_sources.update` |
| `DELETE` | `/api/v1/ai/data_sources/:id` | Delete | `ai.data_sources.delete` |
| `POST` | `/api/v1/ai/data_sources/:id/test_connection` | Probe the source using its active credential | `ai.data_sources.read` |
| `GET` | `/api/v1/ai/data_sources/:id/quota_status` | Current usage vs configured rate limits | `ai.data_sources.read` |

`:id` accepts either the UUID or the slug (via `to_param`).

### Credentials

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/v1/ai/data_sources/:data_source_id/credentials` | List credentials for a source |
| `POST` | `/api/v1/ai/data_sources/:data_source_id/credentials` | Create a new credential |
| `PATCH` | `/api/v1/ai/data_sources/:data_source_id/credentials/:id` | Update |
| `DELETE` | `/api/v1/ai/data_sources/:data_source_id/credentials/:id` | Delete |
| `POST` | `/api/v1/ai/data_sources/:data_source_id/credentials/:id/test` | Test a single credential |
| `POST` | `/api/v1/ai/data_sources/:data_source_id/credentials/:id/make_default` | Mark as the default for this source |

> **Crypto safety:** API keys are never returned in responses or written to logs. `decrypted_api_key` is accessed only from backend services that need to make outbound HTTP calls.

## Procedure — register a new source

1. Create the source via `POST /api/v1/ai/data_sources`:

   ```json
   {
     "data_source": {
       "name": "NOAA GFS",
       "source_type": "noaa_gfs",
       "is_active": true,
       "requires_auth": false,
       "rate_limits": {
         "requests_per_minute": 60,
         "requests_per_hour": 1000
       }
     }
   }
   ```

2. If the source requires auth, attach a credential:

   ```json
   POST /api/v1/ai/data_sources/:id/credentials
   {
     "credential": {
       "name": "primary",
       "api_key": "...",
       "is_default": true,
       "is_active": true
     }
   }
   ```

3. Test the connection:

   ```bash
   curl -X POST \
     -H "Authorization: Bearer $JWT" \
     https://api.powernode.example.com/api/v1/ai/data_sources/:id/test_connection
   ```

4. Confirm `health_status` becomes `healthy`.

## Procedure — rotate a credential

1. Create a new credential on the source (`is_default: false`).
2. Test it via `POST /api/v1/ai/data_sources/:id/credentials/:new_id/test` → expect `success: true`.
3. Promote it: `POST /api/v1/ai/data_sources/:id/credentials/:new_id/make_default`.
4. Verify the old credential is no longer active default, then delete it.

## Quota Enforcement Pattern

Before any outbound request:

```ruby
source = Ai::DataSource.find_by!(slug: "noaa_gfs")
quota  = source.check_quota!
unless quota[:allowed]
  raise "Rate limited on #{quota[:limit]}, retry_after=#{quota[:retry_after]}s"
end

# Proceed with API call using source.api_key (if required)
```

`check_quota!` reads from `current_quota_usage` (hour / minute / day counters tracked per source). Exceeding any configured limit returns a non-allowed response with `retry_after`.

## Discovery & effectiveness (Phase 2a)

Phase 2a layers two operator-relevant capabilities onto the registry: a per-source **effectiveness score** that accrues from real fetches, and **semantic discovery** that ranks sources for a natural-language need. Both are backed by a `data_source`-type node in the knowledge graph (one per source), embedded with the same `Ai::Memory::EmbeddingService` used for skills. This section covers what to monitor, how to backfill the graph nodes, and how to read the ranking weights operationally.

### Monitoring effectiveness_score & usage

Each `Ai::DataSource` carries five Phase-2a columns that update on the **live-fetch** path (never on cache hits, kill-flag blocks, or quota short-circuits — those don't exercise the upstream):

| Column | Default | Meaning |
|--------|---------|---------|
| `effectiveness_score` | `0.5` | Rolled-up 0..1 trust score; recomputed on every 5th recorded outcome |
| `usage_count` | `0` | Total live fetches recorded against the source |
| `positive_usage_count` | `0` | Live fetches with a `success` outcome |
| `negative_usage_count` | `0` | Live fetches with a `failure` outcome |
| `last_used_at` | — | Timestamp of the most recent recorded fetch |

The score is a blend (see [ranking weights](#what-the-ranking-weights-mean-operationally)):

```
effectiveness_score = 0.3 * kg_confidence + 0.4 * usage_success_rate + 0.3 * freshness
```

Surface it without writing any SQL via the existing read surfaces:

```bash
# Per-source trust signals + usage (REST detail / serialize_data_source carries these)
curl -s -H "Authorization: Bearer $JWT" \
  https://api.powernode.example.com/api/v1/ai/data_sources/:id \
  | jq '.data.data_source | {effectiveness_score, usage_count, positive_usage_count, negative_usage_count, usage_success_rate, last_used_at}'

# Usage + trust IMPACT summary for one source (MCP — distinct agents, query-count breakdown, health, trust signals)
#   platform.data_source_impact  data_source_id: ":id"

# Health payload now includes the trust_signals block alongside quota/cache/breaker
#   platform.data_source_health  data_source_id: ":id"
```

What to watch for:

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `effectiveness_score` stuck at `0.5` | No live fetches yet (only cache hits / blocks), or never recomputed | Confirm `usage_count` is advancing; the recompute fires only every 5th outcome |
| Score dropping despite a healthy source | `usage_success_rate` falling — upstream returning errors on live fetches | Check `negative_usage_count` trend and `data_source_impact` failed counts; inspect provider |
| Low score on a fine source | `kg_confidence` defaulting to `0.5` (no KG node) or stale `freshness` | Backfill the KG node (below); a never-used source decays `freshness` toward neutral |
| `effectiveness_score` present but source never appears in discovery | The source has **no embedded `data_source` KG node** | Run the backfill (`sync_all_data_sources`) — discovery ranks KG nodes, not raw rows |

> **Counters are source-wide.** `record_query!` accepts an `agent:` argument but per-agent attribution is reserved for a later phase — today the counters and `effectiveness_score` are aggregated across all requesting agents. Per-agent usage breakdown is available *read-only* via `data_source_impact` (distinct requesting-agent count), which reads the `ai_data_source_queries` log, not the rolled-up counters.

### Backfilling knowledge-graph nodes

Semantic discovery ranks **`data_source` knowledge-graph nodes**, not `ai_data_sources` rows directly. A node is created/refreshed automatically on every source create/update via the guarded `after_commit :sync_to_knowledge_graph` callback — **but only when an embedding field changed** (`name` / `description` / `source_type` / `slug`). Counter, health, and effectiveness updates deliberately do **not** re-embed. So you must backfill when:

- the feature was enabled on an account with **pre-existing** sources (their nodes were never built),
- sources were created in an environment with **no embedding backend** (the node exists but has a nil embedding — discovery silently falls back to keyword matching), or
- you want to refresh embeddings after bulk-editing endpoint names (endpoint names feed the embedding text but don't trip the per-field guard).

Backfill an account's sources with `Ai::DataSourceGraph::BridgeService#sync_all_data_sources`, which iterates the account's **active** sources and upserts a node per source:

```ruby
# rails runner — backfill one account's data_source KG nodes
account = Account.find_by!(slug: "acme")            # or Account.find(<id>)
result  = Ai::DataSourceGraph::BridgeService.new(account).sync_all_data_sources
# => { synced: 12, failed: 0 }
Rails.logger.info("[data-sources] KG backfill: #{result.inspect}")
```

```ruby
# Re-sync a single source (e.g. after editing its endpoints)
ds = Ai::DataSource.for_account(account).find_by!(slug: "open-meteo")
Ai::DataSourceGraph::BridgeService.new(account).sync_data_source(ds)   # returns the node, or nil on failure
```

Behavior to rely on operationally:

- Each node is `entity_type: "data_source"`, linked by `ai_data_source_id`, with `confidence: 1.0` and an embedding built from `name | description | category:<source_type> | endpoints:<names>`. Its `properties` mirror the source: `source_type`, `protocol`, `auth_scheme`, `health_status`, `is_active`, `effectiveness_score`, `usage_count`, `endpoint_count`.
- It **degrades, never crashes**: with no embedding backend the node is still upserted with a nil embedding (and `sync_data_source` returns the node); only a node it could not write returns `nil` and increments `failed`. `sync_all_data_sources` logs `{ synced:, failed: }` so a backfill is auditable from the logs.
- The reuse is exact — `BridgeService` uses the same `Ai::KnowledgeGraph::GraphService` and `Ai::Memory::EmbeddingService` as the skill graph, so embedding-backend health is shared across both subsystems.

Verify a backfill:

```bash
# MCP: count data_source nodes in the graph
#   platform.list_graph_nodes  entity_type: "data_source"

# Then confirm discovery returns them
curl -s -X POST -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{"query":"weather forecast","limit":5}' \
  https://api.powernode.example.com/api/v1/ai/data_sources/discover | jq '.data | {count, results: [.results[] | {slug, score, signals}]}'
```

### What the ranking weights mean operationally

Two different weight sets are in play — keep them distinct when reasoning about a result:

**1. Discovery ranking weights** (`SemanticDiscoveryService::WEIGHTS`) — how a *result is ordered* for a query:

| Signal | Weight | Operational reading |
|--------|--------|---------------------|
| `semantic` | `0.55` | Cosine similarity (`1 - distance`) between the query embedding and the source's node embedding. Dominates — it answers "does this source match the intent". `0.5` (neutral) on the keyword-fallback path when there's no embedding. |
| `effectiveness` | `0.25` | The source's rolled-up `effectiveness_score`. The quality tie-breaker — a proven source outranks an unproven one of equal relevance. |
| `health` | `0.10` | `1.0` if `healthy?` (active + health `healthy`/`unknown`), else `0.0`. A `critical`/`degraded` source is pushed down but not excluded. |
| `recency` | `0.10` | Linear decay of `last_used_at` over a 7-day window; never-used sources get a neutral `0.5` so they aren't buried under stale-but-recently-touched ones. |

The blended `score` (and each `signals` value) is returned per result, so you can see *why* a source ranked where it did. A generous candidate pool (50 KG nodes) is pulled from pgvector before the blend, so a high-`effectiveness` source a few slots down in raw cosine order can still be promoted.

> **Operational levers.** Because `semantic` dominates at `0.55`, the highest-leverage fix for "discovery surfaces the wrong source" is the **embedding text** — a clearer source `name`/`description` and well-named endpoints (re-run the backfill after editing). The next lever is `effectiveness` at `0.25`, which you cannot set directly — it is *earned* through successful live fetches. `health` and `recency` (`0.10` each) only break near-ties.

**2. Effectiveness blend weights** (`Ai::DataSource#recalculate_effectiveness!`) — how the *score itself is computed*: `kg_confidence 0.3 / usage_success_rate 0.4 / freshness 0.3`. Note `usage_success_rate` is the heaviest input here — sustained successful fetches are what move a source's standing the most; `kg_confidence` (the KG node's confidence, `0.5` when no node) and `freshness` (7-day recency decay) round it out.

> **Optional LLM reranking.** `data_source_discover` / the `discover` REST action accept `rerank: true`, which routes the post-blend top candidates through `Ai::Rag::RerankingService` and folds its relevance back into the `semantic` signal. It is **off by default** because it consumes an LLM call when a scoring agent is present (it degrades to a heuristic ordering otherwise). Leave it off for high-volume or hermetic discovery; enable it only when ranking precision matters more than cost/latency.

## Quality, drift & contracts (Phase 2b)

Phase 2b adds per-**endpoint** response observability to the governed fetch: schema-drift tracking, data-quality expectations, quarantine-on-failure, an OpenAPI importer, and an aggregate contract verdict. This section is the *operating* side — what to watch and how to tune. The enable-and-configure walkthrough (flags, writing `Ai::DataSourceExpectation` rules, importing a spec, reading a verdict) is in the [guide](../guides/data-sources.md#enabling-quality--drift-per-endpoint-phase-2b).

> **Default-off, zero-overhead.** The three endpoint flags — `track_schema`, `quality_checks_enabled`, `quarantine_on_failure` — default `false`. Until an operator flips them, `QueryService` runs no extra work and the `FetchEnvelope` is identical to pre-2b. The stages run **only on live fetches** (after decode/normalize) — never on a cache hit, kill-flag block, or quota short-circuit — and each is individually nil-safe (a stage that raises is logged and skipped, never failing the fetch).

The columns that drive everything (on `ai_data_source_endpoints`, all the booleans default `false`):

| Column | Type | Role |
|--------|------|------|
| `track_schema` | bool | Enable schema-drift versioning on live fetches |
| `quality_checks_enabled` | bool | Run quality expectations on live fetches |
| `quarantine_on_failure` | bool | Serve last-known-good when quality fails (requires `quality_checks_enabled`) |
| `sla_max_age_seconds` | int | Freshness budget for the contract verdict (`within_sla`); nil = no SLA |
| `owner` | string | Contract/SLA owner (free-form) |
| `contract` | jsonb | Free-form contract metadata (default `{}`) |

Per-fetch outcomes land on the `ai_data_source_queries` row (and are mirrored into provenance): `quality_score` (decimal), `quality_passed` (bool), `quarantined` (bool, default `false`), `schema_drift` (string classification). The full version history lives in `ai_data_source_schema_versions`; the rules live in `ai_data_source_expectations`.

### Monitoring schema-drift signals

When `track_schema` is on, every live fetch infers a JSON-Schema snapshot from the records (`QueryService#infer_schema` emits an **array-root** schema, `{type: array, items: {type: object, properties: {...}}}`) and appends a version via `Ai::DataSources::SchemaDriftService#record_version!`. Each version is classified against its immediate predecessor:

| Classification | Meaning | Drift? |
|----------------|---------|--------|
| `initial` | First version for the endpoint (no prior schema) | No |
| `none` | Structurally identical to the previous version (same checksum → no new row appended, idempotent) | No |
| `additive` | Fields added, none removed/retyped — backward-compatible for a consumer | Soft |
| `breaking` | A field was removed **or** changed type | Hard |

> **CONSUME-direction semantics.** Because the platform *reads* external APIs, extra response fields are always safe — so any pure addition is `additive` (the JSON-Schema `required` array is not consulted). Only a removal or a type change is `breaking`.

The operationally important behavior: a **`breaking`** classification emits a **stigmergic signal** so autonomous agents perceive the drift without polling:

```
Ai::Coordination::StigmergicSignalService#emit!
  signal_type: "warning"
  signal_key:  "data_source_schema_drift"     # ← the key to watch
  strength:    1.0
  payload:     { data_source_id, data_source_slug, endpoint_id, endpoint_slug,
                 schema_version, classification, diff }
```

Every drifted version (anything but `none`) also appends a `schema_drift_<classification>` anomaly to the fetch's `provenance.anomalies` and stamps the `schema_drift` column on the query-log row.

How to watch for it:

```bash
# MCP — perceive the warning signal stream (filter on the drift key)
#   platform.perceive_signals  signal_type: "warning"
#   → look for signal_key "data_source_schema_drift" entries (payload carries the diff)

# Per-endpoint version history (newest-first), incl. the structural diff per version
#   platform.data_source_schema_history  data_source_id: ":id"  endpoint_id: ":ep"
# REST equivalent (requires ai.data_sources.read):
curl -s -H "Authorization: Bearer $JWT" \
  https://api.powernode.example.com/api/v1/ai/data_sources/:id/endpoints/:ep/schema_history \
  | jq '.data | {count, latest: .latest | {version, classification}, versions: [.versions[] | {version, classification}]}'
```

What to do on a `breaking` signal:

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `data_source_schema_drift` warning fired | Upstream removed/retyped a response field | Inspect the version `diff` (`removed_fields` / `type_changes`) via `schema_history`; update `response_mapping`/`response_schema` and any downstream consumers |
| `schema_drift` column stuck at `initial` | Only one version recorded — endpoint just enabled, or always returns the same shape | Expected; the next *changed* shape produces `additive`/`breaking` |
| No versions appended despite `track_schema` | Endpoint only served cache hits / blocks (no live fetch), or every fetch is byte-identical (idempotent `none`) | Confirm live fetches are happening; identical schemas are deduped by checksum |

### Quarantine behavior & last-known-good

`quarantine_on_failure` is the **safety valve** — it stops a bad batch from reaching agents. It only acts when **all** of these hold: the fetch was HTTP-successful, `quality_checks_enabled` ran and `quality_passed == false` (an **error**-severity rule failed), and `quarantine_on_failure` is set. When it fires:

1. The bad batch is **replaced** with the **last-known-good** payload — `QueryService#quarantine_records` *reads* (never writes) `Ai::DataSources::ResponseCacheService.read` for the same `data_source`/`endpoint`/params. If no prior good payload exists, it serves an **empty batch** (`[]`).
2. `quarantined: true` is set on the row and in provenance, and a `quarantined` anomaly is appended.
3. The **bad payload is not cached** — `finalize` skips the cache write when `@quarantined`, so the next fetch still compares against the genuine last-known-good, not the poisoned one.

> **A quarantined fetch is HTTP-successful but quality-failed.** `success: true` in the envelope (the upstream answered), but `quality_passed: false` and `quarantined: true`. Agents should treat `quarantined` as "stale-but-safe data served" — the served records are the previous good batch (or empty), not the failing one.

Operating notes:

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `quarantined: true` on every fetch | An error-severity expectation is too strict (or the upstream genuinely degraded) | Inspect the latest `quality` outcome (`results`/`anomalies`); loosen the rule to `warn` or fix the upstream |
| Quarantine serves `[]` (empty) | No last-known-good in cache yet (cold endpoint, or caching disabled) | Run a clean fetch that *passes* quality first to seed the cache; check the `data_source_response_caching` kill flag isn't off |
| Quality fails but nothing quarantines | Only **warn**-severity rules failed (warn never quarantines), or `quarantine_on_failure` is off | Quarantine needs an explicit **error** rule + the flag; the built-in defaults are warn-only |

### Tuning quality expectations

Quality is evaluated by `Ai::DataSources::QualityService` over the endpoint's **active** `Ai::DataSourceExpectation` rows (`expectations.active`). The two levers are `severity` and the per-rule `config`.

**Severity is the master switch:**

- **`error`** — failing sets `passed: false` for the batch (and quarantines when enabled). Error rules also weigh **double** in the score.
- **`warn`** — failing only lowers `quality_score`; the batch still passes.

So `passed` is `false` **only** when an error rule fails; `quality_score` = `earned_weight / total_weight` (error 2, warn 1), rounded to 4 dp.

> **Built-in defaults when none configured.** With `quality_checks_enabled` on but **no** active expectations, two WARN defaults run: `non_empty` (`min_records >= 1`) and `uniform_shape` (record-shape consistency). They give you a baseline `quality_score`/`quality_passed` signal but — being WARN — never fail the batch, so **quarantine never triggers until you add at least one `error` rule.**

Tuning workflow:

1. **Start in `warn`.** Add new rules as `warn` first and watch `quality_score` and the `quality_results` for a few fetches via the `quality` read — confirm the rule is measuring what you expect before it can fail a batch.
2. **Promote to `error`** only the rules that should block bad data (and trigger quarantine). Keep "nice to have" checks at `warn`.
3. **Ratchet `config` gradually** — e.g. raise `min_records`, tighten `allowed_values`, lower `distribution.max_null_ratio` — re-reading the outcome between changes.

The six rule types and their `config` keys are in the [guide](../guides/data-sources.md#step-2--write-aidatasourceexpectation-rules). There is **no REST/MCP CRUD** for expectations — manage the rows at the model layer (`endpoint.expectations`, keyed by `ai_data_source_endpoint_id`). Read the current rules + latest outcome:

```bash
# MCP: flags + configured expectations + latest distilled quality outcome
#   platform.data_source_quality  data_source_id: ":id"  endpoint_id: ":ep"
# REST equivalent (requires ai.data_sources.read):
curl -s -H "Authorization: Bearer $JWT" \
  https://api.powernode.example.com/api/v1/ai/data_sources/:id/endpoints/:ep/quality \
  | jq '.data | {quality_checks_enabled, quarantine_on_failure, latest, expectations: [.expectations[] | {name, rule_type, severity, is_active}]}'
```

### SLA & contract ownership

A **contract verdict** (`Ai::DataSources::ContractService`) rolls the three Phase-2b signals into one answer — `schema_valid`, `quality_passed`, and `within_sla` → `{ met, violations }`. Operationally:

- **`within_sla`** compares the served payload's `cache_age_seconds` to `endpoint.sla_max_age_seconds`. Set `sla_max_age_seconds` to declare a freshness budget; an unset SLA is **never violated** (`within_sla: true`). A breach adds `sla_exceeded` to `violations`.
- **A `nil` signal is "not asserted"**, not a violation — an endpoint with no `response_schema`, no quality verdict, and no SLA yields a vacuously `met: true` contract. `met` is true exactly when `violations` is empty.
- **`owner`** (and the free-form `contract` jsonb) record who owns the SLA/contract for the endpoint — read-only metadata for routing a breach to the right team. Set it when you set the SLA so a `sla_exceeded`/`schema_invalid`/`quality_failed` verdict is actionable.

The verdict read is **non-fetching** — `GET .../endpoints/:ep/contract` (and the `data_source_contract` MCP action) build it from the endpoint's **most recent recorded query-log row**, so a GET never triggers an outbound call and a never-queried endpoint is vacuously met:

```bash
# MCP:  platform.data_source_contract  data_source_id: ":id"  endpoint_id: ":ep"
curl -s -H "Authorization: Bearer $JWT" \
  https://api.powernode.example.com/api/v1/ai/data_sources/:id/endpoints/:ep/contract \
  | jq '.data | {met, schema_valid, quality_passed, within_sla, violations}'
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `met: false`, `violations: ["sla_exceeded"]` | Served payload older than `sla_max_age_seconds` | Lower `cache_ttl_seconds`, check upstream availability, or relax the SLA; route to `owner` |
| `met: false`, `violations: ["schema_invalid"]` | Last fetch failed `response_schema` validation | Inspect `schema_history` diff; update the schema/mapping |
| `within_sla: null` | An SLA is set but the row carries no cache age | Expected for some rows; the next fetch with a known cache age resolves it |
| Verdict always `met: true` on a watched endpoint | No assertions configured (no schema, no quality, no SLA) | Add a `response_schema`, enable `quality_checks_enabled` with error rules, and/or set `sla_max_age_seconds` |

## Monitoring a source for changes (Phase 3)

Phase 3 adds a **pull-based monitor**: a subscription (`Ai::DataSourceSubscription`, table `ai_data_source_subscriptions`) binds a source + endpoint to a poll cadence, and a worker cron drives `Ai::DataSources::MonitorService` to poll due subscriptions, change-detect, and emit a `data_source_changed` signal on change. **All poll/fetch/change-detect/signal logic runs server-side** — the worker fires only thin cron triggers. The create-a-subscription walkthrough (MCP `data_source_subscribe` / REST `subscriptions_create`, the `ai.data_sources.stream` permission, cadence values) is in the [guide](../guides/data-sources.md#monitoring-a-source-for-changes-phase-3); this section is the *operating* side.

### The monitor & health crons

Two thin Sidekiq cron jobs (in `worker/config/sidekiq.yml`) are the only worker-side moving parts. Each POSTs an **mTLS, worker-only internal** endpoint and logs the batch summary — they hold no business logic:

| Job class | Cron | Internal endpoint (POST) | Server entry point | Returns |
|-----------|------|--------------------------|--------------------|---------|
| `AiDataSourceMonitorJob` | `*/5 * * * *` | `/api/v1/internal/ai/data_sources/monitor_tick` | `MonitorService#tick(limit: 100)` | `{ polled:, changed:, errors: [{subscription_id:, error:}] }` |
| `AiDataSourceHealthJob` | `*/10 * * * *` | `/api/v1/internal/ai/data_sources/health_tick` | `MonitorService#health_tick` | `{ refreshed:, errors: [] }` |

Both internal routes live under the `Api::V1::Internal::Ai` namespace and inherit the `InternalBaseController` mTLS auth (`authenticate_worker_via_mtls!`, JWT skipped) like every other `/api/v1/internal/*` path. `monitor_tick` accepts an optional `limit` (clamped 1..1000, default 100); `health_tick` takes no params and calls `source.update_health_status!` on every **active** source.

```bash
# Tail the monitor cron summary (polled / changed / errors per tick)
journalctl -u powernode-worker@default -f | grep AiDataSourceMonitorJob
# Tail the health sweep summary (refreshed / errors)
journalctl -u powernode-worker@default -f | grep AiDataSourceHealthJob
```

> **Why thin?** Per the worker architecture the standalone Sidekiq worker never touches the DB or the fetch pipeline directly — it triggers, the server does the work. A `monitor_tick` failure retries once (`retry: 1`); a single bad subscription never fails the tick (see below).

### `due_for_poll` & auto-recovery semantics

`MonitorService#tick` polls `Ai::DataSourceSubscription.due_for_poll` — **the single most important behavior to understand operationally**:

```ruby
scope :due_for_poll, -> {
  where(status: %w[active error])
    .where("next_poll_at IS NOT NULL AND next_poll_at <= ?", Time.current)
}
```

- **It INCLUDES `error`-status subscriptions.** A subscription that tripped the failure threshold (`consecutive_failures >= 5` → `status: "error"`) keeps being polled. That is the **only** path that can clear `error` back to `active` (a successful `record_poll!` resets the counter and flips the status), so a failing subscription **self-heals** once the upstream recovers. Excluding `error` would silently stop monitoring forever.
- **It EXCLUDES operator-set `paused`.** `paused` is the intentional off switch — `pause!` sets `status: "paused"` and `next_poll_at: nil`, and a paused subscription is never picked up. Use it to stop a subscription without deleting it.
- Per poll, the monitor still respects the parent source's `check_quota!`: a throttled source **defers** the poll to the next tick (re-schedules without counting a failure) rather than burning its budget on background monitoring.
- **Per-subscription failures never abort the batch** — each is caught, `record_failure!`'d, and collected into the tick's `errors` array, so one broken subscription cannot stall the others.

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Subscription `status: "error"`, `consecutive_failures` climbing | Upstream returning errors on the polled endpoint | It is *still polling* (auto-recovery) — inspect the upstream; check `last_polled_at` is advancing and `metadata.last_error` |
| Subscription stuck — never polls | `status: "paused"` (operator off switch) or `poll_frequency: "manual"` (never auto-polls) | `activate!` to resume, or set a non-manual cadence; confirm `next_poll_at` is non-nil |
| `next_poll_at` in the past but not polled | Monitor cron not running, or `tick` `limit` saturated by a backlog | Confirm `AiDataSourceMonitorJob` is scheduled; raise `limit` for a one-off catch-up POST to `monitor_tick` |
| Subscription deferred every tick | Parent source quota exhausted | Check `quota_status`; the poll re-schedules without a failure until the source has budget |

### Change-signal monitoring

When a poll detects a change (new canonical SHA-256 checksum vs the stored `last_checksum`, or no prior checksum on the first poll), the monitor:

1. Warms **only that param-variant's** `ResponseCacheService` entry with the fresh payload — it does **not** blanket-invalidate the endpoint, so sibling subscriptions and interactive reads keep their own cached variants.
2. Emits a **stigmergic signal** so autonomous agents perceive the update without polling:

```
Ai::Coordination::StigmergicSignalService#emit!
  signal_type: "discovery"
  signal_key:  "data_source_changed"          # ← the key to watch
  agent:       nil                              # system-emitted (no agent attribution)
  strength:    1.0
  payload:     { slug, data_source_id, endpoint, endpoint_id, subscription_id, checksum }
```

A matching ETag on both the response and the subscription short-circuits to "unchanged" (304-style revalidation) regardless of checksum. An unchanged poll emits no signal and warms no cache.

```bash
# MCP — perceive the discovery signal stream (filter on the change key)
#   platform.perceive_signals  signal_type: "discovery"
#   → look for signal_key "data_source_changed" entries (payload carries the checksum + ids)
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| No `data_source_changed` signals despite a live source | Upstream payload is byte-stable (checksum unchanged) or every poll is deferred/failing | Confirm `changed` > 0 in the monitor-tick log; check the upstream actually changes between polls |
| Signal fires on every poll | Upstream returns a non-deterministic field (timestamp, request id) so the checksum never repeats | Narrow the endpoint `response_mapping`/`query_template` so volatile fields aren't in the canonical payload |
| Change detected but cache not warm for interactive reads | The interactive read used different `params` (a different cache variant) | Expected — the monitor warms only the subscription's param-variant; align params or add a subscription per variant |

## Stale-while-revalidate & stale-if-error

Phase 3 adds two **opt-in, per-endpoint** stale-serving cache policies on `Ai::DataSourceEndpoint`, both nullable and **OFF by default**. When **both** `stale_while_revalidate_seconds` and `stale_if_error_seconds` are nil, the cache is **byte-for-byte the legacy behavior** — the Redis key's TTL equals the hard TTL and the `FetchEnvelope` is unchanged. The enable-the-policy walkthrough is in the [guide](../guides/data-sources.md#enabling-stale-serving-cache-policies-per-endpoint-phase-3); this is the operating mechanics.

| Column | Policy | Served when |
|--------|--------|-------------|
| `stale_while_revalidate_seconds` | **SWR** | The hard TTL has passed but the entry is within the SWR grace window — served immediately (flagged) while a background refresh repopulates it. |
| `stale_if_error_seconds` | **stale-if-error** | A *live* fetch failed with a transient fault (`error`/`timeout`) and a hard-expired entry is within the SIE window — served instead of failing. |

### The grace window (how the entry survives past expiry)

The key mechanic both policies share: `ResponseCacheService` stores a fixed **hard-expiry epoch** in the entry but keeps the Redis key alive for `hard_ttl + grace_window` seconds, where `grace_window = max(stale_while_revalidate_seconds, stale_if_error_seconds)`. So between the hard expiry and the end of the grace window the entry is **physically present but logically stale** — and the policies decide whether to serve it. Outside the grace window Redis has already evicted the key, so neither policy can ever serve beyond `max(swr, sie)` past expiry.

The shared read primitive is `ResponseCacheService.read_stale`, returning `{ payload:, stale:, hard_expired:, age_seconds:, stale_age_seconds: }` (or nil on miss). `stale_age_seconds` counts seconds **past the hard expiry** (0 while fresh) — the SWR/SIE windows are measured against *that*, per HTTP `Cache-Control` `stale-*` semantics (the window starts when the entry goes stale, not when it was written). `read_stale` is a side-channel read and **does not** count toward the cache hit/miss metrics.

### SWR operational behavior

On `ResponseCacheService.fetch`, when the entry is hard-expired but within the SWR window, the service:

1. Records a **hit** and returns the stale payload immediately (non-blocking serve).
2. Schedules a **single** background refresh — an NX-locked (one refresher per key per window) detached `Thread` wrapped in `ActiveRecord::Base.connection_pool.with_connection` (so the refetch's DB work checks out and releases its own connection rather than leaking the pool under load), which calls `MonitorService#refresh!` to re-warm the entry. A failure there is swallowed — the stale value was already served.

So under SWR, *one* reader after expiry eats a stale serve + triggers the refresh; the *next* reader gets the fresh value. This trades a brief window of slightly-stale data for removing the latency spike of a synchronous refetch.

### Stale-if-error operational behavior

Stale-if-error lives in `QueryService` (not the cache layer) because it reacts to a fetch *outcome*. After a live fetch returns `error` or `timeout` (and **only** those — `blocked` and `rate_limited` are deliberate policy rejections, not upstream outages, and are passed through untouched), if the endpoint sets `stale_if_error_seconds` and a hard-expired entry exists within that window, the failure is swapped for the last-known-good payload via `read_stale`. The substituted result is flagged so it reads as an honest degraded serve, not a fresh success:

```jsonc
{
  "success": true,
  "status": "cached",
  "provenance": {
    "stale_if_error": true,
    "served_on_error": "timeout",        // the failure status that triggered the serve
    "from_cache": true,
    "cache_age_seconds": 920,
    "stale_age_seconds": 320,
    "anomalies": ["stale_if_error", "…"]
  }
}
```

It is recorded with `served_stage: "stale_if_error"` and **never re-writes the cache** (finalize only writes on a *fresh* success), so the genuine last-known-good is preserved for the next caller. A still-*fresh* entry would have satisfied the cache layer before the fetch ever ran, so if the failure path is reached with a non-expired entry the failure is unrelated to staleness and is passed through rather than masked.

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Endpoint still hard-fails on a transient upstream error | `stale_if_error_seconds` is nil/0, or no last-known-good in the grace window | Set `stale_if_error_seconds`; confirm a prior successful fetch seeded the cache and the entry is within `max(swr, sie)` of expiry |
| Stale-if-error not serving for a `blocked`/`rate_limited` result | By design — those are policy rejections, not upstream faults | Expected; only `error`/`timeout` qualify. Address the quota/kill-flag instead |
| SWR never refreshes in the background | `MonitorService` undefined in the process, or the NX refresh lock is held | Confirm the server (not worker) serves the cache; the lock auto-expires — a stuck lock self-clears within the lock TTL |
| Cache "grew" a longer TTL after enabling | Expected — the Redis key now lives `hard_ttl + max(swr, sie)` so stale reads can find it; the hard-expiry epoch is unchanged | None; disable both columns to restore the legacy `TTL == hard_ttl` |

## Sync & Health Jobs

Provider model sync and health monitoring for data sources run in the worker. Jobs tag logs with `data_source_id` and post health transitions via the audit log, so operators see state flips in both `Monitoring` dashboards and `Trading::AuditLog` (where applicable). The Phase-3 monitor + health crons are documented above in [Monitoring a source for changes](#monitoring-a-source-for-changes-phase-3).

## Verification

After registering / rotating:

```bash
curl -H "Authorization: Bearer $JWT" \
  https://api.powernode.example.com/api/v1/ai/data_sources/:id | jq '.data.health_status'
# Expect "healthy"

curl -H "Authorization: Bearer $JWT" \
  https://api.powernode.example.com/api/v1/ai/data_sources/:id/quota_status | jq
# Expect counters reset / fresh

# Worker logs show no auth failures
journalctl -u powernode-worker@default --since "5 minutes ago" | grep "data_source_id=$ID"
```

## Rollback

To revert a credential rotation:

1. Re-create the previous credential.
2. `POST /credentials/:old_id/make_default`.
3. Test, then delete the new (broken) credential.

To disable a source entirely:

```bash
curl -X PATCH \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"data_source":{"is_active":false}}' \
  https://api.powernode.example.com/api/v1/ai/data_sources/:id
```

## Troubleshooting

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `health_status = critical` | Repeated upstream failures | Run `test_connection`; inspect provider's status page |
| `quota_status` shows ~0 limit | Misconfigured `rate_limits` | Patch `rate_limits` JSON column to a sane value |
| Credential test passes but agent fails | Wrong default credential | Run `make_default` on the working credential |
| Source missing from `active_credential` | `is_active = false` | Re-enable credential |

## Key Files

| Role | Path |
|------|------|
| Model — Data Source | `server/app/models/ai/data_source.rb` (`record_query!`, `recalculate_effectiveness!`, `usage_success_rate`) |
| Model — Endpoint (Phase 2b/3) | `server/app/models/ai/data_source_endpoint.rb` (2b: `track_schema`/`quality_checks_enabled`/`quarantine_on_failure`/`sla_max_age_seconds`/`owner`/`contract`; 3: `stale_while_revalidate_seconds`/`stale_if_error_seconds`; `has_many :schema_versions`/`:expectations`/`:subscriptions`) |
| Model — Subscription (Phase 3) | `server/app/models/ai/data_source_subscription.rb` (`POLL_FREQUENCIES`, `STATUSES`; `.active`/`.due_for_poll`/`.for_data_source`/`.for_endpoint`; `record_poll!`/`record_failure!`/`schedule_next_poll!`/`activate!`/`pause!`) |
| Model — Credential | `server/app/models/ai/data_source_credential.rb` |
| Model — Schema version (Phase 2b) | `server/app/models/ai/data_source_schema_version.rb` (`CLASSIFICATIONS`; `for_endpoint`/`ordered`/`latest_first`/`breaking`) |
| Model — Quality expectation (Phase 2b) | `server/app/models/ai/data_source_expectation.rb` (`RULE_TYPES`, `SEVERITIES`; `active`/`errors`) |
| Model — KG node | `server/app/models/ai/knowledge_graph_node.rb` (`data_source` entity type, `.data_source_nodes`, `.for_data_source`) |
| Service — KG bridge (Phase 2a) | `server/app/services/ai/data_source_graph/bridge_service.rb` (`sync_data_source`, `sync_all_data_sources`) |
| Service — Semantic discovery (Phase 2a) | `server/app/services/ai/data_sources/semantic_discovery_service.rb` (`WEIGHTS`, `#discover`) |
| Service — Schema drift (Phase 2b) | `server/app/services/ai/data_sources/schema_drift_service.rb` (`#diff`, `#record_version!`; `INITIAL`/`NONE`/`ADDITIVE`/`BREAKING`) |
| Service — Quality (Phase 2b) | `server/app/services/ai/data_sources/quality_service.rb` (`#evaluate`) |
| Service — OpenAPI import (Phase 2b) | `server/app/services/ai/data_sources/open_api_import_service.rb` (`#import`) |
| Service — Contract (Phase 2b) | `server/app/services/ai/data_sources/contract_service.rb` (`#validate`) |
| QueryService wiring (Phase 2b/3) | `server/app/services/ai/data_sources/query_service.rb` (2b: `#apply_observability_stages`, `#track_schema_drift`, `#evaluate_quality`, `#quarantine_records`; 3: `#maybe_serve_stale_if_error`, `#build_stale_if_error_result`) |
| Service — Monitor (Phase 3) | `server/app/services/ai/data_sources/monitor_service.rb` (`#tick`, `#health_tick`, `#refresh!`; `CHANGE_SIGNAL_KEY = "data_source_changed"`) |
| Cache SWR/SIE (Phase 3) | `server/app/services/ai/data_sources/response_cache_service.rb` (`.read_stale`, `#grace_window`, `#schedule_background_refresh`) |
| Controller — Sources | `server/app/controllers/api/v1/ai/data_sources_controller.rb` (`#discover`; subscription permission gating) |
| Controller concern — Endpoints (Phase 2b/3) | `server/app/controllers/concerns/ai/data_source_endpoints.rb` (2b: `#schema_history`, `#quality`, `#contract`, `#introspect`; 3: `#subscriptions_index`, `#subscriptions_create`, `#subscriptions_destroy`) |
| Internal controller (Phase 3) | `server/app/controllers/api/v1/internal/data_sources_controller.rb` (`#monitor_tick`, `#health_tick`; mTLS worker-only) |
| Worker crons (Phase 3) | `worker/app/jobs/ai_data_source_monitor_job.rb` (`*/5`), `worker/app/jobs/ai_data_source_health_job.rb` (`*/10`) — thin triggers to the internal ticks |
| Controller — Credentials | `server/app/controllers/api/v1/ai/data_source_credentials_controller.rb` |
| Serialisation concern | `server/app/controllers/concerns/ai/data_source_serialization.rb` (effectiveness/usage fields) |
| MCP tool | `server/app/services/ai/tools/data_source_tool.rb` (`data_source_discover` / `_provenance` / `_impact`; 2b: `_schema_history` / `_quality` / `_contract` / `_introspect`; 3: `_subscribe` / `_unsubscribe`, `STREAM_ACTIONS` gated by `ai.data_sources.stream`) |
| Routes | `server/config/routes.rb` (`resources :data_sources`; collection `post :discover`; 2b: `endpoints/:endpoint_id/{schema_history,quality,contract}`, `post :introspect`; 3: `{get,post} :subscriptions` + `delete subscriptions/:subscription_id`; internal `ai/data_sources/{monitor_tick,health_tick}`) |
| Permissions (Phase 3) | `server/config/permissions.rb` (`ai.data_sources.stream` — granted to `member`/`manager`/`ai_specialist`) |

---

## Related runbooks

- [data-source-fetch-pipeline.md](data-source-fetch-pipeline.md) — Phase 1: the governed fetch pipeline (kill flag, per-agent fairness, response cache, circuit breaker, SSRF guard, decode/normalize, cost, hash-chained query log) and its troubleshooting
- [../guides/data-sources.md](../guides/data-sources.md) — Phase 2a/2b/3 from the agent/author angle: discover → describe → query, how effectiveness accrues, reading trust signals, enabling per-endpoint quality/drift/contracts, creating monitoring subscriptions, and enabling SWR/stale-if-error
- [ai-operations.md](ai-operations.md) — AI provider sister system; same encryption / credential patterns
- [worker-operations.md](worker-operations.md) — Sync / health jobs schedule

## Materials previously at

- `docs/platform/DATA_SOURCES.md`

_Last verified: 2026-06-06_
