# Data Source Fetch Pipeline (Phase 1)

> Status: active
>
> **When to use this runbook**: monitoring, emergency-disabling, and troubleshooting the governed external-fetch pipeline that AI agents and workflows use to read live data through a registered `Ai::DataSource`. For registering sources and rotating credentials, see [data-sources.md](data-sources.md) (the Phase-0 registry runbook).

## Contents

- [Overview](#overview)
- [The fetch pipeline](#the-fetch-pipeline)
- [Models](#models)
- [Interfaces — REST + MCP](#interfaces--rest--mcp)
- [Monitoring & health](#monitoring--health)
- [Emergency disable — the per-source kill flag](#emergency-disable--the-per-source-kill-flag)
- [Quotas, per-agent fairness, cooldowns](#quotas-per-agent-fairness-cooldowns)
- [Cost attribution](#cost-attribution)
- [The hash-chained query log](#the-hash-chained-query-log)
- [Troubleshooting](#troubleshooting)
- [Key files](#key-files)
- [See also](#see-also)

## Overview

Phase 1 adds a single governed fetch path on top of the Phase-0 registry. Every
outbound read goes through `Ai::DataSources::QueryService`, which composes the
data-source modules (adapters, signers, decoders, format detection,
normalization, the SSRF-guarded connection factory, the response cache) with the
shared reuse services (kill flag, quotas, circuit breaker, credential vault,
schema validation, PII redaction, audit hash chain, cost attribution) into one
pipeline.

The service **never raises**: every failure path is mapped to a `FetchEnvelope`
with `success: false` and a redacted error message. A source is identified by its
`slug`; an endpoint (the concrete URL + method + response shape) is a child
`Ai::DataSourceEndpoint`.

`FetchEnvelope` (the return shape callers and operators see):

```
{
  success:,                      # Boolean
  data:,                         # Array<Hash> — canonical, normalized records
  provenance: {
    slug:, endpoint_id:, fetched_at:, from_cache:, cache_age_seconds:,
    response_sha256:, source_url:,            # source_url is REDACTED
    declared_vs_detected_content_type:, charset:, applied_encoding:,
    schema_valid:, record_count:, anomalies: []
  },
  status:,                       # success | error | timeout | rate_limited | blocked | cached
  duration_ms:, bytes:, error:   # error nil on success; redacted otherwise
}
```

`status` is the fastest triage signal — it tells you *which* stage stopped the
fetch (see the [troubleshooting](#troubleshooting) map). `provenance.anomalies`
is the second signal: it accumulates tokens like `content_type_mismatch`,
`schema_invalid`, `decode_error`, `http_<code>`, `rate_limited`,
`source_disabled` as the pipeline runs.

## The fetch pipeline

`Ai::DataSources::QueryService.new(data_source:, endpoint:, params:, agent:, user:).call`
runs these stages in order (each short-circuits to a `FetchEnvelope`):

| # | Stage | Service | Failure → `status` |
|---|-------|---------|--------------------|
| 1 | Per-source kill flag | `Shared::FeatureFlagService` / Flipper | `blocked` (`source_disabled`) |
| 2 | Quota — per-source + per-agent | `DataSource#check_quota!` + Redis | `rate_limited` |
| 3 | Response cache (singleflight) | `ResponseCacheService.fetch` | `cached` on hit |
| 4 | Credential resolve (Vault → DB) | `Security::VaultCredentialProvider` | (signing fails later) |
| 5 | Circuit-breaker-wrapped dispatch: build → sign → `validate_url!` → send | `CircuitBreakerRegistry` + `HttpConnectionFactory` | `error` (circuit open / transport), `timeout`, `blocked` (SSRF / oversize) |
| 6 | Detect format + decode → records | `Decoders::FormatDetector` + adapter | `decode_error` anomaly (records `[]`) |
| 7 | Schema validate + normalize | `JsonSchemaValidator` + `NormalizationService` | `schema_invalid` anomaly |
| 8 | Record usage + credential health | `DataSource#record_request!` | — |
| 9 | Redact → persist query row → audit hash chain → cost row | `PiiRedactionService`, `Audit::LogIntegrityService`, `Ai::CostAttribution` | — |
| 10 | Cache write (fresh success only) + return envelope | `ResponseCacheService.write` | — |

Two safety properties worth remembering during an incident:

- **Persistence runs exactly once** in `call`, never inside the cache block. A
  cache hit still produces a query-log row (`cached: true`, `served_stage:
  "cache"`) and a cost row — egress is zero-byte but the access is still
  attributed and audited.
- **Idempotent verbs** (`GET HEAD PUT DELETE OPTIONS TRACE`) get one automatic
  transient-failure retry; `POST` is retried only when the caller supplies an
  idempotency key (`auth_config["idempotency_key"]` or `params[:idempotency_key]`).

## Models

| Model | Table | Role |
|-------|-------|------|
| `Ai::DataSource` | `ai_data_sources` | Source registry; `has_many :endpoints, :queries`; new `protocol`, `auth_scheme`, `auth_config` columns; quota counters in Redis |
| `Ai::DataSourceEndpoint` | `ai_data_source_endpoints` | Concrete URL + `http_method` + `response_format` + `response_schema`/`response_mapping` + `cache_ttl_seconds`; `monitorable` flag |
| `Ai::DataSourceQuery` | `ai_data_source_queries` | The query/audit log — one row per fetch (see [hash-chained query log](#the-hash-chained-query-log)) |
| `Ai::DataSourceCredential` | `ai_data_source_credentials` | Credentials; new `vault_path` + `migrated_to_vault_at` columns drive Vault-first resolution |

`auth_scheme` selects the outbound signer (see
[auth failures](#authsigning-failures)). `auth_config` carries scheme-specific
knobs (header/param names, region, service, algorithm) **and** the optional
`idempotency_key`.

## Interfaces — REST + MCP

### REST (nested under a data source)

All under `/api/v1/ai/data_sources` (`:id` accepts UUID or slug). Permissions
are enforced in `validate_permissions`:

| Method | Path | Action | Permission |
|--------|------|--------|------------|
| `GET` | `/:id/endpoints` | list endpoints | `ai.data_sources.read` |
| `POST` | `/:id/endpoints` | create endpoint | `ai.data_sources.update` or `.manage` |
| `PATCH`/`PUT` | `/:id/endpoints/:endpoint_id` | update endpoint | `ai.data_sources.update` or `.manage` |
| `DELETE` | `/:id/endpoints/:endpoint_id` | delete endpoint | `ai.data_sources.update` or `.manage` |
| `POST` | `/:id/endpoints/:endpoint_id/query` | **run a governed fetch** (calls `QueryService`) | `ai.data_sources.query` |
| `GET` | `/:id/quota_status` | quota summary + live `check_quota!` | `ai.data_sources.read` |
| `POST` | `/:id/test_connection` | probe base URL with active credential | `ai.data_sources.read` |

### MCP — `Ai::Tools::DataSourceTool` (`platform.data_source_*`)

Registered in `PlatformApiToolRegistry`. Actions:
`data_source_{list,get,describe,query,health,validate_config,create,update,delete}`.

| Action | Permission | Notes |
|--------|------------|-------|
| `data_source_list` / `get` / `describe` | `ai.data_sources.read` | read paths |
| `data_source_health` | `ai.data_sources.read` | quota + cache + breaker (see below) |
| `data_source_validate_config` | `ai.data_sources.read` | base URL, auth scheme, protocol, endpoint/credential sanity |
| `data_source_query` | `ai.data_sources.query` | runs the full pipeline; returns the `FetchEnvelope` verbatim |
| `data_source_create` / `update` / `delete` | `.create` / `.update` / `.delete` (or `.manage`) | **proposal fallback**: an agent lacking the permission files a proposal via `ProposalService` instead of mutating |

## Monitoring & health

### One-shot health snapshot (MCP)

`platform.data_source_health` (action `data_source_health`) returns the operator
triage bundle in one call — quota, cache, and breaker state together:

```
{
  data_source:   { id:, slug:, name:, health_status: },   # healthy|degraded|critical|unknown
  quota_summary: { usage:, limits:, utilization: { minute_pct:, hour_pct:, day_pct: } },
  cache_metrics: { hits:, misses:, total:, hit_rate: },   # hit_rate is a percentage
  circuit_breaker: {
    service_name: "data_source:<id>",
    state:,                  # closed | open | half_open
    failure_count:, success_count:, consecutive_failures:,
    last_failure_at:, available:
  }
}
```

Each sub-block degrades safely if its backend is unavailable (cache metrics fall
back to zeros with `error: "unavailable"`; an uninitialized breaker reports
`state: "closed", available: true, note: "no breaker initialized yet"`).

### Health status semantics

`health_status` is recomputed by `DataSource#update_health_status!` from the
active credential's failure streak — it is **credential health, not pipeline
health**:

| `consecutive_failures` (active credential) | `health_status` |
|--------------------------------------------|-----------------|
| inactive source or no credential | `unknown` |
| 0–1 | `healthy` |
| 2–4 | `degraded` |
| ≥ 5 | `critical` |

So a source can read `critical` while the circuit breaker is still `closed` (or
vice-versa). Always read both. The breaker reflects *upstream transport* health
per source (keyed `data_source:<id>`), so one flaky upstream trips only its own
breaker.

### Cache metrics

`Ai::DataSources::ResponseCacheService.metrics` →
`{ hits:, misses:, total:, hit_rate: }` (rolling 7-day counters in Redis DB 0,
same shape as the prompt cache). Per-source counters also exist under
`data_source_cache:metrics:hits:<id>` / `:misses:<id>`.

- A **falling `hit_rate`** with stable traffic usually means TTLs are too short
  (`endpoint.cache_ttl_seconds`, default 5 min) or params vary per call (each
  param-variant is a distinct cache key).
- The cache uses **singleflight** (Redis `SET NX PX` recompute lock) plus
  **XFetch** probabilistic early refresh, so a popular key is recomputed by
  exactly one caller just before expiry — you should *not* see thundering-herd
  recompute spikes. If you do, check that `data_source_response_caching` is on.

Invalidate after fixing a bad upstream payload:

```ruby
# All param-variants for one endpoint:
Ai::DataSources::ResponseCacheService.invalidate(data_source: ds, endpoint: ep)
# Every endpoint + variant for the whole source:
Ai::DataSources::ResponseCacheService.invalidate(data_source: ds)
# Returns the number of keys deleted (SCAN-based, non-blocking).
```

### Circuit-breaker state

`closed` = healthy, `open` = short-circuiting (fetches return `status: error`,
"data source temporarily unavailable (circuit open)" **without** touching
credential failure counters — the breaker already reflects upstream health),
`half_open` = trial requests after the cool-off. Inspect via
`platform.data_source_health` or directly:

```ruby
Ai::CircuitBreakerRegistry.get_breaker("data_source:#{ds.id}")&.circuit_stats
Ai::CircuitBreakerRegistry.service_available?("data_source:#{ds.id}")
```

## Emergency disable — the per-source kill flag

Each source has a **kill flag** (Flipper, via `Shared::FeatureFlagService`),
named:

```
data_source.<slug>.enabled
```

Semantics (this is a kill switch, **not** an opt-in): an **unset** flag means
*enabled* — sources work out of the box. Only a flag that is *present and false*
disables the source. When disabled, `QueryService` short-circuits at stage 1 and
returns `status: blocked`, `error: "data source disabled by kill flag"`, with a
`source_disabled` anomaly; a query-log row is still written for the audit trail.
The kill-flag check itself **fails open** (a Flipper error logs a warning and
treats the source as enabled) so a flag-store outage never silently blackholes
all fetches.

Disable / re-enable from a Rails console:

```ruby
# Emergency disable a single misbehaving source (creates the flag, set to off):
Flipper.disable("data_source.<slug>.enabled")

# Re-enable (or simply remove the flag — absence == enabled):
Flipper.enable("data_source.<slug>.enabled")
# or: Flipper.remove("data_source.<slug>.enabled")

# Confirm:
Flipper.exist?("data_source.<slug>.enabled")
Shared::FeatureFlagService.enabled?("data_source.<slug>.enabled")
```

> **Kill flag vs `is_active`.** `is_active: false` disables the source across the
> whole registry (it drops out of `active_credential`, health flips to
> `unknown`, and it disappears from `active`-scoped listings). The kill flag is
> the *surgical, instantly-reversible* lever for the fetch pipeline only —
> prefer it for emergency cut-over because flipping it back is a single Flipper
> call with no DB write and no health-status churn.

There is a **second, independent flag** for the cache layer:
`data_source_response_caching` (same unset-means-on semantics). Disabling it
forces every fetch to recompute and never touch Redis — useful when you suspect
the cache is serving a poisoned payload and you want live reads while you
investigate:

```ruby
Flipper.disable(:data_source_response_caching)   # global cache bypass
```

## Quotas, per-agent fairness, cooldowns

Quotas are enforced **client-side, before** the outbound call, in two tiers.
Both use atomic Redis counters with rolling minute/hour/day windows.

### Tier 1 — per-source

`DataSource#check_quota!` reads `rate_limits` (`requests_per_minute` /
`_per_hour` / `_per_day`) against `current_quota_usage` and returns
`{ allowed: false, retry_after: <s>, limit: "requests_per_minute" }` when any
window is exhausted. Counters live under
`data_source:<id>:quota:{min,hr,day}:<bucket>` (plus a `:bw:<day>` byte counter).

### Tier 2 — per-agent fairness

So one noisy agent cannot drain the whole source budget, `QueryService`
additionally checks a per-agent counter namespaced under
`data_source:<id>:quota:<agent_id>:{min,hr,day}:<bucket>`. Limits come from
`rate_limits["per_agent"]` (`requests_per_minute` / `_per_hour` / `_per_day`);
**absent → no per-agent cap**. A per-agent block returns `limit:
"per_agent.requests_per_minute"` (etc.) so you can tell tier-1 from tier-2 in
the query log and the `FetchEnvelope`.

Configure both tiers via the source's `rate_limits` JSON (PATCH the source):

```json
{
  "data_source": {
    "rate_limits": {
      "requests_per_minute": 60,
      "requests_per_hour": 1000,
      "requests_per_day": 10000,
      "per_agent": { "requests_per_minute": 10, "requests_per_hour": 100 }
    }
  }
}
```

### Cooldowns (`retry_after`)

When blocked, `status: rate_limited`, the envelope carries `retry_after`
(seconds until the *current* window rolls over — `60 - now.sec` for the minute
window, etc.), and the log row records `http_status: 429`. Callers should honor
it as a cooldown rather than hot-retrying. Both quota checks **fail open** on a
Redis error (a warning is logged) so a Redis blip degrades to "allow", never
"block everything".

Inspect live usage:

```bash
# REST — source-wide:
curl -H "Authorization: Bearer $JWT" \
  https://<host>/api/v1/ai/data_sources/<id>/quota_status | jq '.data.quota.utilization'
```

```ruby
# Console — raw counters (source-wide):
ds.current_quota_usage   # => { minute:, hour:, day:, bandwidth_today: }
ds.quota_summary         # => usage + limits + utilization percentages
```

## Cost attribution

Every fetch — **including cache hits** — emits exactly one `Ai::CostAttribution`
row via `Ai::CostAttribution.from_data_source_query`:

- `source_type: "data_source"`, `cost_category: "api_calls"`, `api_calls: 1`,
  `attribution_date: Date.current`.
- `amount_usd = cost_per_request_usd + (cost_per_gb_usd * GiB_transferred)`,
  both rates read from the source's `configuration` (default `0.0` → zero-cost
  but still attributed). Cache hits are zero-byte, so their amount is just the
  per-request component.
- `metadata` links back via `data_source_slug`, `query_id`, `agent_id`, `bytes`.

Per-day attributions roll up into `Ai::RoiMetric` via the daily aggregation job
(`aggregate_to_roi_metrics`). To audit spend for a source:

```ruby
Ai::CostAttribution.for_account(account).by_category("api_calls")
  .where("metadata->>'data_source_slug' = ?", "<slug>")
  .for_date_range(7.days.ago.to_date, Date.current)
  .sum(:amount_usd)
```

> A sudden cost jump with a flat `bytes` total points at request volume
> (per-request pricing) — cross-check the per-agent quota usage to find the
> source of the traffic. A jump in `bytes` with flat request count points at a
> provider that started returning larger payloads (also check the response-size
> cap, below).

## The hash-chained query log

Every fetch persists one `ai_data_source_queries` row, written **fully redacted
before it touches the database** and tied into the platform-wide tamper-evident
audit hash chain.

### What the row captures

| Column(s) | Captures |
|-----------|----------|
| `status`, `http_status`, `duration_ms`, `bytes_in`, `rows_returned` | outcome + timing + size |
| `principal`, `requesting_agent_id`, `account_id`, `purpose` | who/why (`purpose` = endpoint slug; `principal` = `agent:<id>` / `user:<id>` / `system`) |
| `redacted_url`, `redaction_applied`, `masking_applied` | the URL **with secrets stripped** (always redacted) |
| `params_hash` | SHA256 of normalized params (the params themselves are **not** stored raw) |
| `response_sha256` | SHA256 of the raw response body — content fingerprint for change detection / forensics |
| `cached`, `served_stage` | `fresh` vs `cache` |
| `schema_valid` | `true` / `false` / `null` (null = no schema configured = "unknown") |
| `correlation_id`, `error` (redacted) | trace + redacted failure message |
| `metadata` | `anomalies`, `declared_vs_detected_content_type`, `charset`, `applied_encoding`, `redacted_params`, `redacted_response_snippet` (first 2 KB, redacted), and the **`audit_chain` anchor** |

### Redaction guarantees

- The URL query string is masked twice: a hard `SENSITIVE_QUERY_KEY` regex masks
  values of `?token=`, `?secret=`, `?sig=`, `?api_key=` (and many spellings)
  **by key**, then `Ai::Security::PiiRedactionService` runs over the result. On
  any redaction error the whole query string is stripped rather than risk a
  leak.
- The response snippet, error message, and params are each routed through the
  same redactor before persistence. **No raw secret or PII reaches the log.**

### What the hash chain captures

When the query row is saved, a companion `AuditLog` is written
(`api_request` on success/cache, `api_request_failed` otherwise). `AuditLog`'s
`before_create` hook runs `Audit::LogIntegrityService`, which assigns a
monotonic `sequence_number`, the `previous_hash` (linking to the prior entry;
the first entry chains to `GENESIS_HASH`), and an `integrity_hash`. Those three
values are mirrored back into `query.metadata["audit_chain"]`
(`audit_log_id`, `integrity_hash`, `previous_hash`, `sequence_number`) so the
chain anchor is discoverable from the query row **without a join**. Audit-chain
failures never break a fetch — the query row still persists.

Verify the chain is intact (detects tampering, sequence gaps, and broken hash
linkage):

```ruby
Audit::LogIntegrityService.verify_chain
# => { total_entries:, verified_entries:, invalid_entries: [...], chain_intact: true|false }
# Scope a window with from_sequence:/to_sequence: for large logs.
```

A `chain_intact: false` result with populated `invalid_entries` means an audit
row was altered or deleted out from under the chain — escalate per
[incident-response.md](incident-response.md).

## Troubleshooting

Start from the envelope `status` and `provenance.anomalies`, then drill in.

| `status` / anomaly | Likely cause | First action |
|--------------------|--------------|--------------|
| `blocked` + `source_disabled` | Kill flag is off | `Flipper.enabled?("data_source.<slug>.enabled")`; re-enable if the disable was unintended |
| `blocked` (no `source_disabled`) | SSRF guard or oversize response | See [SSRF blocks](#ssrf-blocks) / [oversize](#oversize-responses) below |
| `rate_limited` | Quota window exhausted | Read `limit` — `requests_per_*` (source) vs `per_agent.*` (one agent); honor `retry_after` |
| `timeout` | Slow upstream | Check provider status; raise `configuration.read_timeout_seconds` if legitimately slow |
| `error` + "circuit open" | Breaker tripped from repeated failures | `data_source_health` → breaker `state`; wait for `half_open`, fix upstream |
| `content_type_mismatch` anomaly | Provider's declared type ≠ actual bytes | See [decode failures](#decode-failures-format-mismatch) |
| `decode_error` anomaly (`data` empty) | Decoder couldn't parse the body | See [decode failures](#decode-failures-format-mismatch) |
| `schema_invalid` anomaly | Payload shape drifted from `response_schema` | Compare a sample against the endpoint's `response_schema`; loosen/fix the schema |

### Decode failures (format mismatch)

`Decoders::FormatDetector.detect` sniffs the body (magic bytes / XML root /
declared `Content-Type` / `endpoint.expected_content_type`) independently of the
provider's claim, and flags `mismatch: true` when they disagree (the classic
case: an HTML error page served with a JSON `Content-Type`). That surfaces as the
`content_type_mismatch` anomaly; if the wrong decoder then can't parse, you also
get `decode_error` and an empty `data` array.

Steps:
1. Pull the offending row and read `metadata.declared_vs_detected_content_type`
   and `metadata.redacted_response_snippet` — the snippet usually shows it's an
   HTML/error page, not the expected JSON/CSV.
2. If the provider is genuinely returning a different format, set
   `endpoint.response_format` (one of
   `json xml csv ndjson rss atom html text binary`) to match, or fix the upstream
   request so it returns the right type.
3. Re-run via `data_source_query`; confirm the anomaly clears and `record_count`
   is non-zero.

> Decoder contract reference: `Decoders::Registry.for(format:,
> content_type:).decode(raw_body, endpoint:)` → `Array<Hash>` (e.g. CSV
> `"city,temp\nNYC,72"` → `[{"city"=>"NYC","temp"=>"72"}]`).

### Auth/signing failures

The signer is chosen by `data_source.auth_scheme` via
`Auth::SignerRegistry.for(auth_scheme)` — schemes:
`none`, `api_key`, `bearer`, `aws_sigv4` (wraps `Aws::Sigv4::Signer`), `hmac`.
An unknown/blank scheme degrades safely to `none` (no mutation) rather than
raising. A signing failure is logged **without the credential material** (only
the error class) and surfaces as a generic `error` envelope.

Steps:
1. Confirm the scheme: `ds.auth_scheme` and the scheme-specific `ds.auth_config`
   (header/param name, `region`/`service` for SigV4, `algorithm` for HMAC).
2. Confirm a usable credential exists: `ds.active_credential` (and, if migrated,
   `ds.active_credential.vault_path` — Vault is preferred; the DB-encrypted
   value is the fallback). `data_source_validate_config` warns "Active but has no
   usable credential".
3. Rotate the credential via the Phase-0 procedure in
   [data-sources.md](data-sources.md#procedure--rotate-a-credential) if the key
   is stale/leaked. **Never** echo a key to confirm it — test with
   `POST /:id/test_connection` or a `data_source_query`.

### SSRF blocks

`HttpConnectionFactory.validate_url!` resolves the host and **rejects** any IP in
a private / loopback / link-local / unique-local / metadata range (IPv4 + IPv6,
including the cloud metadata endpoint `169.254.169.254` and IPv4-mapped IPv6).
The check runs on the initial URL **and every redirect hop**, so a public host
cannot 30x-bounce into the internal network. A block raises
`Ai::DataSources::HttpConnectionFactory::SsrfError`; the envelope reports
`status: blocked`, `error: "request blocked by egress policy"` (the internal
resolved IP is deliberately **not** echoed into the error).

Steps:
1. Inspect `redacted_url` on the failed row — most often the source's
   `api_base_url` (or a redirect target) points at an internal/private address
   or a non-`http(s)` scheme.
2. If the target is legitimately public, confirm DNS resolves it to a public IP
   from the backend host (`Resolv.getaddresses("<host>")`).
3. Do **not** add private ranges to an allowlist to "fix" this — that defeats the
   egress control. Front internal services with a proper public-facing gateway
   instead.

### Oversize responses

A response body over the cap (default 10 MiB; an endpoint may *lower* it via
`configuration.max_response_bytes` but never raise it) raises
`ResponseTooLargeError` → `status: error`, "response exceeded size cap". The cap
is enforced both by the declared `Content-Length` (pre-allocation) and the
materialized body. If a source legitimately returns large payloads, paginate at
the endpoint level rather than raising the global ceiling.

### Quick console reproduction

```ruby
ds = Ai::DataSource.find_by!(slug: "<slug>")
ep = ds.endpoints.find_by!(slug: "<endpoint-slug>")
env = Ai::DataSources::QueryService.new(
  data_source: ds, endpoint: ep, params: { ... }, agent: nil, user: nil
).call
env[:status]                       # triage
env[:provenance][:anomalies]       # what tripped
env[:provenance][:declared_vs_detected_content_type]
```

## Key files

| Role | Path |
|------|------|
| Pipeline integrator | `server/app/services/ai/data_sources/query_service.rb` |
| SSRF-guarded connection factory | `server/app/services/ai/data_sources/http_connection_factory.rb` |
| Response cache (singleflight + XFetch) | `server/app/services/ai/data_sources/response_cache_service.rb` |
| Decoders (registry + json/xml/csv/ndjson + detector) | `server/app/services/ai/data_sources/decoders/` |
| Adapters (base/rest/registry) | `server/app/services/ai/data_sources/adapters/` |
| Signers (registry + sigv4/hmac) | `server/app/services/ai/data_sources/auth/` |
| HTTP signature helper | `server/app/services/security/http_signature.rb` |
| Normalization | `server/app/services/ai/data_sources/normalization_service.rb` |
| Audit hash chain | `server/app/services/audit/log_integrity_service.rb` |
| Cost builder | `server/app/models/ai/cost_attribution.rb` (`from_data_source_query`) |
| Query log model | `server/app/models/ai/data_source_query.rb` |
| Endpoint model | `server/app/models/ai/data_source_endpoint.rb` |
| MCP tool | `server/app/services/ai/tools/data_source_tool.rb` |
| REST controller | `server/app/controllers/api/v1/ai/data_sources_controller.rb` |
| Routes | `server/config/routes.rb` (`resources :data_sources` + nested `endpoints`) |
| Frontend — endpoints tab + query console | `frontend/src/features/ai/data-sources/components/{DataSourceEndpointsTab,DataSourceQueryConsole}.tsx` |

## See also

- [data-sources.md](data-sources.md) — Phase-0 registry: registering sources, rotating credentials, basic quota
- [ai-operations.md](ai-operations.md) — AI provider sister system; same encryption / credential patterns
- [observability.md](observability.md) — log labels + LogQL queries for correlating fetch traces
- [incident-response.md](incident-response.md) — escalation path for a broken audit chain or SSRF exposure
- [worker-operations.md](worker-operations.md) — sync / health jobs schedule

_Last verified: 2026-06-06_
