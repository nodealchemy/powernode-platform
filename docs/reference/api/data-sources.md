# Data Sources API

> Status: active
>
> Authoritative reference for the Data Source HTTP + MCP surface: catalog CRUD, nested endpoint CRUD, the governed query action, the `data_source_*` MCP actions, and the `ai_data_source_endpoints` / `ai_data_source_queries` schema.
>
> **Phase 2a (discovery + evaluation)** adds semantic discovery (`POST /discover`, the `data_source_discover` MCP action), per-fetch effectiveness/trust scoring (the `effectiveness_score` / `usage_*` serializer fields), and two new audit/usage MCP actions (`data_source_provenance`, `data_source_impact`). These build on the Phase-1 surface below — they are flagged inline and grouped in [Phase 2a additions](#phase-2a-additions).
>
> **Phase 2b (quality / drift / contracts / introspection)** adds opt-in response-schema drift tracking, data-quality expectations with quarantine, an aggregate data-contract verdict, and OpenAPI 3 introspection. Surfaced as four REST routes (`GET endpoints/:id/{schema_history,quality,contract}`, `POST :id/introspect`) and four MCP actions (`data_source_schema_history` / `data_source_quality` / `data_source_contract` = read, `data_source_introspect` = manage, `dry_run`). Two new tables (`ai_data_source_schema_versions`, `ai_data_source_expectations`), quality columns on `ai_data_source_queries`, and opt-in/SLA/contract columns on `ai_data_source_endpoints` back it. **All three endpoint observability flags default `false`** — a pre-2b endpoint runs the exact same fetch with zero added overhead. Grouped in [Phase 2b additions](#phase-2b-additions).
>
> **Phase 3 (streaming / monitoring)** adds pull-based **subscriptions**: a `(data_source, endpoint)` pairing with a poll cadence that the server-side `Ai::DataSources::MonitorService` walks, change-detects (etag / SHA256 checksum), and on change warms the cache + emits a `data_source_changed` stigmergic signal. Subscriptions are managed over REST (`GET/POST/DELETE /data_sources/:id/subscriptions`) and MCP (`data_source_subscribe` / `data_source_unsubscribe`, gated by the new `ai.data_sources.stream` grant). The standalone worker only fires two thin mTLS cron ticks (`POST /api/v1/internal/ai/data_sources/{monitor,health}_tick`) — all poll/fetch/signal logic is server-side. Phase 3 also wires the **stale-while-revalidate / stale-if-error** cache policies via two opt-in endpoint columns (`stale_while_revalidate_seconds` / `stale_if_error_seconds`, nil = OFF) and adds the `ai_data_source_subscriptions` table. Grouped in [Phase 3 additions](#phase-3-additions).

## Table of Contents

- [Overview](#overview)
- [Permissions](#permissions)
- [REST: Data Sources](#rest-data-sources)
  - [List data sources](#list-data-sources)
  - [Get a data source](#get-a-data-source)
  - [Create a data source](#create-a-data-source)
  - [Update a data source](#update-a-data-source)
  - [Delete a data source](#delete-a-data-source)
  - [Test connection](#test-connection)
  - [Quota status](#quota-status)
- [Phase 2a additions](#phase-2a-additions)
  - [Effectiveness + trust signals](#effectiveness--trust-signals)
  - [REST: Discover (semantic search)](#rest-discover-semantic-search)
  - [MCP: discovery + evaluation actions](#mcp-discovery--evaluation-actions)
- [Phase 2b additions](#phase-2b-additions)
  - [Opt-in observability wiring](#opt-in-observability-wiring)
  - [REST: Schema history](#rest-schema-history)
  - [REST: Quality](#rest-quality)
  - [REST: Contract verdict](#rest-contract-verdict)
  - [REST: Introspect (OpenAPI import)](#rest-introspect-openapi-import)
  - [MCP: quality + drift + contract + introspection actions](#mcp-quality--drift--contract--introspection-actions)
- [Phase 3 additions](#phase-3-additions)
  - [Subscriptions + the monitor loop](#subscriptions--the-monitor-loop)
  - [Stale-while-revalidate / stale-if-error](#stale-while-revalidate--stale-if-error)
  - [REST: Subscriptions](#rest-subscriptions)
  - [Internal: worker monitor / health ticks](#internal-worker-monitor--health-ticks)
  - [MCP: subscription actions](#mcp-subscription-actions)
- [REST: Endpoints (nested)](#rest-endpoints-nested)
  - [List endpoints](#list-endpoints)
  - [Create an endpoint](#create-an-endpoint)
  - [Update an endpoint](#update-an-endpoint)
  - [Delete an endpoint](#delete-an-endpoint)
- [REST: Query (governed fetch)](#rest-query-governed-fetch)
- [MCP: `data_source_*` actions](#mcp-data_source_-actions)
- [Schema reference](#schema-reference)
  - [`ai_data_source_endpoints`](#ai_data_source_endpoints)
  - [`ai_data_source_queries`](#ai_data_source_queries)
  - [`ai_data_source_schema_versions` (2b)](#ai_data_source_schema_versions)
  - [`ai_data_source_expectations` (2b)](#ai_data_source_expectations)
  - [`ai_data_source_subscriptions` (3)](#ai_data_source_subscriptions)
- [Related docs](#related-docs)

## Overview

The data-source surface lets the React frontend and AI agents register external APIs, define declarative request/response **endpoints** under them, and run a single audited, cached, SSRF-guarded, redacted fetch that returns canonical records plus a complete provenance record. It is exposed two ways with 1:1 parity:

- **REST** — `Api::V1::Ai::DataSourcesController` (`server/app/controllers/api/v1/ai/data_sources_controller.rb`), under the `Api::V1` namespace. Catalog CRUD lives on the controller; nested endpoint CRUD + the query action are mixed in via the `Ai::DataSourceEndpoints` concern (`server/app/controllers/concerns/ai/data_source_endpoints.rb`), and JSON serialization via `Ai::DataSourceSerialization` (`server/app/controllers/concerns/ai/data_source_serialization.rb`). All paths are prefixed with `/api/v1`.
- **MCP** — `Ai::Tools::DataSourceTool` (`server/app/services/ai/tools/data_source_tool.rb`), exposed as the `data_source_management` tool and registered per-action in `PlatformApiToolRegistry`.

All responses follow the unified envelope (`render_success` / `render_error` / `render_validation_error`) documented in [`overview.md`](overview.md#response-format). All paths are JWT-authenticated; the worker service token bypasses the per-action permission gate (`validate_permissions` returns early for `current_worker`).

Conceptual background — the protocol/adapter/decoder model, the decode/normalize layers, the `QueryService` pipeline, the response cache, and the security model — is in [`../../concepts/data-sources.md`](../../concepts/data-sources.md). The register/rotate/troubleshoot runbook is in [`../../operations/data-sources.md`](../../operations/data-sources.md).

> Credential CRUD is a separate surface (`DataSourceCredentialsController`, `/ai/data_sources/:id/credentials`) and is not covered here — see [`api/ai.md`](ai.md#data-sources).

## Permissions

Defined in `server/config/permissions.rb`. Checked in `validate_permissions` for REST (skipped when `current_worker` is present) and per-action inside `DataSourceTool#call` for MCP.

| Permission | Grants |
|------------|--------|
| `ai.data_sources.read` | View sources, endpoints, quota, health, validate config; run `test_connection`; list subscriptions |
| `ai.data_sources.query` | Run the governed fetch (the `query` action) |
| `ai.data_sources.create` | Create a source |
| `ai.data_sources.update` | Update a source; create/update/delete its endpoints |
| `ai.data_sources.delete` | Delete a source |
| `ai.data_sources.manage` | Super-grant — satisfies any create/update/delete; gates `introspect` |
| `ai.data_sources.stream` *(3)* | Create/cancel pull-based subscriptions (`subscriptions_create` / `subscriptions_destroy`; MCP `data_source_subscribe` / `data_source_unsubscribe`) |

The `ai.data_sources.stream` grant (added in `permissions.rb`) is seeded onto the `member`, `manager`, and `ai_specialist` roles.

REST per-action mapping (`DataSourcesController#validate_permissions`):

| Action(s) | Permission |
|-----------|-----------|
| `index`, `show`, `quota_status`, `test_connection`, `endpoints_index`, `discover`, `subscriptions_index` | `ai.data_sources.read` |
| `create` | `ai.data_sources.create` |
| `update` | `ai.data_sources.update` |
| `destroy` | `ai.data_sources.delete` |
| `endpoints_create`, `endpoints_update`, `endpoints_destroy` | `ai.data_sources.update` **or** `ai.data_sources.manage` (`require_any_permission`) |
| `endpoints_query` | `ai.data_sources.query` |
| `schema_history`, `quality`, `contract` *(2b)* | `ai.data_sources.read` |
| `introspect` *(2b)* | `ai.data_sources.manage` (even `dry_run` — it is a write surface) |
| `subscriptions_create`, `subscriptions_destroy` *(3)* | `ai.data_sources.stream` |

## REST: Data Sources

All sources are scoped to the caller's account (`current_account` / `current_user.account`). A missing source returns `404` (`render_error("Data source not found", status: :not_found)`); a missing account context returns `401`.

### List data sources

```
GET /api/v1/ai/data_sources
```

Query params: `source_type`, `is_active`, `search` (ILIKE on `name`), `sort` (`priority` (default) | `name` | `created_at`), `page` (default 1), `per_page` (default 20, max 100).

Response (`200`) — `items` are serialized via `serialize_data_source`:

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "account_id": "uuid",
        "name": "Open-Meteo",
        "slug": "open-meteo",
        "source_type": "open_meteo",
        "is_active": true,
        "requires_auth": false,
        "api_base_url": "https://api.open-meteo.com",
        "priority_order": 100,
        "capabilities": [],
        "health_status": "unknown",
        "last_health_check_at": null,
        "effectiveness_score": 0.5,
        "usage_count": 0,
        "positive_usage_count": 0,
        "negative_usage_count": 0,
        "usage_success_rate": 0.5,
        "last_used_at": null,
        "created_at": "2026-06-06T00:00:00Z",
        "updated_at": "2026-06-06T00:00:00Z",
        "credential_count": 0,
        "stats": { "credentials_count": 0 }
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_pages": 1,
      "total_count": 1
    }
  }
}
```

The `effectiveness_score` / `usage_count` / `positive_usage_count` / `negative_usage_count` / `usage_success_rate` / `last_used_at` fields are Phase 2a additions present on **every** serialized source (list and detail) — see [Effectiveness + trust signals](#effectiveness--trust-signals).

### Get a data source

```
GET /api/v1/ai/data_sources/:id
```

Response (`200`) — `serialize_data_source_detail` (the list shape plus the fields below):

```json
{
  "success": true,
  "data": {
    "data_source": {
      "id": "uuid",
      "name": "FRED",
      "slug": "fred",
      "source_type": "fred",
      "description": "Federal Reserve Economic Data",
      "documentation_url": "https://fred.stlouisfed.org/docs/api",
      "configuration": {},
      "default_parameters": {},
      "rate_limits": {},
      "metadata": {},
      "credentials": [
        {
          "id": "uuid",
          "name": "primary",
          "is_active": true,
          "is_default": true,
          "expires_at": null,
          "last_used_at": null,
          "last_test_at": null,
          "last_test_status": null,
          "last_error": null,
          "created_at": "2026-06-06T00:00:00Z",
          "updated_at": "2026-06-06T00:00:00Z",
          "data_source": { "id": "uuid", "name": "FRED", "source_type": "fred" },
          "stats": {
            "success_count": 0,
            "failure_count": 0,
            "consecutive_failures": 0,
            "success_rate": 0
          }
        }
      ],
      "quota": { }
    }
  }
}
```

`quota` is `data_source.quota_summary` (Redis-backed minute/hour/day window usage). Credential responses never include key material — only health/metadata.

### Create a data source

```
POST /api/v1/ai/data_sources
```

Body — keyed under `data_source`, permitted by `data_source_params`:

```json
{
  "data_source": {
    "name": "Open-Meteo",
    "slug": "open-meteo",
    "source_type": "open_meteo",
    "description": "Free weather API",
    "api_base_url": "https://api.open-meteo.com",
    "is_active": true,
    "requires_auth": false,
    "priority_order": 100,
    "documentation_url": "https://open-meteo.com/en/docs",
    "capabilities": [],
    "configuration": {},
    "rate_limits": {},
    "default_parameters": {},
    "metadata": {}
  }
}
```

Permitted keys: `name`, `slug`, `source_type`, `description`, `api_base_url`, `is_active`, `requires_auth`, `priority_order`, `documentation_url`, and the JSON/array fields `capabilities` (array), `configuration`, `rate_limits`, `default_parameters`, `metadata` (hashes). `source_type` is a fixed enum (`noaa_ncei`, `noaa_gfs`, `noaa_observations`, `open_meteo`, `fred`, `yahoo_finance`, `espn`, `newsapi`, `custom`). `slug` is unique per account. **`protocol`, `auth_scheme`, and `auth_config` are not settable through this controller** in Phase 1 — they default to `rest` / `none` / `{}` and are configured at the model layer.

Response: `201` with `{ "data_source": <detail> }`, or `422` `render_validation_error` on invalid attributes. Emits the `ai.data_sources.create` audit event.

### Update a data source

```
PATCH /api/v1/ai/data_sources/:id
```

Same body shape and permitted keys as create. Response: `200` with `{ "data_source": <detail> }`, or `422` on validation failure. Emits the `ai.data_sources.update` audit event (with the list of changed columns).

### Delete a data source

```
DELETE /api/v1/ai/data_sources/:id
```

Response (`200`):

```json
{ "success": true, "data": { "message": "Data source deleted successfully" } }
```

`422` on a destroy that fails validation. Emits the `ai.data_sources.delete` audit event.

### Test connection

```
POST /api/v1/ai/data_sources/:id/test_connection
```

Performs a live `GET` against `api_base_url` using the source's `active_credential` (10s open/read timeout, `Bearer` auth applied when `requires_auth` and a decrypted key are present), and records success/failure on the credential. Returns `422` when no active credential exists.

Response (`200`):

```json
{
  "success": true,
  "data": {
    "success": true,
    "status_code": 200,
    "response_time_ms": 142,
    "message": "Connection successful"
  }
}
```

> Note this is a simpler, direct `Net::HTTP` probe, **not** the governed `QueryService` pipeline. On a raised exception it still returns `200` with `{ "success": false, "error": ..., "message": ... }`.

### Quota status

```
GET /api/v1/ai/data_sources/:id/quota_status
```

Response (`200`):

```json
{
  "success": true,
  "data": {
    "data_source": { "id": "uuid", "name": "FRED", "source_type": "fred" },
    "quota": { },
    "check": { }
  }
}
```

`quota` is `quota_summary` (current window usage); `check` is `check_quota!` (the allow/deny decision and remaining budget).

## Phase 2a additions

Phase 2a layers **discovery** and **evaluation** onto the Phase-1 catalog/query surface. Every governed *live* fetch now rolls a success/failure outcome into the source's effectiveness score, each source is mirrored into the knowledge graph as a `data_source` node with a pgvector embedding, and agents/UI can find the right source by intent (`/discover`, `data_source_discover`) and audit/measure usage after the fact (`data_source_provenance`, `data_source_impact`). No Phase-1 contract changed; the additions are purely additive.

### Effectiveness + trust signals

`serialize_data_source` (`Ai::DataSourceSerialization`) gained six fields, present on **both** the list and detail shapes:

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `effectiveness_score` | float (0..1) | `data_source.effectiveness_score&.to_f` | Blended trust score; **defaults to `0.5`** for a new source |
| `usage_count` | integer | `usage_count` | Total recorded live-fetch outcomes (defaults `0`) |
| `positive_usage_count` | integer | `positive_usage_count` | Successful live fetches (defaults `0`) |
| `negative_usage_count` | integer | `negative_usage_count` | Failed live fetches (defaults `0`) |
| `usage_success_rate` | float (0..1) | `usage_success_rate` | `positive / (positive + negative)`, **`0.5`** when there are no outcomes yet |
| `last_used_at` | ISO8601 / null | `last_used_at&.iso8601` | Timestamp of the last live fetch |

**How the score is maintained.** `Ai::DataSources::QueryService#finalize` calls `data_source.record_query!(outcome:, freshness:, agent:)` on **LIVE fetches only** — never on cache hits, and never on the kill-flag / quota short-circuit envelopes (those never reach `finalize`). `record_query!` performs a single `update_columns` write (deliberately bypassing the audit hash chain and the knowledge-graph re-sync `after_commit`, so hot-path counter bumps don't flood either) that increments `usage_count` and the matching `positive_usage_count` / `negative_usage_count`, sets `last_used_at`, and calls `recalculate_effectiveness!` on every 5th recorded outcome.

`recalculate_effectiveness!(freshness:)` recomputes (also via `update_columns`):

```
effectiveness_score = (0.3 * kg_confidence + 0.4 * usage_success_rate + 0.3 * freshness).round(4)
```

- `kg_confidence` = `knowledge_graph_node&.confidence&.to_f`, falling back to `0.5` when the source has no graph node.
- `usage_success_rate` = `positive / (positive + negative)`, or `0.5` when there are no outcomes (neutral, so brand-new sources aren't penalized).
- `freshness` = the explicit `freshness:` argument when supplied (clamped 0..1), otherwise a private `freshness_score`: a linear 7-day decay off the most recent of `last_used_at` / `last_health_check_at` (`1.0` when fresh, `0.0` at a week old, `0.5` when the source has never been used or health-checked).

Each source is also mirrored into the knowledge graph by `Ai::DataSourceGraph::BridgeService#sync_data_source(ds)`, which upserts an `Ai::KnowledgeGraphNode` (entity type `data_source`, `ai_data_source_id: ds.id`) carrying an embedding built from `name | description | category:<source_type> | endpoints:<names>` and `properties` `{ source_type, protocol, auth_scheme, health_status, is_active, effectiveness_score, usage_count, endpoint_count }`. It reuses the same `Ai::KnowledgeGraph::GraphService` + `Ai::Memory::EmbeddingService` as the skill graph, returns `nil` on any error (logged), and degrades to a node with no embedding when no embedding backend is available. The model's `after_commit :sync_to_knowledge_graph` is **guarded** to fire only when `name`, `description`, `source_type`, or `slug` changed — so the high-frequency counter/score `update_columns` writes never trigger a re-embed.

### REST: Discover (semantic search)

```
POST /api/v1/ai/data_sources/discover
```

Requires `ai.data_sources.read`. Ranks the caller's account sources by relevance to a natural-language need via `Ai::DataSources::SemanticDiscoveryService#discover`: it embeds the query, pulls the nearest `data_source` knowledge-graph nodes (pgvector cosine `nearest_neighbors`), maps each back to its `Ai::DataSource`, and blends a final 0..1 score from four signals — `semantic` (cosine similarity), `effectiveness` (the source's `effectiveness_score`), `health` (`1.0` if `healthy?`, else `0.0`), and `recency` (7-day linear decay of `last_used_at`) — weighted `semantic 0.55 / effectiveness 0.25 / health 0.10 / recency 0.10`. With no embedding backend it degrades to a keyword name match (`search_by_name`) with the semantic signal neutralized; `rerank: true` routes the top candidates through `Ai::Rag::RerankingService`.

Request body:

```json
{ "query": "hourly precipitation forecast", "limit": 10, "rerank": false }
```

| Field | Required | Default | Notes |
|-------|----------|---------|-------|
| `query` | yes | — | Natural-language data need; `422 "query is required"` when blank |
| `limit` | no | `10` | Max ranked results, clamped to `1..50` |
| `rerank` | no | `false` | Opt-in LLM reranking (consumes a model call when a scoring agent is present) |

Response (`200`) — each result is the full `serialize_data_source` shape (including the trust fields above) merged with the ranking `score` + `signals`:

```json
{
  "success": true,
  "data": {
    "query": "hourly precipitation forecast",
    "count": 1,
    "results": [
      {
        "id": "uuid",
        "name": "Open-Meteo",
        "slug": "open-meteo",
        "source_type": "open_meteo",
        "effectiveness_score": 0.72,
        "usage_count": 40,
        "positive_usage_count": 38,
        "negative_usage_count": 2,
        "usage_success_rate": 0.95,
        "last_used_at": "2026-06-06T00:00:00Z",
        "score": 0.81,
        "signals": { "semantic": 0.78, "effectiveness": 0.72, "health": 1.0, "recency": 0.91 }
      }
    ]
  }
}
```

Returns `401` on a missing account context. An empty account, a blank embedding with no keyword matches, etc. return `count: 0` with `results: []` (not an error).

### MCP: discovery + evaluation actions

`Ai::Tools::DataSourceTool` now carries **12 actions** — the original nine plus the three below, all gated by `ai.data_sources.read` (added to `READ_ACTIONS`; the proposal fallback applies only to the mutation actions). They are registered per-action in `PlatformApiToolRegistry`. Full parity details, params, and return shapes are in [MCP: `data_source_*` actions](#mcp-data_source_-actions). In addition, the existing `data_source_describe` and `data_source_health` payloads were extended with `effectiveness_score` and a `trust_signals` block (`effectiveness_score`, `usage_count`, `positive_usage_count`, `negative_usage_count`, `usage_success_rate`, `kg_confidence`, `last_used_at`, `health_status`, `healthy`).

| Action | Purpose | Params | Required permission |
|--------|---------|--------|---------------------|
| `data_source_discover` | Semantic discovery via `SemanticDiscoveryService` (embedding + pgvector NN, blended with effectiveness/health/recency; keyword fallback) | `query` (required), `limit?` (default 10, clamped 1..50), `rerank?` | `ai.data_sources.read` |
| `data_source_provenance` | Provenance of one recorded fetch — reads an `ai_data_source_queries` row's **already-redacted** provenance columns | `query_id?`, `correlation_id?`, `data_source_id?`, `endpoint_id?` (at least one selector required) | `ai.data_sources.read` |
| `data_source_impact` | Usage + trust summary for a source (distinct requesting agents, query-count breakdown, recency, effectiveness, health) | `data_source_id` (required) | `ai.data_sources.read` |

**`data_source_discover`** returns `{ query, count, results: [...] }` where each result is the compact source summary merged with `score` + `signals` (`{ semantic, effectiveness, health, recency }`) + `effectiveness_score` — the MCP analogue of the REST `/discover` response.

**`data_source_provenance`** resolves the target row account-scoped with precedence `query_id → correlation_id → latest query for a `data_source_id` (optionally scoped to `endpoint_id`)`, raising `ArgumentError` when no selector is given and not-found when nothing matches. It returns `{ provenance: { query_id, correlation_id, source, endpoint, fetched_at, status, http_status, duration_ms, bytes_in, rows_returned, response_sha256, redacted_url, schema_valid, cached, served_stage, redaction_applied, estimated_cost_usd, actual_cost_usd, anomalies, audit_chain } }`. **Redaction note:** this action performs **no** redaction itself — it surfaces columns that `Ai::DataSources::QueryService` already redacted at write time (`redacted_url` is the masked URL, `error`/snippets pass through `Ai::Security::PiiRedactionService`, `redaction_applied` records whether PII redaction ran). The `audit_chain` anchor is the `integrity_hash` / `previous_hash` / `sequence_number` mirror QueryService writes into the row's `metadata`.

**`data_source_impact`** returns `{ data_source, distinct_requesting_agents, query_counts: { total, successful, failed, cached }, last_used_at, effectiveness_score, health_status, trust_signals }`. Counts come from the `Ai::DataSourceQuery` scopes (`for_data_source`, `successful`, `failed`, `cached`); `distinct_requesting_agents` is a `DISTINCT` count of non-null `requesting_agent_id`.

## Phase 2b additions

Phase 2b layers **data observability** onto the governed fetch: per-endpoint response-schema **drift** history, **data-quality** expectations (with optional **quarantine** of bad batches), an aggregate **contract** verdict, and **OpenAPI 3 introspection** that mints endpoints from a spec. The new services are `Ai::DataSources::SchemaDriftService`, `Ai::DataSources::QualityService`, `Ai::DataSources::ContractService`, and `Ai::DataSources::OpenApiImportService` — see [`../../concepts/data-sources.md`](../../concepts/data-sources.md#data-quality-schema-drift--contracts-phase-2b) for their internals.

**Nothing in the Phase-1/2a contract changed.** The three endpoint flags (`track_schema`, `quality_checks_enabled`, `quarantine_on_failure`) all default `false`, so the `QueryService` pipeline and its `FetchEnvelope` are byte-for-byte identical to pre-2b until an endpoint opts in.

### Opt-in observability wiring

When an endpoint sets one of the flags, `Ai::DataSources::QueryService` runs an extra private `apply_observability_stages` pass **after normalization, on LIVE fetches only** — a cache hit returns the cached payload from `ResponseCacheService.fetch` and never re-decodes/normalizes, so the stages do not run on hits (consistent with `record_query!`). Each stage is individually nil-safe and a stage failure is logged and skipped, never breaking the fetch:

| Flag (on `ai_data_source_endpoints`) | Default | Effect when `true` |
|--------------------------------------|---------|--------------------|
| `track_schema` | `false` | `QueryService#infer_schema(records)` emits an **array-root** JSON-Schema snapshot (`{type:array, items:{type:object, properties:{…}}}`) and `SchemaDriftService#record_version!` appends a version row. The classification token (`initial`/`none`/`additive`/`breaking`) is written to the query row's `schema_drift` column and mirrored onto provenance. On a `breaking` classification it emits `Ai::Coordination::StigmergicSignalService#emit!(signal_type: "warning", signal_key: "data_source_schema_drift", …)` so autonomous agents perceive the drift, and adds a `schema_drift_breaking` anomaly. |
| `quality_checks_enabled` | `false` | `QualityService#evaluate(records)` runs the endpoint's `expectations.active`; `quality_score` / `quality_passed` are persisted on the query row and mirrored onto provenance. A failure adds `quality_failed` (+ per-rule `quality_<rule_type>`) anomalies. |
| `quarantine_on_failure` | `false` | Only meaningful alongside `quality_checks_enabled`. When a fetch **succeeds** but `quality_passed == false`, the bad batch is swapped for the last-known-good payload via `ResponseCacheService.read` (sets `quarantined: true` on the row + provenance, adds a `quarantined` anomaly), and the bad payload is **not** cached. Falls back to an empty batch when no prior good payload exists. |

The four columns this writes (`quality_score`, `quality_passed`, `quarantined`, `schema_drift`) are documented under [`ai_data_source_queries`](#ai_data_source_queries); the opt-in/SLA/contract columns are under [`ai_data_source_endpoints`](#ai_data_source_endpoints). All four observability **read** surfaces below are side-effect-free GETs that distill the latest recorded query row — they never trigger an outbound fetch.

### REST: Schema history

```
GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/schema_history
```

Requires `ai.data_sources.read`. Returns the endpoint's recorded schema-version history, **newest-first**, with a convenience pointer to the latest version. Versions are appended by `SchemaDriftService#record_version!` on tracked fetches (so an endpoint with `track_schema: false`, or one never fetched, returns `count: 0`). Response shape matches the frontend `DataSourceSchemaHistoryResponse`:

```json
{
  "success": true,
  "data": {
    "endpoint_id": "uuid",
    "count": 2,
    "versions": [
      {
        "id": "uuid",
        "ai_data_source_endpoint_id": "uuid",
        "version": 2,
        "schema": { "type": "array", "items": { "type": "object", "properties": { "time": { "type": "string" }, "temperature_2m": { "type": "number" }, "humidity": { "type": "integer" } } } },
        "checksum": "…",
        "classification": "additive",
        "diff": { "added_fields": ["[].humidity"], "removed_fields": [], "type_changes": [] },
        "created_at": "2026-06-06T00:00:00Z",
        "updated_at": "2026-06-06T00:00:00Z"
      },
      {
        "id": "uuid",
        "ai_data_source_endpoint_id": "uuid",
        "version": 1,
        "schema": { "type": "array", "items": { "type": "object", "properties": { "time": { "type": "string" }, "temperature_2m": { "type": "number" } } } },
        "checksum": "…",
        "classification": "initial",
        "diff": { "added_fields": [], "removed_fields": [], "type_changes": [] },
        "created_at": "2026-06-06T00:00:00Z",
        "updated_at": "2026-06-06T00:00:00Z"
      }
    ],
    "latest": { "version": 2, "classification": "additive", "…": "(== versions[0])" }
  }
}
```

`classification` is one of `initial` (first version) | `none` (structurally identical to the prior version) | `additive` (fields added, none removed/retyped — for the CONSUME direction any pure addition is backward-compatible, the JSON-Schema `required` array is not consulted) | `breaking` (a field was removed **or** changed type). `diff` carries `added_fields` / `removed_fields` (dotted property paths; array items are suffixed `[]`) and `type_changes` (`[{ field, from, to }]`). `record_version!` is idempotent: re-recording a byte-identical schema (same `checksum`) creates **no** new row and reports `classification: "none"` for that call.

### REST: Quality

```
GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/quality
```

Requires `ai.data_sources.read`. Returns the latest quality outcome distilled from the endpoint's most-recent query row, plus its configured `Ai::DataSourceExpectation` rules. Matches `DataSourceQualityResponse`:

```json
{
  "success": true,
  "data": {
    "endpoint_id": "uuid",
    "quality_checks_enabled": true,
    "quarantine_on_failure": false,
    "latest": {
      "quality_score": 0.92,
      "quality_passed": true,
      "quarantined": false,
      "schema_drift": "none",
      "evaluated_at": "2026-06-06T00:00:00Z",
      "results": [
        { "name": "rows_present", "rule_type": "min_records", "passed": true, "severity": "error", "detail": "24 >= 1" }
      ],
      "anomalies": []
    },
    "expectations": [
      {
        "id": "uuid",
        "ai_data_source_endpoint_id": "uuid",
        "name": "rows_present",
        "rule_type": "min_records",
        "config": { "min": 1 },
        "severity": "error",
        "is_active": true,
        "created_at": "2026-06-06T00:00:00Z",
        "updated_at": "2026-06-06T00:00:00Z"
      }
    ]
  }
}
```

`latest` is `null` when the endpoint has never run a quality-checked fetch. `latest.results` / `latest.anomalies` ride on the query row's `metadata` (keys `quality_results` / `results` and `anomalies`) — they default to `[]` when the inline quality stage did not record them. `rule_type` is one of `required_fields` | `min_records` | `max_records` | `non_null` | `allowed_values` | `distribution`; `severity` is `warn` | `error`. `quality_passed` is `false` **only** when an `error`-severity rule fails — `warn` failures lower `quality_score` (error rules are weighted ×2) but never fail the batch. When no expectations are configured, `QualityService` runs two built-in `warn`-severity defaults (a non-empty-batch check and a record-shape uniformity check) so a signal still exists.

> **Expectation CRUD** is **not** exposed by this surface in Phase 2b — `Ai::DataSourceExpectation` rows are created at the model/seed layer. This endpoint is read-only.

### REST: Contract verdict

```
GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/contract
```

Requires `ai.data_sources.read`. Returns the aggregate data-contract verdict from `Ai::DataSources::ContractService#validate`. **A GET must not trigger an outbound fetch**, so the verdict is built from a synthetic envelope assembled from the endpoint's latest recorded query row: `schema_valid` and `quality_passed` come straight off the row's columns, and freshness is the row's age (`cache_age_seconds` = seconds since it was recorded) measured against `endpoint.sla_max_age_seconds`. With no prior query the verdict is vacuously met (all signals `null`). Matches `DataSourceContractVerdict`:

```json
{
  "success": true,
  "data": {
    "met": true,
    "schema_valid": true,
    "quality_passed": true,
    "within_sla": true,
    "violations": []
  }
}
```

Each of the three signals is `true`/`false`, or `null` when **not asserted** — `schema_valid` is `null` when the endpoint has no `response_schema`; `quality_passed` is `null` when quality was never evaluated and a fresh run is not possible; `within_sla` is `true` when no `sla_max_age_seconds` is set (an unset SLA cannot be exceeded) and `null` when an SLA is set but the cache age is unknown. `met` = every **asserted** signal holds (a `null` signal is treated as "not asserted" and never counts as a violation, so a contract with no assertions is vacuously met). `violations` lists the asserted-`false` signals as `schema_invalid` / `quality_failed` / `sla_exceeded`. (The MCP `data_source_contract` action differs — it runs a **live** governed fetch first; see below.)

### REST: Introspect (OpenAPI import)

```
POST /api/v1/ai/data_sources/:data_source_id/introspect
```

Requires `ai.data_sources.manage` (it creates endpoints — **even `dry_run` is gated by manage** as a write surface). Imports an OpenAPI 3 document into `Ai::DataSourceEndpoint` rows via `Ai::DataSources::OpenApiImportService#import`. The document is supplied **either** inline as a parsed `spec` Hash **or** as a `spec_url` / `url` that the server fetches through the SSRF-guarded `Ai::DataSources::HttpConnectionFactory` (resolve-and-pin on every hop) and parses as JSON.

Request body:

```json
{ "spec": { "openapi": "3.0.0", "paths": { "/v1/forecast": { "get": { "operationId": "getForecast", "responses": { "200": { "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Forecast" } } } } } } } }, "components": { "schemas": { "Forecast": { "type": "object", "properties": { "time": { "type": "string" } } } } } }, "dry_run": true }
```

| Field | Required | Default | Notes |
|-------|----------|---------|-------|
| `spec` | one of `spec`/`spec_url` | — | Parsed OpenAPI 3 document (Hash). Takes precedence over `spec_url`/`url` |
| `spec_url` (or `url`) | one of `spec`/`spec_url` | — | Remote spec URL fetched through the SSRF-guarded factory and JSON-parsed. `422` `"spec or url is required"` when neither is present |
| `dry_run` | no | `false` | Preview the endpoints without persisting |

Each `paths` × `{get,post,put,patch,delete,head}` operation maps to an endpoint: `name` = `operationId` ‖ `summary` ‖ `"METHOD path"`; `slug` from `operationId`/name; `http_method` = the verb; `path_template` = the path; `response_format = "json"`; `response_schema` = the 2xx (then `default`) JSON content schema with `$ref` chains resolved recursively against `#/components` (cycle-guarded). Persisted import **skips duplicate slugs** (both pre-existing on the source and collisions earlier in the same batch) rather than erroring; per-path failures are collected in `errors`. Response matches `DataSourceOpenApiImportResult` (with `dry_run` echoed back):

```json
{
  "success": true,
  "data": {
    "created": [],
    "preview": [
      {
        "name": "getForecast",
        "slug": "get_forecast",
        "http_method": "GET",
        "path_template": "/v1/forecast",
        "response_format": "json",
        "response_schema": { "type": "object", "properties": { "time": { "type": "string" } } },
        "metadata": { "operation_id": "getForecast", "imported_from": "openapi", "source_path": "/v1/forecast", "source_method": "GET" }
      }
    ],
    "errors": [],
    "dry_run": true
  }
}
```

On `dry_run: true`, `created` is `[]` and `preview` holds the would-be endpoints. On a persisted import, `created` holds the compact serialization of the saved endpoints (`id`, `name`, `slug`, `http_method`, `path_template`, `response_format`) and `preview` still holds the full attribute set. Emits the `ai.data_sources.introspect` audit event (`dry_run`, `created_count`).

### MCP: quality + drift + contract + introspection actions

`Ai::Tools::DataSourceTool` now carries **16 actions** — the Phase-1/2a twelve plus the four below, registered per-action in `PlatformApiToolRegistry`. The three read actions are added to `READ_ACTIONS` (gated `ai.data_sources.read`, no proposal fallback); `data_source_introspect` is the `INTROSPECT_ACTION`, gated `ai.data_sources.manage`. Full parity details are in [MCP: `data_source_*` actions](#mcp-data_source_-actions).

| Action | Purpose | Params | Required permission |
|--------|---------|--------|---------------------|
| `data_source_schema_history` | Endpoint schema-version history (ordered) + the latest version's `diff` | `data_source_id`, `endpoint_id` | `ai.data_sources.read` |
| `data_source_quality` | Endpoint's latest quality outcome (from its most recent query row) + configured expectations | `data_source_id`, `endpoint_id` | `ai.data_sources.read` |
| `data_source_contract` | **Live** governed fetch, then aggregate `schema_valid` + `quality_passed` + `within_sla` into a contract verdict | `data_source_id`, `endpoint_id`, `params?` | `ai.data_sources.read` |
| `data_source_introspect` | Import an OpenAPI 3 `spec` into endpoints (`OpenApiImportService`); supports `dry_run` | `data_source_id`, `spec` (required), `dry_run?` | `ai.data_sources.manage` |

`data_source_id` / `endpoint_id` accept a UUID **or** a slug. Return shapes (all wrapped in the tool's `success_result`):

- **`data_source_schema_history`** → `{ data_source:{id,slug,name}, endpoint:{id,slug,name,track_schema}, versions:[{version,classification,checksum,created_at}], count, latest_diff }`. (Compact per-version summary; the REST route returns the full schema snapshot per version.)
- **`data_source_quality`** → `{ data_source, endpoint:{id,slug,name,quality_checks_enabled,quarantine_on_failure}, latest_quality:{query_id,quality_score,quality_passed,quarantined,schema_drift,fetched_at}|null, expectations:[{id,name,rule_type,severity,is_active,config}], expectation_count }`.
- **`data_source_introspect`** → `{ data_source, dry_run, created, created_count, preview, preview_count, errors }`. Accepts only an inline `spec` Hash (no `spec_url` — that is REST-only); raises `ArgumentError "spec is required"` when blank.
- **`data_source_contract`** → `{ data_source, endpoint:{id,slug,name,sla_max_age_seconds,owner}, contract:{met,schema_valid,quality_passed,within_sla,violations}, fetch_status, fetch_success }`. **Unlike the REST `contract` GET**, this runs a real `QueryService` fetch first (consuming quota/egress) and validates the contract against the **live** envelope.

## Phase 3 additions

Phase 3 layers **streaming / monitoring** onto the governed fetch. A **subscription** (`Ai::DataSourceSubscription`, table `ai_data_source_subscriptions`) pairs a `(data_source, endpoint)` with a poll cadence and the last observed change fingerprint (`last_checksum` / `last_etag`). The server-side `Ai::DataSources::MonitorService` walks due subscriptions, runs the **same governed `QueryService` pipeline** as an interactive query, change-detects against the stored fingerprint, and **on change** warms only that param-variant's cache entry + emits a `data_source_changed` stigmergic signal so autonomous agents perceive the update. The standalone worker fires only two thin mTLS cron ticks; it never polls or fetches itself. Phase 3 also activates the **stale-while-revalidate / stale-if-error** cache policies behind two opt-in endpoint columns. **Nothing in the Phase-1/2a/2b contract changed** — the `FetchEnvelope` is byte-for-byte identical until an endpoint opts into a stale window, and the existing `served_stage` enum already carried the `stale_if_error` value.

### Subscriptions + the monitor loop

`Ai::DataSourceSubscription` (`server/app/models/ai/data_source_subscription.rb`):

- `belongs_to :data_source` (`ai_data_source_id`) / `:endpoint` (`ai_data_source_endpoint_id`); `belongs_to :agent` (`ai_agent_id`, **optional** — cadence ownership without coupling to agent lifecycle). `Ai::DataSource has_many :subscriptions` and `Ai::DataSourceEndpoint has_many :subscriptions`, both `dependent: :destroy`.
- `POLL_FREQUENCIES = %w[manual 5min hourly daily weekly monthly realtime]` — reuses `Ai::DataConnector`'s cadence set plus two monitor-grade fine tiers (`5min`, `realtime`). `poll_interval` returns an `ActiveSupport::Duration` (`realtime` → `0.seconds`, polled on **every** tick; unknown/blank → `1.hour`).
- `STATUSES = %w[active paused error]`.
- `params` / `metadata` are jsonb with lambda defaults. A `before_create` seeds `next_poll_at = Time.current` for any non-`manual` cadence so the monitor picks the subscription up without an explicit `activate!`.

**Scopes** (drive the monitor):

| Scope | Definition | Notes |
|-------|------------|-------|
| `active` | `status: "active"` | |
| `due_for_poll` | `status IN (active, error) AND next_poll_at IS NOT NULL AND next_poll_at <= now` | **Includes `error`** so a failing subscription keeps retrying and can self-heal (the only path that clears `error → active` is a successful `record_poll!`). **Excludes operator-set `paused`.** |
| `for_data_source(ds)` / `for_endpoint(ep)` | scope by source / endpoint | accepts a record or an id |

**Lifecycle methods**:

- `activate!` → sets `status: "active"` and schedules the next poll. `pause!` → `status: "paused"`, `next_poll_at: nil` (drops out of `due_for_poll`). `active?`.
- `record_poll!(changed:, checksum: nil, etag: nil)` — sets `last_polled_at`, **resets `consecutive_failures` to 0**, clears a prior `error` status back to `active`, updates `last_checksum` / `last_etag` only when supplied, then schedules the next poll. Returns the `changed` flag.
- `record_failure!(error_message = nil)` — increments `consecutive_failures`, flips `status` to `"error"` once failures **`>= 5`** (only from `active`), records `last_error` / `last_error_at` in `metadata`, and still schedules the next attempt (unless `paused`) so a transient fault self-heals.
- `schedule_next_poll!` — `next_poll_at = now + poll_interval`; a no-op for `manual` (and immediate for `realtime`, interval 0). `needs_poll?` → `active? && next_poll_at present && <= now`.

`Ai::DataSources::MonitorService.new(account = nil)` (`server/app/services/ai/data_sources/monitor_service.rb`):

- **`#tick(limit: 100)` → `{ polled:, changed:, errors: [{ subscription_id:, error: }] }`.** Walks `DataSourceSubscription.due_for_poll` (eager-loading source/endpoint/agent, account-scoped when an account was supplied). For each subscription it first respects the parent source's `check_quota!` — a throttled source **reschedules without counting a failure** rather than burning budget on background monitoring. It then runs the governed `QueryService` fetch, passing the stored `last_etag` as a conditional hint via the reserved `__conditional_etag` param (adapters that support it translate to `If-None-Match`; others ignore it).
- **Change detection** compares a canonical `Digest::SHA256` of the deep-sorted payload (preferring the provenance `response_sha256` when present) against `last_checksum`; when both sides expose an etag and they match, the result is unchanged regardless of checksum (handles 304-style revalidation). The first successful poll (blank `last_checksum`) always registers as changed.
- **On change**: warms **only that param-variant's** `ResponseCacheService.write` entry (an idempotent `setex` — it does **not** blanket-invalidate the endpoint, which would cold-miss sibling subscriptions / interactive reads cached under different params; the `__conditional_etag` hint is stripped from the cache-key params), then emits `Ai::Coordination::StigmergicSignalService.new(account: source.account || account).emit!(signal_type: "discovery", signal_key: "data_source_changed", agent: nil, strength: 1.0, payload: { slug, data_source_id, endpoint, endpoint_id, subscription_id, checksum })`. The signal is **system-emitted** (no agent attribution, consistent with the QueryService schema-drift signal) and skipped when the source has no resolvable account.
- Outcomes are recorded via `record_poll!` (changed true/false) or `record_failure!` on a failed/erroring envelope. **Per-subscription failures are collected and never abort the batch.**
- **`#health_tick` → `{ refreshed:, errors: [] }`** — calls `update_health_status!` on every active source in scope (used by the health cron tick).
- **`#refresh!(data_source:, endpoint:, params: {})` → Boolean** — the background SWR refresh entry point (see below): runs the governed fetch and re-warms the cache on success; best-effort (any failure is logged, never raised).

### Stale-while-revalidate / stale-if-error

Two nullable integer columns added to `ai_data_source_endpoints` (migration `20260606121000`) gate the stale-serving policies. **Both default `nil` = OFF** — when both are nil the cache behaves byte-for-byte as before and the `FetchEnvelope` is unchanged.

| Column | Policy |
|--------|--------|
| `stale_while_revalidate_seconds` | After the hard TTL, `ResponseCacheService.fetch` may serve a hard-expired entry **within this window** (flagged) and kick off a background refresh. |
| `stale_if_error_seconds` | On a transient upstream failure, `QueryService` may serve the last-known-good cached payload **within this window** instead of failing. |

`ResponseCacheService` (`server/app/services/ai/data_sources/response_cache_service.rb`):

- **`write` / `fetch` extend the Redis key TTL** by `grace_window = max(stale_while_revalidate_seconds, stale_if_error_seconds)` while keeping the **hard-expiry epoch** unchanged — so either policy can still find the entry past its freshness boundary. With both windows nil the grace is 0 and the Redis TTL equals the hard TTL (legacy behaviour).
- **`fetch`** serves a **hard-expired** entry within the SWR window (`hard_expired: true` but still inside grace), counts it as a hit, and calls `schedule_background_refresh` — an **NX-locked, detached `Thread`** (one refresher per key per grace window) wrapped in `ActiveRecord::Base.connection_pool.with_connection` so the refetch's DB work doesn't leak the pool, delegating the real refresh to `MonitorService#refresh!`.
- **`read_stale(data_source:, endpoint:, params:)` → `{ payload:, stale:, hard_expired:, age_seconds:, stale_age_seconds: }` | nil** — a side-channel read used only by the stale policies; it does **not** count toward hit/miss metrics. `stale_age_seconds` is seconds elapsed **past** the hard expiry (0 while fresh), per HTTP `Cache-Control` `stale-*` semantics (the window is measured from when the entry went stale, not when it was written).

`QueryService` stale-if-error (`maybe_serve_stale_if_error`): on a `STATUS_ERROR` / `STATUS_TIMEOUT` failure (policy rejections `blocked` / `rate_limited` are **deliberately excluded** — those are decisions, not upstream outages), and only when `stale_if_error_seconds` is set and a hard-expired entry exists within the window, it swaps the failure for the cached payload via `read_stale`. The substituted result is flagged `success: true`, `status: cached`, `served_stage: "stale_if_error"`, with `provenance.stale_if_error: true` (and `served_on_error` recording the original failure status) so persistence/provenance record an honest degraded serve. It never re-writes the cache (`finalize` gates `write_cache` on a fresh success). The `served_stage` enum on `ai_data_source_queries` therefore takes one of `fresh / cache / stale_while_revalidate / stale_if_error`.

### REST: Subscriptions

Subscriptions nest under a source (mixed in via the `Ai::DataSourceEndpoints` concern). Routes (`config/routes.rb`):

```
GET    /api/v1/ai/data_sources/:data_source_id/subscriptions
POST   /api/v1/ai/data_sources/:data_source_id/subscriptions
DELETE /api/v1/ai/data_sources/:data_source_id/subscriptions/:subscription_id
```

The shared subscription summary (`serialize_subscription`, kept in lockstep with the MCP `subscription_summary` and the frontend `AiDataSourceSubscription` type):

```json
{
  "id": "uuid",
  "data_source_id": "uuid",
  "endpoint_id": "uuid",
  "poll_frequency": "hourly",
  "status": "active",
  "params": {},
  "next_poll_at": "2026-06-06T01:00:00Z",
  "last_polled_at": "2026-06-06T00:00:00Z",
  "last_checksum": "…",
  "last_etag": "\"abc123\"",
  "consecutive_failures": 0,
  "agent_id": null
}
```

**List** — `GET .../subscriptions` (`subscriptions_index`, `ai.data_sources.read`): returns `{ "items": [<summary>, …], "count": N }` (newest-first; eager-loads `:endpoint`).

**Create / update** — `POST .../subscriptions` (`subscriptions_create`, `ai.data_sources.stream`). **Idempotent** on the source+endpoint pair via `find_or_initialize_by(ai_data_source_endpoint_id:)` — a second POST for the same endpoint updates the existing cadence/params instead of duplicating. Body is keyed under `subscription`:

```json
{ "subscription": { "endpoint_id": "uuid-or-slug", "poll_frequency": "hourly", "params": { "lat": 40.71 } } }
```

| Field | Required | Default | Notes |
|-------|----------|---------|-------|
| `endpoint_id` | yes | — | Resolved within the source's `endpoints`; `404 "Endpoint not found"` otherwise |
| `poll_frequency` | no | `hourly` | Must be in `POLL_FREQUENCIES`; `422` with the allowed list otherwise |
| `params` | no | `{}` | Free-form per-poll variables (permit-all; redacted by `QueryService` on each poll) |

A new record (or a changed `poll_frequency`) re-arms the cadence (`next_poll_at = nil`, then `schedule_next_poll!`). Response: `201` (new) / `200` (updated) with `{ "subscription": <summary> }`, or `422` `render_validation_error`. Emits `ai.data_sources.subscription.create`.

**Cancel** — `DELETE .../subscriptions/:subscription_id` (`subscriptions_destroy`, `ai.data_sources.stream`): `{ "message": "Subscription cancelled successfully" }`, or `404` when the subscription is not under this source. Emits `ai.data_sources.subscription.delete`.

### Internal: worker monitor / health ticks

Worker-only, mTLS (no JWT). `Api::V1::Internal::DataSourcesController` inherits `InternalBaseController` (skip JWT, `authenticate_worker_via_mtls!`). Both delegate straight to `MonitorService` and return its summary in the standard envelope.

```
POST /api/v1/internal/ai/data_sources/monitor_tick
POST /api/v1/internal/ai/data_sources/health_tick
```

- **`monitor_tick`** — optional `limit` body param (clamped `1..1000`, default `100`); calls `MonitorService.new.tick(limit:)` across all accounts → `{ polled, changed, errors }`.
- **`health_tick`** — calls `MonitorService.new.health_tick` → `{ refreshed, errors }`.

On any raised error both return a `render_error` (not a 500). The worker side is two **thin** cron triggers that only POST these paths and log the batch summary:

| Worker job | Cron (`worker/config/sidekiq.yml`) | Posts |
|-----------|-------------------------------------|-------|
| `worker/app/jobs/ai_data_source_monitor_job.rb` | `*/5 * * * *` | `POST /api/v1/internal/ai/data_sources/monitor_tick` |
| `worker/app/jobs/ai_data_source_health_job.rb` | `*/10 * * * *` | `POST /api/v1/internal/ai/data_sources/health_tick` |

### MCP: subscription actions

`Ai::Tools::DataSourceTool` now carries **18 actions** — the Phase-1/2a/2b sixteen plus the two below. Both are in `STREAM_ACTIONS`, gated by `ai.data_sources.stream` (`STREAM_PERMISSION`); like the read/query actions they have **no** proposal fallback (an unauthorized call returns a permission-denied result). `data_source_id` / `endpoint_id` accept a UUID **or** a slug, resolved within the acting account.

| Action | Purpose | Params | Required permission |
|--------|---------|--------|---------------------|
| `data_source_subscribe` | Create/update a pull-based subscription (idempotent `find_or_initialize` on the endpoint) | `data_source_id`, `endpoint_id`, `params?`, `poll_frequency?` (default `hourly`) | `ai.data_sources.stream` |
| `data_source_unsubscribe` | Remove a subscription | `subscription_id` **OR** `data_source_id` + `endpoint_id` | `ai.data_sources.stream` |

- **`data_source_subscribe`** validates `poll_frequency` against `POLL_FREQUENCIES`, sets the acting `agent` when present, re-arms the cadence on a new/changed-frequency record, and returns `{ subscription: <summary>, message: "Subscription created"|"Subscription updated" }`. (The MCP `subscription_summary` omits `last_etag`; the REST `serialize_subscription` includes it.)
- **`data_source_unsubscribe`** deletes by `subscription_id` (account-scoped via a join through the parent source) → `{ message, subscription_id }`; or, given `data_source_id + endpoint_id`, `destroy_all` matching subscriptions → `{ message, removed_count, data_source_id, endpoint_id }`. Raises `ArgumentError` when neither selector is supplied.

## REST: Endpoints (nested)

Endpoints nest under a source. They are declarative request templates + response contracts (see [`../../concepts/data-sources.md`](../../concepts/data-sources.md#catalog--endpoints)). Routes (`config/routes.rb`):

```
GET    /api/v1/ai/data_sources/:data_source_id/endpoints
POST   /api/v1/ai/data_sources/:data_source_id/endpoints
PATCH  /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
PUT    /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
DELETE /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
POST   /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/query
```

The source is resolved from `:data_source_id`; the endpoint from `:endpoint_id` within that source's `endpoints` scope (`404` `"Endpoint not found"` otherwise).

The serialized endpoint shape (`serialize_data_source_endpoint`):

```json
{
  "id": "uuid",
  "ai_data_source_id": "uuid",
  "name": "Hourly forecast",
  "slug": "hourly_forecast",
  "http_method": "GET",
  "path_template": "/v1/forecast",
  "response_format": "json",
  "expected_content_type": "application/json",
  "cache_ttl_seconds": 300,
  "monitorable": false,
  "change_detection": null,
  "query_template": { "latitude": "{lat}", "longitude": "{lon}", "hourly": "temperature_2m" },
  "body_template": {},
  "response_mapping": { "records_path": "hourly" },
  "response_schema": {},
  "metadata": {},
  "created_at": "2026-06-06T00:00:00Z",
  "updated_at": "2026-06-06T00:00:00Z"
}
```

### List endpoints

```
GET /api/v1/ai/data_sources/:data_source_id/endpoints
```

Response (`200`): `{ "items": [ <endpoint>, ... ], "count": N }` (ordered by `name`).

### Create an endpoint

```
POST /api/v1/ai/data_sources/:data_source_id/endpoints
```

Body — keyed under `endpoint`, permitted by `endpoint_params`:

```json
{
  "endpoint": {
    "name": "Hourly forecast",
    "slug": "hourly_forecast",
    "http_method": "GET",
    "path_template": "/v1/forecast",
    "response_format": "json",
    "expected_content_type": "application/json",
    "cache_ttl_seconds": 300,
    "monitorable": false,
    "change_detection": null,
    "query_template": { "latitude": "{lat}", "longitude": "{lon}" },
    "body_template": {},
    "response_mapping": { "records_path": "hourly" },
    "response_schema": {},
    "metadata": {}
  }
}
```

Permitted keys: `name`, `slug`, `http_method`, `path_template`, `response_format`, `expected_content_type`, `cache_ttl_seconds`, `monitorable`, `change_detection`, and the JSON fields `query_template`, `body_template`, `response_mapping`, `response_schema`, `metadata`. Validation (model `Ai::DataSourceEndpoint`): `name` required; `slug` lowercase `[a-z0-9_-]+`, unique per source, auto-generated from `name` when omitted; `http_method` in `GET/POST/PUT/PATCH/DELETE/HEAD`; `response_format` in `json/xml/csv/ndjson/rss/atom/html/text/binary` (nil allowed); `change_detection` in `etag/last_modified/content_hash/polling/none` (nil allowed); `cache_ttl_seconds` >= 0.

Response: `201` with `{ "endpoint": <endpoint> }`, or `422` `render_validation_error`. Emits the `ai.data_sources.endpoint.create` audit event.

### Update an endpoint

```
PATCH /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
PUT   /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
```

Same body shape and permitted keys as create. Response: `200` with `{ "endpoint": <endpoint> }`, or `422`. Emits the `ai.data_sources.endpoint.update` audit event.

### Delete an endpoint

```
DELETE /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
```

Response (`200`): `{ "message": "Endpoint deleted successfully" }`. Emits the `ai.data_sources.endpoint.delete` audit event.

## REST: Query (governed fetch)

```
POST /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/query
```

Requires `ai.data_sources.query`. Runs the full governed pipeline (kill flag → quota → cache → credential/Vault → circuit-breaker-wrapped sign + SSRF-guarded send → decode → schema-validate → normalize → redact → hash-chained audit row → cost attribution → cache write) via `Ai::DataSources::EndpointQueryRunner` → `Ai::DataSources::QueryService`, with the request's `current_user` as context. See the [pipeline detail](../../concepts/data-sources.md#the-queryservice-pipeline).

Request body — caller params for the endpoint's `{placeholder}` variables, accepted under **either** `params` **or** `query_params` as a free-form (permit-all) hash, because variables are source-specific. Everything is redacted before persistence:

```json
{ "params": { "lat": 40.71, "lon": -74.0 } }
```

Response — the `QueryService` `FetchEnvelope`, identical for REST and MCP:

```json
{
  "success": true,
  "data": {
    "success": true,
    "data": [ { "time": "2026-06-06T00:00:00Z", "temperature_2m": 18.4 } ],
    "provenance": {
      "slug": "open-meteo",
      "endpoint_id": "uuid",
      "fetched_at": "2026-06-06T00:00:00Z",
      "from_cache": false,
      "cache_age_seconds": 0,
      "response_sha256": "…",
      "source_url": "[REDACTED]",
      "declared_vs_detected_content_type": {
        "declared": "application/json",
        "detected": "json",
        "content_type": "application/json",
        "mismatch": false
      },
      "charset": "utf-8",
      "applied_encoding": "utf-8",
      "schema_valid": null,
      "record_count": 1,
      "anomalies": []
    },
    "status": "success",
    "duration_ms": 142,
    "bytes": 384,
    "error": null
  }
}
```

`status` is one of `success | error | timeout | rate_limited | blocked | cached`. `schema_valid` is `true`/`false`, or `null` when the endpoint has no `response_schema`. `source_url` is always redacted; `anomalies` lists issues like `content_type_mismatch`, `schema_invalid`, `http_4xx`, `decode_error`.

On a failed envelope (`success: false`), the controller renders `render_error` with the redacted `error`, the `provenance` and `status` under `details`, and an HTTP status mapped from the envelope `status`:

| Envelope `status` | HTTP status |
|-------------------|-------------|
| `rate_limited` | `429 Too Many Requests` |
| `blocked` | `403 Forbidden` |
| `timeout` | `504 Gateway Timeout` |
| anything else | `502 Bad Gateway` |

```json
{
  "success": false,
  "error": "rate limit exceeded",
  "details": { "provenance": { }, "status": "rate_limited" }
}
```

## MCP: `data_source_*` actions

`Ai::Tools::DataSourceTool` exposes the surface to agents as the `data_source_management` tool, now with **18 actions** (Phase-1 nine + Phase 2a three + Phase 2b four + Phase 3 two). The class-level `REQUIRED_PERMISSION` (`ai.data_sources.read`) gates visibility; finer per-action authorization happens inside `#call`. `data_source_id` / `endpoint_id` accept **either a UUID or a slug** (resolved within the acting account).

**Proposal fallback:** when the acting agent's account lacks the required mutation grant, the `create`/`update`/`delete` actions do **not** mutate. They file an `Ai::AgentProposal` (via `Ai::ProposalService`, `proposal_type: "configuration"`) describing the intended change and return `{ success: true, requires_approval: true, proposal_id, status, proposed_changes, message }` for a human to review. (If there is no agent/account context, or the proposal can't be filed, the action returns a permission-denied / error result instead.) Read and `query` actions have **no** fallback — they return a permission-denied result when unauthorized. `ai.data_sources.manage` satisfies any mutation.

| Action | Purpose | Params | Required permission | Proposal fallback |
|--------|---------|--------|---------------------|-------------------|
| `data_source_list` | List sources with health + credential counts | `source_type?`, `is_active?` | `ai.data_sources.read` | n/a (denied) |
| `data_source_get` | One source: config, rate limits, credentials, quota | `data_source_id` | `ai.data_sources.read` | n/a (denied) |
| `data_source_describe` | A source's endpoints (method, path, format, schemas) | `data_source_id`, `endpoint_id?` | `ai.data_sources.read` | n/a (denied) |
| `data_source_query` | Governed external fetch — returns a `FetchEnvelope` | `data_source_id`, `endpoint_id`, `params?` | `ai.data_sources.query` | n/a (denied) |
| `data_source_health` | Quota summary + cache metrics + circuit-breaker state + trust signals | `data_source_id` | `ai.data_sources.read` | n/a (denied) |
| `data_source_validate_config` | Check SSRF-safe base URL, known auth scheme, supported protocol/formats | `data_source_id` | `ai.data_sources.read` | n/a (denied) |
| `data_source_discover` *(2a)* | Semantic discovery — ranked sources for a natural-language need | `query`, `limit?`, `rerank?` | `ai.data_sources.read` | n/a (denied) |
| `data_source_provenance` *(2a)* | Provenance of one recorded fetch (already-redacted audit-log columns) | `query_id?`, `correlation_id?`, `data_source_id?`, `endpoint_id?` | `ai.data_sources.read` | n/a (denied) |
| `data_source_impact` *(2a)* | Usage + trust summary for a source | `data_source_id` | `ai.data_sources.read` | n/a (denied) |
| `data_source_schema_history` *(2b)* | Endpoint schema-version history + latest `diff` | `data_source_id`, `endpoint_id` | `ai.data_sources.read` | n/a (denied) |
| `data_source_quality` *(2b)* | Endpoint's latest quality outcome + configured expectations | `data_source_id`, `endpoint_id` | `ai.data_sources.read` | n/a (denied) |
| `data_source_contract` *(2b)* | **Live** fetch + aggregate contract verdict | `data_source_id`, `endpoint_id`, `params?` | `ai.data_sources.read` | n/a (denied) |
| `data_source_introspect` *(2b)* | OpenAPI 3 import → endpoints (`dry_run?`) | `data_source_id`, `spec`, `dry_run?` | `ai.data_sources.manage` | n/a (denied) |
| `data_source_subscribe` *(3)* | Create/update a pull-based subscription (idempotent on the endpoint) | `data_source_id`, `endpoint_id`, `params?`, `poll_frequency?` | `ai.data_sources.stream` | n/a (denied) |
| `data_source_unsubscribe` *(3)* | Remove a subscription | `subscription_id` **OR** `data_source_id` + `endpoint_id` | `ai.data_sources.stream` | n/a (denied) |
| `data_source_create` | Create a source | `name`, `source_type`, `api_base_url?`, `slug?`, `description?`, `is_active?`, `requires_auth?`, `priority_order?`, `configuration?`, `rate_limits?` | `ai.data_sources.create` (or `.manage`) | **Yes** — files a proposal |
| `data_source_update` | Update a source | `data_source_id`, `name?`, `source_type?`, `api_base_url?`, `description?`, `is_active?`, `requires_auth?`, `priority_order?`, `configuration?`, `rate_limits?` | `ai.data_sources.update` (or `.manage`) | **Yes** — files a proposal |
| `data_source_delete` | Delete a source | `data_source_id` | `ai.data_sources.delete` (or `.manage`) | **Yes** — files a proposal |

`data_source_query` returns the `FetchEnvelope` verbatim (same shape as the REST query response `data`). `data_source_health` returns `{ data_source, effectiveness_score, trust_signals, quota_summary, cache_metrics, circuit_breaker }` where `cache_metrics` is `ResponseCacheService.metrics` (`{ hits, misses, total, hit_rate }`) and `circuit_breaker` is the per-source breaker state (`service_name: "data_source:<id>"`). `data_source_validate_config` returns `{ data_source, valid, errors, warnings }`. `data_source_describe` now also includes `effectiveness_score` + a `trust_signals` block per source. The three Phase 2a actions (`data_source_discover`, `data_source_provenance`, `data_source_impact`) are detailed in [MCP: discovery + evaluation actions](#mcp-discovery--evaluation-actions); the four Phase 2b actions (`data_source_schema_history`, `data_source_quality`, `data_source_contract`, `data_source_introspect`) in [MCP: quality + drift + contract + introspection actions](#mcp-quality--drift--contract--introspection-actions); the two Phase 3 actions (`data_source_subscribe`, `data_source_unsubscribe`) in [MCP: subscription actions](#mcp-subscription-actions). The MCP tool does **not** expose endpoint CRUD or expectation CRUD — endpoints are managed over REST (or minted via `data_source_introspect`), and expectations at the model layer.

## Schema reference

UUIDv7 primary keys; `t.references` semantics per the platform's [data-model](../../concepts/data-model.md) conventions. The parent catalog table `ai_data_sources` and the credential table `ai_data_source_credentials` are documented in [`reference/database-schema.md`](../database-schema.md); the five tables introduced/extended for the endpoint + audit + observability + streaming layers are detailed below.

> **Phase 2a** added scoring columns to `ai_data_sources`: `effectiveness_score` (default `0.5`), `usage_count` / `positive_usage_count` / `negative_usage_count` (default `0`), and `last_used_at`. It also added the nullable `ai_data_source_id` (uuid, partial index) FK column to `ai_knowledge_graph_nodes` so a `data_source`-typed node links back to its source. Full column reference: [`reference/database-schema.md`](../database-schema.md).

> **Phase 2b** added two tables — `ai_data_source_schema_versions` and `ai_data_source_expectations` (migration `20260606120500`) — plus quality columns on `ai_data_source_queries` (`20260606120600`) and opt-in/SLA/contract columns on `ai_data_source_endpoints` (`20260606120700`). All detailed below.

> **Phase 3** added the `ai_data_source_subscriptions` table plus the two stale-window columns (`stale_while_revalidate_seconds`, `stale_if_error_seconds`) on `ai_data_source_endpoints` — both in migration `20260606121000`. Detailed below.

### `ai_data_source_endpoints`

Declarative request template + response contract for one operation against a source. Model: `Ai::DataSourceEndpoint`. Unique index on `(ai_data_source_id, slug)`.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | uuid | no | `gen_random_uuid()` | PK |
| `ai_data_source_id` | uuid | no | — | FK → `ai_data_sources` |
| `name` | string(255) | no | — | Human label |
| `slug` | string(100) | no | — | `[a-z0-9_-]+`, unique per source; auto-generated from `name` |
| `http_method` | string(10) | no | `GET` | One of `GET/POST/PUT/PATCH/DELETE/HEAD` |
| `path_template` | string(1000) | yes | — | Path with `{placeholder}` segments (path-escaped at build) |
| `query_template` | jsonb | no | `{}` | Query-param template Hash |
| `body_template` | jsonb | no | `{}` | Body template (sent for POST/PUT/PATCH) |
| `response_format` | string(50) | yes | — | Decoder hint (`json/xml/csv/ndjson/rss/atom/html/text/binary`) |
| `expected_content_type` | string(255) | yes | — | Used by `FormatDetector` cross-check |
| `response_mapping` | jsonb | no | `{}` | Where records live + normalization rules (`records_path`, etc.) |
| `response_schema` | jsonb | no | `{}` | Optional JSON Schema for validation |
| `cache_ttl_seconds` | integer | yes | — | Per-endpoint cache TTL (>= 0); fallback 5 min |
| `monitorable` | boolean | no | `false` | Monitoring hint flag (subscriptions drive the actual Phase-3 monitor loop) |
| `change_detection` | string(50) | yes | — | Change-detection strategy hint: `etag/last_modified/content_hash/polling/none` |
| `etag` | string(500) | yes | — | Change-detection state |
| `last_modified` | string(255) | yes | — | Change-detection state |
| `track_schema` | boolean | no | `false` | **(2b)** Opt in to schema-drift version tracking on each fetch |
| `quality_checks_enabled` | boolean | no | `false` | **(2b)** Opt in to running active expectations over each fetch |
| `quarantine_on_failure` | boolean | no | `false` | **(2b)** Serve last-known-good instead of a batch that fails an error-severity rule |
| `sla_max_age_seconds` | integer | yes | — | **(2b)** Freshness budget for the contract `within_sla` signal (nil = no SLA) |
| `owner` | string(255) | yes | — | **(2b)** Free-form endpoint owner label (surfaced in the contract MCP action) |
| `contract` | jsonb | yes | `{}` | **(2b)** Free-form contract metadata |
| `stale_while_revalidate_seconds` | integer | yes | — | **(3)** SWR grace window; serve a hard-expired entry while refreshing in the background (nil = OFF) |
| `stale_if_error_seconds` | integer | yes | — | **(3)** Stale-if-error window; serve last-known-good on a transient upstream failure (nil = OFF) |
| `metadata` | jsonb | no | `{}` | Free-form |
| `created_at` / `updated_at` | datetime | no | — | Timestamps |

The six Phase 2b columns are added by `20260606120700_add_quality_opt_in_to_ai_data_source_endpoints`. The two Phase 3 stale-window columns are added by `20260606121000_create_ai_data_source_subscriptions` (alongside the subscriptions table). The endpoint serializer (`serialize_data_source_endpoint`) does **not** echo any of them — the 2b columns are read through the dedicated `schema_history` / `quality` / `contract` routes and the stale-window columns are consumed internally by `ResponseCacheService` / `QueryService`. `has_many :schema_versions` / `has_many :expectations` / `has_many :subscriptions` (all `dependent: :destroy`) link the three new tables.

### `ai_data_source_queries`

The query/audit log: one row per governed fetch (including cache hits and blocked/rate-limited attempts). Every operator-visible field is redacted before write, and the row is hash-chained into the audit log (the chain anchor — `integrity_hash` / `previous_hash` / `sequence_number` — is mirrored into `metadata["audit_chain"]`). Model: `Ai::DataSourceQuery`. Index on `(ai_data_source_id, created_at)`.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | uuid | no | `gen_random_uuid()` | PK |
| `ai_data_source_id` | uuid | no | — | FK → `ai_data_sources` |
| `ai_data_source_endpoint_id` | uuid | yes | — | FK → `ai_data_source_endpoints` (nullified on endpoint delete) |
| `account_id` | uuid | yes | — | Owning account |
| `requesting_agent_id` | uuid | yes | — | Agent that initiated the fetch (if any) |
| `status` | string(50) | yes | — | `success/error/timeout/rate_limited/blocked/cached` |
| `served_stage` | string(50) | yes | — | `fresh/cache/stale_while_revalidate/stale_if_error` |
| `cached` | boolean | no | `false` | True when served from cache |
| `http_status` | integer | yes | — | Upstream HTTP status |
| `duration_ms` | integer | yes | — | Wall-clock fetch duration |
| `bytes_in` | bigint | yes | — | Response bytes |
| `bytes_out` | bigint | yes | — | Request bytes |
| `rows_returned` | integer | yes | — | Canonical record count |
| `schema_valid` | boolean | yes | — | JSON-Schema result (`null` = no schema) |
| `response_sha256` | string(64) | yes | — | SHA256 of the exact response bytes |
| `redacted_url` | string(2000) | yes | — | URL after redaction (secrets masked) |
| `params_hash` | string(128) | yes | — | Digest of normalized params (variant key) |
| `redaction_applied` | boolean | no | `false` | PII redaction ran |
| `masking_applied` | boolean | no | `false` | Sensitive-key masking ran |
| `policy_decision` | string(50) | yes | — | `allow/deny/mask` |
| `principal` | string(255) | yes | — | Acting principal |
| `purpose` | string(255) | yes | — | Declared fetch purpose |
| `correlation_id` | string(255) | yes | — | Cross-system trace id |
| `estimated_cost_usd` | decimal(12,6) | yes | — | Pre-fetch cost estimate |
| `actual_cost_usd` | decimal(12,6) | yes | — | Realized egress cost |
| `error` | text | yes | — | Redacted error message |
| `quality_score` | decimal(5,4) | yes | — | **(2b)** Weighted share of quality rules passed (`QualityService`); nil when quality stage did not run |
| `quality_passed` | boolean | yes | — | **(2b)** `false` only when an error-severity rule failed; nil when not evaluated |
| `quarantined` | boolean | no | `false` | **(2b)** Bad batch was swapped for last-known-good and not cached |
| `schema_drift` | string(20) | yes | — | **(2b)** Drift classification for this fetch (`initial/none/additive/breaking`); nil when `track_schema` off |
| `metadata` | jsonb | no | `{}` | Includes `audit_chain` anchor mirror; `quality_results` / `anomalies` when the quality stage recorded them |
| `created_at` / `updated_at` | datetime | no | — | Timestamps |

The four Phase 2b columns are added by `20260606120600_add_quality_to_ai_data_source_queries` (no standalone indexes — they are always read alongside the owning row). They are written by `QueryService` only when the endpoint opts into the matching stage, and mirrored onto the `FetchEnvelope` provenance.

### `ai_data_source_schema_versions`

**(Phase 2b)** Per-endpoint response-schema version history — one row per observed/declared snapshot, classified against its immediate predecessor with the structural diff retained. Appended monotonically by `Ai::DataSources::SchemaDriftService#record_version!`. Model: `Ai::DataSourceSchemaVersion`. Migration: `20260606120500_create_ai_data_source_schema_versions_and_expectations`. Unique index on `(ai_data_source_endpoint_id, version)` (`index_ai_ds_schema_versions_unique_version`) — its leftmost prefix covers FK lookups, so there is **no** standalone FK index. Scopes: `for_endpoint`, `ordered`, `latest_first`, `breaking`.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | uuid | no | `gen_random_uuid()` | PK |
| `ai_data_source_endpoint_id` | uuid | no | — | FK → `ai_data_source_endpoints` |
| `version` | integer | no | `1` | Monotonic per endpoint; unique with the FK |
| `schema` | jsonb | no | `{}` | The captured JSON-Schema snapshot (array-root when inferred by `QueryService`) |
| `checksum` | string(64) | yes | — | SHA256 of the canonical schema; drives idempotent re-recording |
| `classification` | string(20) | no | `initial` | `initial` / `none` / `additive` / `breaking` (`CLASSIFICATIONS`) |
| `diff` | jsonb | no | `{}` | `{ added_fields:[], removed_fields:[], type_changes:[{field,from,to}] }` |
| `created_at` / `updated_at` | datetime | no | — | Timestamps |

### `ai_data_source_expectations`

**(Phase 2b)** Per-endpoint data-quality expectations (Great-Expectations-style rules) evaluated over canonical records by `Ai::DataSources::QualityService`. Model: `Ai::DataSourceExpectation`. Same migration as above. Indexed FK on `ai_data_source_endpoint_id`. Scopes: `for_endpoint`, `active` (`is_active: true`), `errors` (`severity: "error"`). No REST/MCP CRUD in Phase 2b — created at the model/seed layer.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | uuid | no | `gen_random_uuid()` | PK |
| `ai_data_source_endpoint_id` | uuid | no | — | FK → `ai_data_source_endpoints` |
| `name` | string(255) | no | — | Human label |
| `rule_type` | string(50) | no | — | `required_fields` / `min_records` / `max_records` / `non_null` / `allowed_values` / `distribution` (`RULE_TYPES`) |
| `config` | jsonb | no | `{}` | Rule params (e.g. `{ min: 1 }`, `{ fields: [...] }`, `{ field, values }`, `{ field, max_null_ratio }`) |
| `severity` | string(20) | no | `warn` | `warn` (lowers score) or `error` (fails batch + can trigger quarantine) |
| `is_active` | boolean | no | `true` | Only active rows are evaluated |
| `created_at` / `updated_at` | datetime | no | — | Timestamps |

### `ai_data_source_subscriptions`

**(Phase 3)** Pull-based subscription pairing a `(data_source, endpoint)` with a poll cadence + the last observed change fingerprint. Walked by `Ai::DataSources::MonitorService`. Model: `Ai::DataSourceSubscription`. Migration: `20260606121000_create_ai_data_source_subscriptions`. Composite scan index on `(status, next_poll_at)` (`index_ai_data_source_subscriptions_on_status_and_next_poll`) — backs the `due_for_poll` filter; `t.references` adds FK indexes on `ai_data_source_id`, `ai_data_source_endpoint_id`, and a bare index on `ai_agent_id`. Scopes: `active`, `due_for_poll` (includes `error`, excludes `paused`), `for_data_source`, `for_endpoint`.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | uuid | no | `gen_random_uuid()` | PK |
| `ai_data_source_id` | uuid | no | — | FK → `ai_data_sources` |
| `ai_data_source_endpoint_id` | uuid | no | — | FK → `ai_data_source_endpoints` |
| `ai_agent_id` | uuid | yes | — | Optional owning agent (cadence ownership; not FK-constrained to agent lifecycle) |
| `params` | jsonb | no | `{}` | Per-poll variables passed to each governed fetch |
| `poll_frequency` | string(50) | yes | — | One of `POLL_FREQUENCIES` (`manual/5min/hourly/daily/weekly/monthly/realtime`) |
| `status` | string(50) | no | `active` | `active/paused/error` (`STATUSES`) |
| `last_polled_at` | datetime | yes | — | Timestamp of the last poll attempt |
| `next_poll_at` | datetime | yes | — | When the monitor next picks this up (seeded on create for non-`manual` cadence; nil when `paused`/`manual`) |
| `last_checksum` | string(128) | yes | — | Canonical SHA256 of the last observed payload (change fingerprint) |
| `last_etag` | string(500) | yes | — | Last observed ETag (conditional-request hint) |
| `consecutive_failures` | integer | no | `0` | Failure counter; flips `status` to `error` at `>= 5`, reset to 0 on a successful poll |
| `metadata` | jsonb | no | `{}` | Free-form; holds `last_error` / `last_error_at` after a failure |
| `created_at` / `updated_at` | datetime | no | — | Timestamps |

## Related docs

- [`api/overview.md`](overview.md) — response envelope, auth, ApiResponse method reference
- [`api/ai.md`](ai.md#data-sources) — full AI controller catalogue (incl. credential CRUD)
- [`../../concepts/data-sources.md`](../../concepts/data-sources.md) — protocol/adapter/decoder model, the `QueryService` pipeline, security model, `FetchEnvelope`
- [`../../operations/data-sources.md`](../../operations/data-sources.md) — register a source, rotate a credential, troubleshoot
- [`../../concepts/permissions.md`](../../concepts/permissions.md) — `require_permission` / `has_permission?` behind the `ai.data_sources.*` grants
- [`../../concepts/mcp-and-tools.md`](../../concepts/mcp-and-tools.md) — how the `data_source_management` MCP tool dispatches
- [`reference/database-schema.md`](../database-schema.md) — full `ai_data_source*` table reference

_Last verified: 2026-06-06 (Phase 3: streaming / monitoring)_
