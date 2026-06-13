# Data Sources

> Status: active
>
> When to use this runbook: registering, rotating, and troubleshooting external data-API integrations consumed by AI agents and workflows.

## Table of Contents

- [Prerequisites](#prerequisites)
- [When to use this](#when-to-use-this)
- [Overview](#overview)
- [Source Types & Categories](#source-types--categories)
- [Models](#models)
- [HTTP API](#http-api)
- [Procedure — register a new source](#procedure--register-a-new-source)
- [Procedure — rotate a credential](#procedure--rotate-a-credential)
- [Quota Enforcement Pattern](#quota-enforcement-pattern)
- [Credential brokering (Phase 4b-2a)](#credential-brokering-phase-4b-2a)
- [Query-time governance (Phase 4b-2b)](#query-time-governance-phase-4b-2b)
- [Retrieval transforms, dry-run estimates & cache-tag invalidation (Phase 4b-3a)](#retrieval-transforms-dry-run-estimates--cache-tag-invalidation-phase-4b-3a)
  - [A response changed shape — the config-driven transform pipeline](#a-response-changed-shape--the-config-driven-transform-pipeline)
  - [Estimating cost before enabling a costly source (dry-run)](#estimating-cost-before-enabling-a-costly-source-dry-run)
  - [Cache-tag invalidation operations](#cache-tag-invalidation-operations)
- [Onboarding & config versioning (Phase 4b-3b)](#onboarding--config-versioning-phase-4b-3b)
  - [Exports are credential-free — the security contract](#exports-are-credential-free--the-security-contract)
  - [Bulk-onboarding from templates](#bulk-onboarding-from-templates)
  - [Auditing config history](#auditing-config-history)
  - [Rolling back a bad config change](#rolling-back-a-bad-config-change)
- [Multi-source failover, forensic replay & RAG ingestion (Phase 4b-3c)](#multi-source-failover-forensic-replay--rag-ingestion-phase-4b-3c)
  - [Configuring a primary + mirror failover group](#configuring-a-primary--mirror-failover-group)
  - [Reading the failover provenance flags](#reading-the-failover-provenance-flags)
  - [Investigating a past fetch with replay](#investigating-a-past-fetch-with-replay)
  - [RAG ingestion operations](#rag-ingestion-operations)
  - [Reconciliation determinism (same inputs ⇒ same merge)](#reconciliation-determinism-same-inputs--same-merge)
- [Discovery & effectiveness (Phase 2a)](#discovery--effectiveness-phase-2a)
- [Quality, drift & contracts (Phase 2b)](#quality-drift--contracts-phase-2b)
- [Monitoring a source for changes (Phase 3)](#monitoring-a-source-for-changes-phase-3)
- [Stale-while-revalidate & stale-if-error](#stale-while-revalidate--stale-if-error)
- [Incremental sync stuck / not advancing](#incremental-sync-stuck--not-advancing)
- [Crawl politeness troubleshooting](#crawl-politeness-troubleshooting)
- [Nightly schema sync (Phase 4)](#nightly-schema-sync-phase-4)
- [Outbound pagination operational limits (Phase 4)](#outbound-pagination-operational-limits-phase-4)
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
>
> **Generic source framework (Phase 4).** `source_type` is now free-form (no enum), sources carry a `category` grouping, and the `protocol` column selects the adapter (REST / GraphQL / RSS-Atom). Two operational concerns land here: a **nightly schema-sync cron** (`AiDataSourceSchemaSyncJob`, `0 4 * * *`) that samples schema-tracked / baseline-less endpoints and records inferred schema versions — see [Nightly schema sync (Phase 4)](#nightly-schema-sync-phase-4) — and **outbound pagination** limits when an endpoint sets a `pagination` config — see [Outbound pagination operational limits (Phase 4)](#outbound-pagination-operational-limits-phase-4). The onboarding / config walkthroughs are in [../guides/data-sources.md](../guides/data-sources.md#onboarding-a-graphql-or-rssatom-source-phase-4).

## Source Types & Categories

> **Phase 4: `source_type` is now FREE-FORM.** The model no longer enforces an enum — `source_type` accepts any lowercase token (`/\A[a-z0-9_-]+\z/`, ≤50 chars). The list below is `Ai::DataSource::SUGGESTED_SOURCE_TYPES` (UI autocomplete hints only; `SOURCE_TYPES` is a backward-compat alias of it), **not** a constraint. New source kinds need no code change.

| Suggested type | Description | Backfilled `category` |
|------|-------------|------|
| `noaa_ncei` | NOAA National Centers for Environmental Information — historical climate data | `weather` |
| `noaa_gfs` | NOAA Global Forecast System — numerical weather prediction | `weather` |
| `noaa_observations` | NOAA current observations | `weather` |
| `open_meteo` | Open-Meteo — free weather API (no key for historical / forecast) | `weather` |
| `fred` | Federal Reserve Economic Data — macroeconomic indicators | `finance` |
| `yahoo_finance` | Yahoo Finance — market data | `finance` |
| `espn` | ESPN — sports data | `sports` |
| `newsapi` | NewsAPI — news aggregation | `news` |
| `custom` | Arbitrary REST source with a hand-rolled template | — (NULL) |

The **`category`** column (string, ≤100 chars, nullable) is the coarse grouping the `by_category` scope and the `?category=` list filter use. Migration `20260606122000` backfilled it from the legacy `source_type` tokens per the mapping above (a partial index on `category WHERE category IS NOT NULL` keeps the filter fast); `custom` and any later free-form token stay NULL. The **`protocol`** column (string, default `"rest"`) selects the adapter — `rest`/`custom` → generic REST, `graphql` → GraphQL, `rss`/`atom` → feed adapter (see the [guide](../guides/data-sources.md#onboarding-a-graphql-or-rssatom-source-phase-4)).

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

**Scopes:** `active`, `by_type(type)`, `by_category(category)`, `for_account(account)`, `ordered_by_priority`, `requiring_auth`.

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

## Credential brokering (Phase 4b-2a)

Phase 4b-2a adds **dynamic credential brokering** to the governed fetch. Instead of signing every request with a static stored secret, a source can configure a **broker** that EXCHANGES its resolved base credential with an external authority — AWS STS (`AssumeRole` / `AssumeRoleWithWebIdentity`), an OAuth2 token endpoint (`client_credentials` grant), a Vault dynamic secrets engine, or an S3/Azure presigner — for a **short-lived** credential, minted just before the signed fetch. The brokered credential satisfies the same signer contract (`decrypted_api_key` / `decrypted_api_secret` / `[](name)`), so the signer layer is unchanged.

Brokering slots into `QueryService#resolve_credential` (via `maybe_broker_credential`) **after** the base credential is resolved, gated on `data_source.auth_config["broker"]["type"]`. **No broker configured (or a blank/unknown type) ⇒ byte-for-byte the original behavior** — `Registry.for` falls back to `StaticBroker`, which returns the base credential unchanged (mirroring `SignerRegistry`'s `NoneSigner` fallback). The seven broker types and their config are in the model layer; this section is the *operating* side.

> **Two layers of fail-safe — a broker fault NEVER breaks a fetch.** `BaseBroker#acquire` wraps the subclass exchange in a rescue that **degrades to the base credential** on any error; `QueryService#maybe_broker_credential` then wraps *that* in a second rescue (defense in depth). So a misconfigured or unreachable broker silently falls back to signing with the stored credential. `@last_credential` deliberately stays pinned to the **base** credential, so the source's success/failure counters and `effectiveness_score` track the STORED credential, not the ephemeral brokered one.

### Telling whether brokering is active

Every acquisition emits a **single non-secret audit line** via `BaseBroker#audit_log` (`Rails.logger.info`), tagged with the demodulized broker class. The shape is fixed:

```
[Credentials::<BrokerClass>] broker=<type> source=<slug> outcome=<outcome> <k=v ...>
```

- **`broker=`** — the canonical broker type (`aws_sts`, `aws_sts_web_identity`, `oauth2_client_credentials`, `vault_dynamic`, `presigned_url`, `static`).
- **`source=`** — the data source slug (`unknown` if unresolvable).
- **`outcome=`** — the operationally relevant signal: **`acquired`** (a fresh short-lived credential was minted — carries `expires_at=<iso8601|none>`), **`skipped`** (brokering could not proceed — carries `reason=<...>`, the credential degraded to base), or **`error`** (the exchange raised — carries `error_class=<...>`, also degraded to base). (`cached` is defined in the contract but the current brokers do not emit it — a cache HIT is silent; only the miss-path mint logs `acquired`.)

```bash
# Is brokering firing at all? Tail the audit lines (all brokers share the prefix).
journalctl -u powernode-backend@default -f | grep -E '\[Credentials::[A-Za-z]+\]'

# Only the successful mints (fresh short-lived creds), with their lease expiry.
journalctl -u powernode-backend@default --since "15 minutes ago" \
  | grep -E '\[Credentials::.*\] .*outcome=acquired'

# Confirm a specific source is being brokered (slug filter).
journalctl -u powernode-backend@default --since "15 minutes ago" \
  | grep -E 'source=open-meteo' | grep -E 'broker='
```

What the presence/absence of these lines tells you:

| Observation | Meaning |
|-------------|---------|
| `outcome=acquired expires_at=<iso8601>` on the source | Brokering is **active and healthy** — a fresh lease was minted (this is a cache MISS; subsequent reads within the lease are silent cache HITs) |
| No `[Credentials::…]` lines despite expecting brokering | Either no broker is configured (check `auth_config["broker"]["type"]`), the type resolved to `static` (unknown type ⇒ silent no-op), **or** every request is hitting the warm cache (no miss ⇒ no log). Flush the cache (below) to force one logged mint |
| `outcome=skipped reason=<…>` | The broker bailed before any exchange and **degraded to base** — see the degrade table below |
| `outcome=error error_class=<…>` | The exchange raised and **degraded to base** — see the degrade table below |

### Troubleshooting a broker that silently degrades to base

The whole design is fail-open, so a broker that "isn't working" usually means **it degraded to the base credential and the fetch still succeeded with the stored secret** — there is no fetch failure to chase, only the audit line. Two outcomes signal a degrade, each with a discriminating field:

**`outcome=error error_class=<class>`** — the subclass `acquire!` raised and `BaseBroker#acquire` caught it. Only `error_class` is logged (never the exception message — an HTTP/SDK message can echo request material, e.g. a `client_secret`). Common classes:

| `error_class` | Likely cause | First action |
|---------------|--------------|--------------|
| `Ai::DataSources::HttpConnectionFactory::SsrfError` | A config `token_url` (OAuth2 / web-identity) resolves to a private/loopback/link-local address or a disallowed scheme — see [SSRF guard](#the-ssrf-guard-rejecting-a-token_url) below | Fix the `token_url` to a public, resolvable HTTPS endpoint; confirm it does not resolve to `169.254.169.254` / RFC-1918 |
| `Aws::STS::Errors::AccessDenied` | The base IAM key cannot `sts:AssumeRole` into `role_arn` (or `external_id` mismatch / wrong trust policy) | Verify the role's trust policy trusts the base principal; check `external_id` matches; confirm `role_arn` |
| `Aws::STS::Errors::ValidationError` | `duration_seconds` out of the STS window, or a malformed `role_arn` | The broker clamps duration to 900..43200 — check `role_arn` syntax and `session_name` |
| `Aws::Sigv4::Errors::MissingCredentialsError` / `Aws::Errors::MissingRegionError` | Base AWS keys empty (STS path) or no region resolvable | Brokers default region to `us-east-1`; verify the base credential actually carries AWS keys |
| `Errno::ENOENT` (web-identity `token_file`) | The projected OIDC token path does not exist | Confirm the `token_file` path (the IRSA / EKS Pod Identity projection) is mounted and readable |
| `Faraday::ConnectionFailed` / `Faraday::TimeoutError` | The OAuth2 / web-identity `token_url` is unreachable or slow | Check upstream IdP availability; the token endpoint must answer 2xx (a 3xx degrades — token endpoints are dispatched `max_redirects: 0`) |

> A brokering fault that escapes the broker's own rescue (it shouldn't) is caught one level up and logged as `[DataSources::QueryService] credential brokering failed (using base) for <slug>: <class>` — same fail-open outcome, different prefix. If you see *that* line, the broker's internal rescue was bypassed (a bug); capture it.

**`outcome=skipped reason=<reason>`** — the broker decided it could not proceed (a precondition was missing) and returned base **without** attempting an exchange. These are configuration gaps, not faults:

| `reason` | Broker(s) | Meaning / fix |
|----------|-----------|---------------|
| `missing_base_aws_keys` | `aws_sts`, `presigned_url` (s3) | The base credential carries no `decrypted_api_key` / `decrypted_api_secret` to call STS / presign with. Attach AWS keys to the source's base credential |
| `missing_web_identity_token` | `aws_sts_web_identity` | None of `web_identity_token` / `token_file` / `token_url` resolved a token. Provide exactly one token source |
| `no_vault_path` | `vault_dynamic` | `config["vault_path"]` is blank. Set the dynamic mount path (e.g. `aws/creds/s3-reader`) |
| `no_account` | `vault_dynamic` | `data_source.account` is nil — the Vault integration is account-scoped. Ensure the source is account-bound |
| `empty_lease` | `vault_dynamic` | Vault returned an empty/unusable response for the path (sealed, wrong mount, no policy). Check Vault status + the mount path + the token's policy |
| `missing_bucket_or_key` / `missing_region` | `presigned_url` (s3) | Required S3 presign config absent. Set `bucket`, `object_key`, and `region` |
| `missing_azure_params` | `presigned_url` (azure_sas) | One of account name / account key / `container` / `blob` is missing. Provide all four |
| `unknown_provider` | `presigned_url` | `config["provider"]` is neither `s3` nor `azure_sas`. Fix the provider token |

General degrade workflow:

1. Find the `skipped`/`error` line for the source (`grep 'source=<slug>'`) and read its discriminating field (`reason=` or `error_class=`).
2. For `skipped` → fix the named config gap in `auth_config["broker"]` (and the base credential for the `missing_*_keys` reasons).
3. For `error` → resolve the upstream/identity cause per the table; the message is intentionally withheld, so reproduce against the authority directly (STS/IdP/Vault) if the class alone is ambiguous.
4. After fixing, **flush the broker cache** (next section) so the next fetch re-attempts the exchange and logs a fresh `outcome=acquired` rather than serving a stale degrade decision. (A *degrade* is never cached — only successful material is — but flushing forces an immediate logged mint to confirm the fix.)

### The short-lived credential cache (`ds_cred_broker:*`)

Brokered material is cached in **Redis** (the shared client, via `Powernode::Redis.client`) so a swarm hitting expiry does not hammer STS / the token endpoint / the Vault dynamic engine. `BrokerCache` is the owner:

- **Key namespace** — `ds_cred_broker:` (`BrokerCache::NAMESPACE`). The value key is `ds_cred_broker:<digest>` where `<digest>` is a broker-built, **non-secret** stable key (broker type + source id + a one-way SHA-256 fingerprint of the base credential, so **rotating the base secret naturally busts the cache**). A SETNX singleflight **lock** lives alongside at `ds_cred_broker:lock:<key>` (TTL `LOCK_TTL = 10`s) so only one worker mints per key per window — a contended caller computes its own copy **without sleeping** (Kernel#sleep is forbidden in this pipeline) rather than blocking.
- **TTL** — the entry is cached for `(lease − skew)` seconds (`ttl_with_skew`), floored at `MIN_TTL = 5`s. The absolute expiry is also embedded **inside** the cached material (as an ISO8601 string) so a cache HIT can still reconstruct `BrokeredCredential#expires_at`. A broker that returns `ttl_seconds <= 0` signals **uncacheable** (e.g. a Vault lease with no advertised duration) — the material is used but not stored, so the next fetch re-acquires.
- **Fail-open** — any Redis error (read, write, or lock) degrades to "compute once, return uncached". A cache outage never breaks the fetch; you'll just see an `outcome=acquired` on *every* request instead of one per lease.

Inspect and flush:

```bash
# List all brokered-credential cache + lock keys (values are short-lived secret
# material — DO NOT GET them in a shared shell; the key names are non-secret).
redis-cli --scan --pattern 'ds_cred_broker:*'

# How long until a given entry expires (forces re-acquisition when it lapses).
redis-cli TTL 'ds_cred_broker:<digest>'

# Force re-acquisition of ONE source's brokered credential: delete its value key(s).
# The next governed fetch misses the cache, re-runs the exchange, and logs outcome=acquired.
redis-cli --scan --pattern 'ds_cred_broker:*' | xargs -r -n1 redis-cli DEL

# Drop a stuck singleflight lock (self-expires in 10s anyway; only needed to force
# an immediate re-mint after a crashed acquirer).
redis-cli DEL 'ds_cred_broker:lock:<key>'
```

> **Which key belongs to which source?** The digest is a one-way hash and is **not** reversible to a source — there is no slug in the key. To force re-acquisition for a single source without flushing the whole namespace, **rotate its base credential** (which changes the fingerprint and orphans the old entry to expire on its own), or flush the whole `ds_cred_broker:*` namespace (cheap — every source just re-mints once on its next fetch). Use the audit line (`outcome=acquired source=<slug>`) to confirm the re-mint landed on the source you intended.

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `outcome=acquired` logs on **every** request (no caching) | Redis unreachable (fail-open ⇒ compute-uncached), **or** the broker returns `ttl_seconds <= 0` (uncacheable lease, e.g. Vault with no `lease_duration`) | Check Redis connectivity; for Vault, confirm the dynamic engine advertises a lease (else it is re-read each fetch by design) |
| Stale credential served after the upstream revoked it | The cached lease has not yet lapsed (cached for `lease − skew`) | Flush the source's `ds_cred_broker:*` entry to force a fresh mint; raise `skew_seconds` so the cache is dropped earlier before real expiry |
| First request after a fix still degrades | A *successful* prior mint is cached — but a degrade is never cached, so this is the cache serving the **old good** material, or the warm lease pre-dates the fix | Flush `ds_cred_broker:*`; the next fetch re-mints and logs `outcome=acquired` |
| Thundering herd of token/STS calls at expiry | Singleflight lock not engaging (Redis lock errors fail to the contended path) | Check Redis health; the contended path computes-without-caching, so a Redis fault degrades singleflight to a brief duplicate-compute (bounded, not a storm) |

### The SSRF guard rejecting a `token_url`

Only the brokers that fetch a **config-supplied URL** make outbound HTTP during acquisition — `oauth2_client_credentials` (the OAuth2 `token_url`) and `aws_sts_web_identity` (when it sources the OIDC token from a `token_url`). Because that URL is **operator config**, it MUST go through `BaseBroker#broker_http_connection`, which is the SSRF-guarded Faraday connection: it calls `HttpConnectionFactory.validate_url!` (resolve-and-pin, fail-fast before any socket opens) and carries `SsrfGuardMiddleware` (re-validates the exact target per request) plus a redirect callback that re-pins every hop. The AWS STS SDK calls and the S3/Azure presigners hit **fixed** endpoints and have no SSRF surface (and deliberately do **not** honor a config endpoint override).

`validate_url!` raises `Ai::DataSources::HttpConnectionFactory::SsrfError` when the URL:

- uses a disallowed scheme (anything but http/https → `Disallowed URL scheme`),
- has no host, fails to resolve, or
- resolves to **any** private / loopback / link-local address (the classic `token_url -> 169.254.169.254` IMDS-rebinding attempt → `URL resolves to a disallowed (private/loopback/link-local) address`).

The `SsrfError` propagates out of the broker's exchange and is caught by `BaseBroker#acquire`, so it surfaces as **`outcome=error error_class=Ai::DataSources::HttpConnectionFactory::SsrfError`** and the fetch **degrades to base** — it is never a hard failure, and the rejected URL is never dispatched.

```bash
# Catch SSRF rejections of a broker token_url specifically.
journalctl -u powernode-backend@default --since "1 hour ago" \
  | grep -E 'outcome=error error_class=.*SsrfError'
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `outcome=error error_class=…SsrfError` on an OAuth2 / web-identity source | The `token_url` resolves to a private/loopback/link-local address or uses a non-http(s) scheme | Point `token_url` at a public, resolvable HTTPS IdP endpoint; verify DNS does not resolve it to `169.254.169.254` / RFC-1918. This is the guard working as intended — never bypass it |
| OAuth2 broker degrades but the IdP is public and healthy | The token endpoint answered a **3xx** (dispatched `max_redirects: 0`, so a redirect parses as non-2xx ⇒ degrade), preventing a `client_secret` replay to the redirect target | Use the IdP's canonical token URL that returns 2xx directly; a token endpoint should never redirect |
| Want to send the token request through a private/internal minter | Not supported by design — the guard blocks private targets to close the SSRF/DNS-rebinding hole | Expose the minter on a public, resolvable host, or use `token_file` / inline `web_identity_token` (file/inline sources bypass the URL fetch entirely) |

### Security posture

The brokering layer mirrors the data-source pipeline's `sign_request!` discipline and is **non-negotiable**:

- **Short-lived material in Redis, never logged.** The cached value is ephemeral, account/source-scoped secret material that expires automatically. It is **never** written to a log — only the **non-secret cache KEY** (a one-way digest) and the **outcome** appear. Audit lines carry only `broker=` / `source=` / `outcome=` / `expires_at=` / `reason=` / `error_class=` — never a token, secret, `session_token`, `client_secret`, or any key material.
- **No secrets in error paths.** Rescue blocks log `e.class` **only** — an exception message from an HTTP client or the AWS SDK can echo request material, so the message is deliberately withheld everywhere.
- **`BrokeredCredential` is leak-proof.** It is frozen on construction, its material Hash is duplicated and read-only, and `#inspect` / `#to_s` are **redacted** (they print field *names* and the expiry, never values) so a token cannot escape through a `raise cred`, `pp cred`, or string interpolation in a trace.
- **SSRF-guarded outbound, fixed AWS endpoints.** Every config-supplied URL is validated (above); AWS SDK calls and presigners use fixed/regional AWS endpoints with **no** config override, so there is no acquisition-time SSRF surface. (A *presigned* URL is fetched later by `QueryService` through the same SSRF-guarded connection, where its host is validated like any other fetch.)
- **No long-lived key generation.** Brokering never generates or persists long-lived key material — it only *exchanges* an existing base secret for a short-lived one. Base secrets continue to live encrypted in Vault / the credential store per [Cryptographic Material Safety](../../CLAUDE.md); the broker reads them via `decrypted_api_key` / `decrypted_api_secret` inside the service only.

## Query-time governance (Phase 4b-2b)

Phase 4b-2b adds a **per-request governance overlay** to the governed fetch — invoked from `QueryService` between the quota gate and the cache lookup — with two independent responsibilities, both implemented in `Ai::DataSources::GovernanceService` over **existing** policy infrastructure (it invents no new models):

1. **Authorize** (`#authorize`) — decide whether *this* principal may read *this* source right now, combining **per-agent ABAC** (`Ai::AgentPrivilegePolicy`) with **account-level data-access compliance** (`Ai::CompliancePolicy` of type `data_access`: residency / consent / usage). A deny short-circuits to a **`blocked`** envelope *before* any cache read or upstream dispatch (mirroring the kill-flag / SSRF short-circuit).
2. **Mask** (`#mask_records`) — redact PII/secret string values out of the response records at the single envelope-finalization chokepoint, using the shared `Ai::Security::PiiRedactionService`.

> **Posture: fail-OPEN on infra error, DENY on explicit policy.** A policy-engine **bug** (an exception while resolving/evaluating policies) rescues to `allowed: true` and logs the **class only** — governance is an overlay on a read path the controller already authorized for the human, so an internal fault degrades to "allow + log", never "hard-fail every query". An **explicit** policy decision is the opposite: an applicable privilege policy that lists the resource under `denied_resources`, or a **blocking** compliance policy returning `allowed: false`, yields `allowed: false`. Infra error ⇒ open; explicit deny ⇒ closed.

> **Zero-overhead default.** A **user/system** fetch (no agent) of a source with **no** `metadata.governance` config skips ALL policy resolution and allows — byte-for-byte the pre-4b-2b path. Agent-initiated fetches and governance-configured sources run the full check (so account-wide `data_access` compliance applies to every agent read). ABAC is **default-allow / deny-on-explicit**: a resource that no applicable policy mentions (absent from both `allowed_resources` and `denied_resources`, no wildcard) is **allowed** — a read is denied **only** when an applicable policy explicitly lists `data_source:<id>` (or `"*"`) under `denied_resources`.

### A query returning 403 / "blocked by ... policy" — ABAC vs compliance

A governance deny surfaces as a **`blocked`** FetchEnvelope (`success: false`, `status: "blocked"`), persisted as a blocked query-log row with **no upstream dispatch and no cache read**. The `governance_blocked` anomaly is appended and the decision is recorded on **`provenance.policy_decision`**:

```jsonc
{
  "success": false,
  "status": "blocked",
  "error": "Privilege policy 'agent-data-fence' denies data_source:0192…",
  "provenance": {
    "anomalies": ["governance_blocked"],
    "policy_decision": {
      "allowed": false,
      "reason": "Privilege policy 'agent-data-fence' denies data_source:0192…",
      "enforcement": "block"
    }
  }
}
```

> **First, separate governance from egress.** A governance block carries the `governance_blocked` anomaly **and** a `provenance.policy_decision` object. The **SSRF egress** block (a different gate) has `error: "request blocked by egress policy"` with **no** `policy_decision` — see [SSRF guard](#the-ssrf-guard-rejecting-a-token_url) / the fetch-pipeline runbook. If there is no `policy_decision`, it is not governance.

**Read the `reason` to tell ABAC from compliance** — the two paths produce structurally different strings:

| Path | `reason` shape | `enforcement` | Side effect |
|------|----------------|---------------|-------------|
| **ABAC** (per-agent privilege) | `Privilege policy '<policy_name>' denies data_source:<id>` | `"block"` | None recorded — the deny is computed from `denied_resources`, no violation row |
| **Compliance** (`data_access`) | `decision[:reason]` from the policy's own `#evaluate` (e.g. a residency/consent message), else `Compliance policy '<name>' denied access` | `decision[:enforcement]` or `"block"` | **Records an `Ai::PolicyViolation`** (`severity: "high"`, `status: "open"`, `source_type: "data_source"`, `source_id: <id>`) via `CompliancePolicy#record_violation!` |

So the discriminator is the recorded violation: an **ABAC** deny leaves no `Ai::PolicyViolation`; a **compliance** deny always writes one. Check both:

```bash
# 1. The deny itself — read provenance.policy_decision off the most recent query-log
#    row (a governed fetch returns it inline; MCP exposes it on the provenance read).
#    platform.data_source_query  data_source_id: ":id"  endpoint_id: ":ep"
#    → .provenance.policy_decision  (reason / enforcement) + .provenance.anomalies

# 2. Was a compliance violation recorded? (compliance deny ⇒ yes; ABAC deny ⇒ no)
#    platform.governance_dashboard          # open violations across policies
#    platform.list_governance_reports       # or scope a scan
```

```ruby
# rails runner — the authoritative ABAC-vs-compliance check for one source + agent.
ds    = Ai::DataSource.for_account(account).find_by!(slug: "open-meteo")
agent = Ai::Agent.find("<agent_id>")
decision = Ai::DataSources::GovernanceService
             .new(data_source: ds, agent: agent, account: account)
             .authorize
# => { allowed: false, reason: "...", enforcement: "block" }

# Compliance deny leaves a high-severity violation row; ABAC deny does NOT.
Ai::PolicyViolation.for_source("data_source", ds.id).recent.limit(5)
  .pluck(:detected_at, :severity, :status, :description)
```

**Granting access** — fix whichever layer denied:

| Deny path | How to grant |
|-----------|--------------|
| **ABAC** — `Privilege policy '<name>' denies …` | Remove `data_source:<id>` (and any `"*"`) from that `Ai::AgentPrivilegePolicy`'s **`denied_resources`** for the agent's trust tier. Under default-allow, simply *not denying* is enough — you do **not** need to add it to `allowed_resources`. Confirm with `AgentPrivilegePolicy.applicable_to(agent.id, trust_tier)` that no *other* applicable policy still denies it |
| **Compliance** — blocking `data_access` policy | The policy genuinely rejected the **context** (region/residency/consent). Either satisfy the condition (set the source's `metadata.governance.region` / `residency` correctly, or supply the missing consent context), or — if the policy should not apply here — narrow its `applies_to` (`types`/`tags`) or set it non-blocking (`enforcement` log/warn) so it advises instead of blocks. After resolving, mark the recorded `Ai::PolicyViolation` `resolved!`/`dismissed!` |

> **Trust tier drives which ABAC policies apply.** `applicable_to(agent_id, trust_tier)` is filtered by the agent's resolved tier (`autonomous` ≥ 0.9 / `trusted` ≥ 0.7 / `monitored` ≥ 0.4 / `supervised` ≥ 0.0, mirroring `Ai::AgentTrustScore`). A missing/altered trust signal resolves to the most restrictive `supervised`, so a deny that only appears for a low-trust agent is expected — raising the agent's trust score (or scoping the deny to specific tiers) changes the applicable set.

### Masking — fields coming back `[REDACTED:...]`

When response fields arrive as `[REDACTED:<type>]` (e.g. `[REDACTED:email]`, `[REDACTED:jwt_token]`, `[REDACTED:bearer_token]`), **egress masking is ON** for the source. Masking is an **explicit opt-in** via `metadata.governance` — it is OFF (passthrough) unless one of:

- `metadata.governance.mask` is truthy (`true` / `"true"` / `"1"` / `"yes"` / `"on"`), **or**
- `metadata.governance.mask_at_classification` is present.

A bare `metadata.governance.classification` label does **not** by itself enable masking — labeling a source's sensitivity and stripping values from its payload are separate decisions.

When on, `GovernanceService#mask_records` deep-walks every Hash/Array and runs `PiiRedactionService#redact(log: false)` on every **string value** — which strips **every** detected PII/secret pattern (email, JWT, bearer token, AWS keys, private-key headers, SSN/DOB/MRN, generic api-key, etc.), not a classification-threshold subset. **Keys are never masked; non-string scalars are untouched.** The placeholder is `[REDACTED:%{type}]` (the `type` is the detected pattern name). The per-fetch outcome lands on **`provenance.masking_applied`** (bool) and **`provenance.masked_field_count`** (int), and is mirrored onto the persisted query-log row (`masking_applied` / `masked_field_count`).

Inspect whether/why masking ran:

```bash
# The masking flags ride on every governed-fetch envelope's provenance.
#   platform.data_source_query  data_source_id: ":id"  endpoint_id: ":ep"
#   → .provenance.masking_applied   (true ⇒ masking ran)
#     .provenance.masked_field_count (how many string values were replaced)
```

```ruby
# rails runner — read the source's masking config directly.
ds = Ai::DataSource.for_account(account).find_by!(slug: "people-api")
ds.metadata["governance"]          # => { "mask" => true, "classification" => "pii", ... }
                                    #    string OR symbol keys are tolerated
```

**Disabling / changing masking** — edit `metadata.governance` on the source. To turn it **off**, remove the opt-in markers (set `mask` falsey AND clear `mask_at_classification`); a leftover `classification` alone will not re-enable it:

```bash
# Turn masking OFF (preserve any other metadata; this overwrites metadata wholesale,
# so include the keys you want to keep). PATCH requires ai.data_sources.update.
curl -s -X PATCH -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{"data_source":{"metadata":{"governance":{"mask":false}}}}' \
  https://api.powernode.example.com/api/v1/ai/data_sources/:id
```

> **The cache holds RAW — toggling masking takes effect on the very next request.** `QueryService` caches the **unmasked** records; masking is computed per-request at envelope finalization (the cache write and the audit row consume RAW `result[:data]`, the returned envelope carries the MASKED copy). So flipping `metadata.governance.mask` needs **no cache flush** — the next fetch (even a cache *hit*) re-derives masking from the new config. This is also why the same cached payload can be masked differently per requester/policy without poisoning the shared entry.

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Fields unexpectedly `[REDACTED:…]` | `metadata.governance.mask` truthy (or `mask_at_classification` set) | Read `provenance.masking_applied`; edit `metadata.governance` to disable — effective next request (no flush) |
| Toggled `mask` off but still redacted | Edited the wrong key, or `mask_at_classification` is still set (it *also* enables masking) | Clear **both** `mask` and `mask_at_classification`; a bare `classification` does not enable masking |
| Masking on but `masked_field_count: 0` | No values matched a PII/secret pattern — the payload had nothing to redact | Expected; redaction is pattern-driven, not "redact every field" |
| `provenance.masking_applied: false` despite `mask: true` | A masking **fault** degraded to passthrough (fail-open on availability, flagged) — logged `masking error (<class>)` | Check the backend log for `[DataSources::GovernanceService] masking error`; the data was served **unmasked** and flagged so you can detect it |
| Huge payload only partially masked | Hit `MAX_MASKED_VALUES = 50_000` — masking is capped per response | Logged `masking capped at 50000 values`; narrow the endpoint `response_mapping` so the payload (and PII surface) is smaller |

### mTLS troubleshooting (outbound client certificates)

A source can present an **outbound client certificate** on its upstream fetches via `data_source.configuration["mtls"]` (read by `Ai::DataSources::HttpConnectionFactory`, **not** the governance service — `GovernanceService` only surfaces `mtls: <present?>` into the compliance context for residency conditions). It is **OFF by default**: with no `configuration["mtls"]` block (or `enabled` falsey) the Faraday connection carries **no `ssl:` key** and is byte-for-byte the pre-mTLS build. The cert/key/CA are **never in the config** — config holds only a Vault **reference**:

```jsonc
"mtls": {
  "enabled":     true,            // off unless truthy
  "required":    false,           // true => fail CLOSED on any load error
  "vault_path":  "secret/data/…", // explicit Vault KV path (preferred)
  "credential_id": "<uuid>",      // OR convention lookup (account scope + id)
  "cert_key":    "cert_pem",      // field name in the Vault secret (default cert_pem)
  "key_key":     "key_pem",       // field name in the Vault secret (default key_pem)
  "ca_key":      "ca_pem"         // optional CA-chain field (default ca_pem)
}
```

**`required: true` + bad/missing Vault material ⇒ `MtlsConfigError`.** When `enabled` and `required` are both set, a missing secret, missing `cert_pem`/`key_pem` fields, or malformed PEM raises `Ai::DataSources::HttpConnectionFactory::MtlsConfigError` rather than silently attempting an unauthenticated TLS handshake. The message is deliberately **non-secret** (no path, no key, no cert bytes) — one of:

- `mTLS is required for this data source but no client certificate is configured` (Vault returned nothing usable),
- `mTLS is required for this data source but the client certificate could not be loaded` (Vault read / lookup raised — the underlying class is logged, never the message),
- `mTLS is required for this data source but the client certificate is invalid` (PEM parse failed — `OpenSSL::PKey::PKeyError` / `OpenSSL::X509::CertificateError`).

`MtlsConfigError` propagates out of the connection build through `QueryService#perform_fetch`'s catch-all rescue, surfacing as a normal **`error`** FetchEnvelope (`status: "error"`) with the non-secret message — *not* a `blocked` envelope and *not* a raw 500.

**`required: false` (or unset) ⇒ optional-degrade.** The same load failures **silently return `{}`** (no client cert) and the fetch proceeds over **plain TLS** — there is no `MtlsConfigError`, no envelope error attributable to mTLS, and only an `Rails.logger.error("[DataSources::HttpConnectionFactory] mTLS setup failed: <class>")` (class only). So an `enabled: true, required: false` source whose Vault material is broken will *appear to work* while never actually presenting a client cert — if the upstream then rejects the unauthenticated request you will see a downstream auth/TLS error, **not** an mTLS one. **Set `required: true` whenever the upstream truly mandates mTLS**, so a material fault fails loud instead of degrading.

> **`cache: false` is a hard guarantee — the private key is NEVER in Redis.** `read_vault_secret` reads the Vault secret with `cache: false`, so a client **private key** is never written to `Rails.cache` (Redis / Solid Cache). It is read **fresh from Vault per connection build** (mTLS is rare and the connection is short-lived), honoring the absolute vault-only-storage rule for key material. The loaded key becomes an in-memory `OpenSSL::PKey` that is never logged or stringified; an optional CA chain is written to a per-process, content-deduplicated tempfile (Faraday's `ssl.ca_file` wants a path) whose handle is retained for the process lifetime. **Do not** try to "warm" or cache the cert — there is no cache entry to inspect, and that is by design.

**Where the cert/key live (Vault).** The material lives **only in Vault**, resolved one of two ways:

- **`vault_path`** (preferred) — read directly via `::Security::VaultClient.read_secret(vault_path, cache: false)`. The secret is expected to carry `cert_pem` / `key_pem` (and optional `ca_pem`) fields, overridable via `cert_key` / `key_key` / `ca_key`.
- **`credential_id`** (convention) — when no `vault_path`, falls back to `::Security::VaultCredentialProvider.new(account_id:).get_credential(credential_type: :data_source, credential_id:)`. Requires **both** the source's `account_id` and the `credential_id` (else it resolves to nil ⇒ the required/optional branch above).

Per [Cryptographic Material Safety](../../CLAUDE.md), do **not** generate or echo the cert/key via CLI — store the PEM material into Vault out-of-band (UI/API/Vault directly) and reference it by `vault_path` / `credential_id` here.

```bash
# An mTLS-required source failing surfaces as a normal error envelope with the
# non-secret message — confirm it is mTLS (not a generic upstream error):
#   platform.data_source_query  data_source_id: ":id"  endpoint_id: ":ep"
#   → .error  contains "mTLS is required for this data source but …"

# The class-only setup-failure log (no path/key/cert ever appears here):
journalctl -u powernode-backend@default --since "15 minutes ago" \
  | grep -E '\[DataSources::HttpConnectionFactory\] mTLS (setup failed|material is invalid)'

# Verify the referenced Vault secret carries the cert/key fields (run where Vault
# is reachable; NEVER print the values — list field names only).
vault kv get -format=json <vault_path> | jq '.data.data | keys'
#   → expect ["ca_pem","cert_pem","key_pem"]  (or your cert_key/key_key/ca_key names)
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Fetch errors with `mTLS is required … no client certificate is configured` | `required: true` but Vault returned nothing usable (wrong `vault_path`, sealed Vault, no policy, or `credential_id`/`account_id` missing) | Verify the `vault_path` (or `credential_id` + the source is account-bound); confirm Vault is unsealed and the token's policy can read the path |
| Fetch errors with `… could not be loaded` | `required: true` and the Vault read/lookup **raised** (transport, auth, policy) | The underlying class is in the `mTLS setup failed: <class>` log; resolve the Vault access cause (the message is intentionally withheld) |
| Fetch errors with `… is invalid` | `required: true` and the PEM failed to parse (truncated cert, non-PEM `key_pem`, wrong field mapping) | Check the secret's `cert_pem`/`key_pem` fields are valid PEM; if an exporter prepended metadata lines they are stripped, but a genuinely malformed key still fails — re-store clean PEM |
| Upstream rejects the request but **no** mTLS error appears | `required: false` (or unset) and the material is broken ⇒ **optional-degrade** to plain TLS (silent) | Look for `mTLS setup failed: <class>` in the backend log; set `required: true` so the fault fails loud, then fix the Vault material |
| Suspect the private key is cached somewhere | It is not — `read_vault_secret` uses `cache: false`; the key is read fresh per build and only held in-memory | Nothing to flush; if you need a fresh read, the next fetch already re-reads Vault (no warm cache exists) |
| mTLS "stopped working" after a cert rotation | The new PEM is in Vault but the source still references the old `vault_path`/secret, or the rotated secret renamed the fields | Point `vault_path`/`credential_id` at the rotated secret; confirm the field names match `cert_key`/`key_key`/`ca_key` (no cache to bust — reads are live) |

## Retrieval transforms, dry-run estimates & cache-tag invalidation (Phase 4b-3a)

Phase 4b-3a adds three operator-facing capabilities to the governed fetch, all **OFF / no-op by default** so the live path is byte-for-byte unchanged until used:

1. A per-endpoint **config-driven transform pipeline** (`Ai::DataSources::TransformService`) that reshapes the canonical records *between* normalization and the cache write — so the cached, persisted, and masked payload **IS** the transformed shape.
2. A **dry-run** mode on `Ai::DataSources::QueryService` that short-circuits before any upstream call and returns a pre-execution **cost / row estimate** instead of data.
3. **Surrogate-key (tag) cache invalidation** in `Ai::DataSources::ResponseCacheService`, plus an MCP action (`data_source_invalidate_cache`) to drive it.

### A response changed shape — the config-driven transform pipeline

When an endpoint's returned/cached records look different from the raw upstream payload — flattened dotted keys, fewer/renamed fields, one row per array element, an extra computed field — a **transform pipeline** is configured on that endpoint. The pipeline is an ordered list of steps (`flatten` / `unnest` / `select` / `rename` / `computed`) stored in `ai_data_source_endpoints.transforms` (jsonb, default `{}`), shape `{ "pipeline" => [ {op, ...}, ... ] }`, applied **in order** by `TransformService` after `NormalizationService` and **before** the response-cache write.

**How to tell whether (and how) transforms ran** — two signals ride on the FetchEnvelope's `provenance`, mirrored onto the persisted `ai_data_source_queries` row:

- **`provenance[:transforms_applied]`** (bool) — `true` when the endpoint declared a non-empty pipeline and it executed; `false` when the endpoint has no pipeline (`transforms?` false ⇒ records passed through byte-for-byte) **or** the pipeline aborted and degraded to the untransformed records.
- **`provenance[:record_count]`** — the **post-transform** row count. `record_count` is computed *after* `apply_transforms` reassigns the working set, so it is honest: an `unnest`/`explode` step inflates it, a filtering pipeline shrinks it. A `record_count` that does not match the raw upstream element count is the first clue a pipeline is reshaping the payload.

```bash
# Read both signals off the most recent governed fetch. (data_source_query returns
# the envelope verbatim; data_source_provenance reads the persisted row.)
#   platform.data_source_query  data_source_id: ":id"  endpoint_id: ":ep"
#   → .provenance.transforms_applied   (true ⇒ the pipeline ran)
#     .provenance.record_count         (POST-transform row count)
```

```ruby
# rails runner — read the endpoint's configured pipeline directly.
ep = Ai::DataSourceEndpoint.find("<endpoint_id>")
ep.transforms?            # => true when a non-empty "pipeline" is configured
ep.transforms["pipeline"] # => the ordered [ {op, ...}, ... ] steps
```

**Transforms run PRE-CACHE — a config change needs a cache invalidation to take effect.** This is the operationally critical consequence: because `TransformService` runs before the cache write, the cache holds the **already-transformed** shape. So editing an endpoint's `transforms` config does **NOT** retroactively reshape what is already cached — every cache **hit** keeps serving the OLD shape until the entry expires (or is regenerated). After changing `transforms`, **invalidate the endpoint's cache** (see [Cache-tag invalidation operations](#cache-tag-invalidation-operations)) so the next fetch is a miss, re-runs the new pipeline, and re-caches the new shape.

> **Contrast with masking (Phase 4b-2b), which is per-request and needs NO flush.** Governance masking is computed *after* the cache (the cache holds RAW, the masked copy is derived per request), so toggling `metadata.governance.mask` takes effect on the very next request — even a cache hit. Transforms are the opposite: they are baked **into** the cached payload, so a `transforms` change is invisible until the cached shape is invalidated and regenerated. When a config edit "didn't take," check which one you changed.

**Resilience (why a fetch never breaks on a bad pipeline).** `TransformService` is pure/stateless (no DB/Redis/network) and fully rescued: a malformed *step* is skipped (logged at warn) and the records flow through unchanged; a pipeline-level fault returns the best-effort records. `QueryService#apply_transforms` wraps that in a second rescue (defense in depth) that, on any fault, returns the **untransformed** records with `transforms_applied:false` and appends a **`transform_error`** anomaly. So a broken config degrades to "serve untransformed + flag," never a hard failure.

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Cached/returned records have an unexpected shape (dotted keys, dropped/renamed fields, exploded rows) | The endpoint declares a `transforms` pipeline | Read `ep.transforms["pipeline"]`; `provenance.transforms_applied:true` confirms it ran |
| Edited `transforms` but the shape didn't change | The OLD shape is still cached (transforms run pre-cache) | **Invalidate the endpoint's cache** (tag `endpoint:<id>` or scope by endpoint) so the next fetch re-runs the pipeline and re-caches |
| `record_count` far larger than the raw payload | An `unnest`/`explode` step is fanning out array elements (capped at `MAX_RECORDS = 50_000`; overflow dropped + logged) | Expected for explode; if it hit the cap, look for `unnest capped output at 50000 records` in the backend log |
| `provenance.transforms_applied:false` but a pipeline IS configured + `transform_error` anomaly present | A transform fault degraded to untransformed records | Check the backend log for `[DataSources::TransformService]` (step/pipeline) or `[DataSources::QueryService] transform pipeline failed` (class + message); fix the offending step |
| A step in the pipeline appears to do nothing | An **unknown `op`** (or unknown `computed` inner op) is a no-op — it is skipped and a debug line is logged, never executed | Verify the op token against the supported set (`flatten`/`unnest`/`select`/`rename`/`computed`); the `computed` interpreter is whitelisted — no arbitrary code runs from config |

### Estimating cost before enabling a costly source (dry-run)

Before flipping on a metered/expensive source (or before letting agents loose on it), use **dry-run** to get a pre-execution **cost and row estimate** without making the upstream call. Dry-run is a constructor flag on `QueryService` (`dry_run: true`) that **short-circuits the pipeline AFTER the kill-flag, quota, and governance gates** (so a dry-run respects exactly the same permissions a live read would — a denied read never gets an estimate) but **BEFORE** any cache lookup, credential resolution, signing, upstream dispatch, or cache write. It performs **no side effects**: it persists nothing (the `"dry_run"` status is deliberately *not* a `DataSourceQuery::STATUSES` member, so it never reaches a query-log row) and writes nothing to the cache.

> **Scope:** dry-run is currently a **service-level** flag, invoked from Ruby (e.g. `rails runner`), not yet a parameter on the MCP `data_source_query` action (that action constructs `QueryService` without `dry_run:`). Drive it from the service directly:

```ruby
# rails runner — estimate a fetch's cost/rows WITHOUT calling upstream.
ds    = Ai::DataSource.for_account(account).find_by!(slug: "metered-api")
ep    = ds.endpoints.find_by!(slug: "expensive-endpoint")
env   = Ai::DataSources::QueryService.new(
          data_source: ds, endpoint: ep, params: { ... },
          agent: nil, user: nil, dry_run: true
        ).call

env[:status]                       # => "dry_run"
env[:data]                         # => []  (no data fetched)
env[:provenance][:anomalies]       # => ["dry_run"]
est = env[:provenance][:estimate]
#   {
#     would_fetch:         true|false,   # false when a FRESH cache hit exists
#     from_cache:          true|false,   # mirror of a fresh cache hit being available
#     source_url:          "<REDACTED>", # would-be URL, built pure then redacted
#     http_method:         "GET",
#     estimated_cost_usd:  0.0012,       # see pricing below
#     estimated_rows:      <int|nil>,    # avg rows over recent NON-cached successes
#     cache_hit_available: true|false
#   }
```

**Reading the estimate:**

- **`estimated_cost_usd`** prices the would-be fetch the same way `Ai::CostAttribution` prices a real one: when the source declares `configuration["cost_per_request_usd"]` / `cost_per_gb_usd`, it uses `per_request + per_gb * avg_GB` (the GB term from the **average historical transfer size** over the last `DRY_RUN_HISTORY_SAMPLE = 20` successful, **non-cached** queries for that endpoint). With no cost config it falls back to the average historical `actual_cost_usd`, and finally to `0.0` on a cold source with neither config nor history.
- **`estimated_rows`** is the average `rows_returned` over those same recent non-cached successes; `nil` on a cold endpoint. (Note: a transform pipeline that explodes/filters means the *live* row count may differ — the estimate reflects historical post-transform counts.)
- **`would_fetch` / `cache_hit_available`** — `cache_hit_available:true` (so `would_fetch:false`) means a **fresh** (not-hard-expired) cache entry exists right now, so a live call would be served from cache and incur **no** upstream cost. The probe uses `ResponseCacheService.read_stale` (not `read`) specifically so it reads the `hard_expired` flag **without** counting a hit/miss in the cache metrics — a dry-run never pollutes the hit-rate.
- A cold source (no history) still returns a well-formed estimate with `estimated_cost_usd: 0.0` / `estimated_rows: nil` — absence of history degrades gracefully, it does not error.

Use it as a gate: dry-run an endpoint, read `estimated_cost_usd` × your expected call volume, and decide whether to set `is_active: true` / grant agents access. Because dry-run runs the **governance gate**, it also doubles as a cheap "would this principal even be allowed?" probe — a `blocked` envelope (not a `dry_run` one) means the read is denied before cost is ever a question.

### Cache-tag invalidation operations

Every cached response is **tag-addressable**. On write, `ResponseCacheService` indexes each entry's cache key into one or more **surrogate-key** Redis SETs (`data_source_cache:tag:<tag>`), so a whole tag can be invalidated in one shot without a keyspace SCAN. When the writer supplies no explicit tags, the entry is auto-tagged with `default_tags` so **every** entry is reachable by:

- **`ds:<data_source_id>`** — every cached entry for the source,
- **`endpoint:<endpoint_id>`** — every entry for one endpoint (across param variants),
- **`slug:<endpoint_slug>`** — same endpoint, addressed by slug.

**Two invalidation surfaces:**

- **By tag** — `ResponseCacheService.invalidate_by_tag(tag)` deletes every cache key recorded in that tag's SET, then drops the (now-stale) index SET. Returns the count invalidated (the index SET's own deletion is not counted). A blank/unknown tag invalidates nothing and returns `0`.
- **By scope** (prefix delete, SCAN-based) — `ResponseCacheService.invalidate(data_source:, endpoint:)`: with an endpoint it clears that endpoint's variants (`data_source_cache:<ds_id>:<slug>:*`); with the source alone it clears **all** of the source's entries (`data_source_cache:<ds_id>:*`).

**The `data_source_invalidate_cache` MCP action** drives both. It is an **operational write** gated by **`ai.data_sources.update`** (`ai.data_sources.manage` also satisfies it). Unlike the model-mutation actions (create/update/delete), it does **not** file a proposal when unauthorized — it **hard-denies**, because invalidation is idempotent and fully recoverable (the next fetch just re-populates). Precedence: **a `tag` takes priority over scope**; otherwise `data_source_id` (+ optional `endpoint_id`) selects the scope.

```bash
#   platform.data_source_invalidate_cache  tag: "endpoint:<endpoint_id>"
#     → { scope: "tag", tag: ..., invalidated: <n> }     # one endpoint, all variants
#
#   platform.data_source_invalidate_cache  data_source_id: ":id"  endpoint_id: ":ep"
#     → { scope: "endpoint", invalidated: <n> }           # scope (prefix) delete
#
#   platform.data_source_invalidate_cache  data_source_id: ":id"
#     → { scope: "data_source", invalidated: <n> }        # whole source
```

The most common trigger is the transform-config change above: after editing an endpoint's `transforms`, invalidate `endpoint:<endpoint_id>` (or scope by that endpoint) so the stale-shaped entries are dropped and the next fetch re-runs the pipeline and re-caches the new shape.

**Tags self-expire — invalidation is a fast-path, not the only cleanup.** A tag index SET is **not** permanent: `index_tags` arms each SET's TTL to at least as long as the longest-lived entry it points at (`ttl_seconds + grace`, the SWR/SIE grace window included), and only ever *extends* that TTL on later writes (never shortens an existing longer one). So even with **no** explicit invalidation, every cached entry — and its tag membership — lapses on its own once the TTL (and any grace window) elapses. `invalidate_by_tag` simply drops them **immediately** rather than waiting. (Stale set members that point at already-expired cache keys are harmless: deleting an absent key is a no-op, and the SET itself expires.)

**Fail-open, like the rest of the cache.** Tag *indexing* is best-effort and isolated from the payload write — a SADD/EXPIRE failure logs `[ResponseCache] tag indexing skipped` and never fails the cache write. `invalidate_by_tag` is likewise fail-open: a Redis error logs `[ResponseCache] invalidate_by_tag failed` and returns `0` rather than raising.

```bash
# Inspect the tag index (key names are non-secret; values are cache keys, also non-secret).
redis-cli --scan --pattern 'data_source_cache:tag:*'

# Which cache keys does a tag currently point at, and when does the index SET lapse?
redis-cli SMEMBERS 'data_source_cache:tag:endpoint:<endpoint_id>'
redis-cli TTL     'data_source_cache:tag:endpoint:<endpoint_id>'
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `data_source_invalidate_cache` returns `permission_denied` | Caller lacks `ai.data_sources.update` (and `.manage`) | Grant `ai.data_sources.update`; this action hard-denies (no proposal fallback) by design |
| `invalidated: 0` for a tag you expected to hit | Blank/unknown tag, the tag already self-expired, or the entries were never written under it | Confirm the tag name (`ds:<id>` / `endpoint:<id>` / `slug:<slug>`); `SMEMBERS` the tag SET; remember every entry is auto-tagged with the defaults |
| Old shape still served right after editing `transforms` | The transformed payload is cached pre-transform-change | Invalidate `endpoint:<endpoint_id>` (or scope by endpoint); next fetch re-runs the pipeline |
| Tag SETs accumulating in Redis | Normal — they self-expire with their entries (`ttl + grace`) | No action; `invalidate_by_tag` is only needed for *immediate* eviction, not cleanup |

## Onboarding & config versioning (Phase 4b-3b)

Phase 4b-3b adds the **"config not code"** onboarding and lifecycle surface — a source (and its endpoints) becomes a portable, **credential-free** manifest you can export, install from a library template, version, audit, and roll back. It is all built on `Ai::DataSources::ConfigPortabilityService`, the `Ai::DataSources::TemplateLibrary`, and an append-only `Ai::DataSourceConfigVersion` history. Six MCP actions on the existing `data_source_management` tool drive it:

| Action | Permission | What it does |
|--------|------------|--------------|
| `data_source_export` | `ai.data_sources.read` | Emit the source's credential-free manifest (re-importable) |
| `data_source_import` | `ai.data_sources.create` (or `.manage`) | Create-or-update a source + endpoints from a manifest (`dry_run` previews) |
| `data_source_list_templates` | `ai.data_sources.read` | List the built-in starter-manifest catalog |
| `data_source_install_template` | `ai.data_sources.create` (or `.manage`) | Materialize a library template into the account |
| `data_source_config_versions` | `ai.data_sources.read` | List the source's append-only version history (latest first) |
| `data_source_rollback_config` | `ai.data_sources.manage` | Replay a historical manifest (snapshots the pre-rollback state first) |

> **The three write actions file a PROPOSAL when the agent lacks the grant.** `data_source_import`, `data_source_install_template`, and `data_source_rollback_config` all create-or-update a source, so they follow the same proposal fallback as `data_source_create/update/delete`: an agent whose account lacks the mutation permission does **not** mutate — it files an `Ai::AgentProposal` (the import manifest is **re-sanitized through the export allowlist** before it lands in the proposal record, so a hand-supplied manifest can never park a secret in the proposal payload) and returns `requires_approval: true`. This is unlike `data_source_invalidate_cache`, which hard-denies. The author-side walkthrough lives in [../guides/data-sources.md](../guides/data-sources.md); this section is the operating side.

### Exports are credential-free — the security contract

**A manifest NEVER carries secret material — re-attaching credentials is a deliberate, separate post-import step.** This is the load-bearing security property of the whole onboarding surface, enforced by `ConfigPortabilityService#export`:

- The **credentials association is never traversed** — no `Ai::DataSourceCredential` row, no decrypted api key / secret / token / password / mnemonic, no encrypted column ever enters the manifest.
- `auth_config` is exported **only through `#sanitize_auth_config`**, never raw: an **allowlist** (`AUTH_CONFIG_ALLOWED_KEYS` — only non-secret structural knobs like `token_url`, `role_arn`, `region`, `scope`, `vault_path`) intersected with a **denylist** (`SECRET_KEY_SUBSTRINGS` + `SECRET_KEY_EXACT`, applied recursively as defense-in-depth, so a key that turns secret-ish — `client_secret`, `web_identity_token`, a bare `token`/`key`/`api_key` — is stripped even if it somehow rode an allowlisted parent). The free-form jsonb columns (`configuration` / `default_parameters` / `metadata`, and the endpoint templates) are recursively **secret-scrubbed** the same way.
- The same sanitizer **re-runs on import** (`sanitized_source_attrs` → `sanitize_auth_config`) — an inbound manifest is never trusted to already be clean, so a hand-edited manifest cannot smuggle a secret into the stored record.

Because the manifest is credential-free, after **any** import / template install / rollback the operator must re-establish what the manifest deliberately omits, before the source can actually fetch:

1. **Re-attach credentials.** `#import` *never* sets credentials (its hard contract). If the source `requires_auth`, attach a credential via the credentials API/UI — see [Procedure — register a new source](#procedure--register-a-new-source) step 2 — then `make_default` it. An imported `requires_auth: true` source with no credential will fail `validate_config` with `"Active but has no usable credential"` and fail live fetches at the signer.
2. **Re-point Vault references.** A manifest *may* carry a `vault_path` **structural knob** (it is allowlisted as a path, not material), but that path is meaningful only in the **source** environment. After importing into a new account/cluster, re-point `configuration["mtls"].vault_path` (outbound client cert — see [mTLS troubleshooting](#mtls-troubleshooting-outbound-client-certificates)) and any broker `auth_config["broker"]["vault_path"]` (Vault dynamic engine — see [Credential brokering](#credential-brokering-phase-4b-2a)) at the secret that actually exists in the **target** Vault, and store that material out-of-band per [Cryptographic Material Safety](../../CLAUDE.md).
3. **Re-supply the STS `external_id`.** `external_id` is **deliberately excluded** from the export allowlist — an AWS STS `external_id` is a confused-deputy **shared secret**, not a portable knob. After importing an `aws_sts` brokered source, the importing operator must re-supply `external_id` (alongside the base AWS credential) for the target role's trust policy.

> **Templates ship in the repo, so they are credential-free *by construction*.** `TemplateLibrary` manifests are checked in and shipped to every account; they carry only `auth_scheme: "none"` or `"api_key"` (the scheme NAME, no key) and at most `{}` `auth_config`. Even so, `install` routes through `#import`, which re-runs the sanitizer — defense in depth against a hand-edited template. A template that declares `requires_auth: true` (e.g. `generic-graphql`) still needs the operator to attach the key afterward.

### Bulk-onboarding from templates

For standing up many sources fast, start from the built-in template catalog rather than hand-writing each manifest. `Ai::DataSources::TemplateLibrary` is an account-agnostic, credential-free library of starter manifests in the exact shape `#export`/`#import` use; **installing a template is just importing a seeded manifest**. The current catalog:

| Template slug | Category | Auth | Notes |
|---------------|----------|------|-------|
| `generic-rest-json` | general | none | Blank REST/JSON scaffold — replace the placeholder base URL + example endpoint |
| `rss-feed` | news | none | Public RSS/Atom feed reader (`respect_robots: true`, `crawl_delay_seconds: 5`) |
| `open-meteo-weather` | weather | none | **Works out of the box** — real public no-key weather API; good reference manifest |
| `generic-graphql` | general | api_key | GraphQL POST scaffold; `auth_scheme: "api_key"` is a HINT — attach the key after install |

List the catalog, then install by slug:

```bash
# 1. List the starter catalog (slug / name / description / category — manifests omitted)
#    platform.data_source_list_templates
#      → { templates: [{slug, name, description, category}, ...], count: N }

# 2. Install one (materializes its credential-free manifest via ConfigPortabilityService#import)
#    platform.data_source_install_template  template_slug: "open-meteo-weather"
#      → { data_source: {...}, created: true, updated_endpoints: [{slug, action}], errors: [] }
```

```ruby
# rails runner — bulk-onboard several templates into one account in a loop.
# install() NEVER sets credentials; target_slug lets you install the same template
# more than once (the model de-dupes the name on a clone).
account = Account.find_by!(slug: "acme")
%w[open-meteo-weather rss-feed generic-rest-json].each do |slug|
  result = Ai::DataSources::TemplateLibrary.install(slug, account: account)
  Rails.logger.info("[data-sources] installed #{slug}: created=#{result[:created]} errors=#{result[:errors].inspect}")
end
```

Operating notes:

- **Idempotent by slug.** `#import` does `find_or_initialize_by(slug:)` for the source and upserts endpoints by slug, **all in one transaction** — re-installing the same template **updates** rather than duplicating (`created: false`). To install the same template as a *second* source, pass an override `slug:` / `target_slug:` (a clone under a new slug gets its **name de-duplicated** — `"… (2)"` — so it can't trip the per-account name-uniqueness validation).
- **Preview with `dry_run`.** `data_source_import` / `install` accept `dry_run: true` — returns the create/update plan (`updated_endpoints: [{slug, action}]`, source compact preview) and persists **nothing**. Use it to confirm an import will *update* vs *create* before committing.
- **Transactional all-or-nothing.** A single bad endpoint records an error and rolls the **whole** import back (no half-applied source). The action surfaces that as an `error_result` (nil `data_source` + populated `errors`).
- **Migrating a source between accounts/clusters** is export-then-import: `data_source_export` the source (carry the manifest out — it is diffable and secret-free), `data_source_import` it into the target, then complete the credential-free gaps per [the security contract](#exports-are-credential-free--the-security-contract).

### Auditing config history

Every source carries an **append-only** config-version history in `ai_data_source_config_versions` (`Ai::DataSourceConfigVersion`) — one row per monotonic `version` (1, 2, 3…), each a full credential-free `manifest` snapshot of the source + endpoints at that point in time, classified by `created_by_type`:

| `created_by_type` | Captured when |
|-------------------|---------------|
| `manual` | An explicit operator snapshot (`snapshot!(created_by_type: "manual")`) |
| `auto` | Automatically (e.g. before an automated config change) |
| `rollback` | The pre-rollback state, recorded by a `rollback!` to preserve reversibility |

> **The persisted `manifest` is credential-free, same as an export** — it is produced by the same `#export`, so a version row **never** contains secrets (the model documents this as a `SECURITY` invariant). The history is safe to read, diff, and surface in the UI.

List the history (newest first):

```bash
#    platform.data_source_config_versions  data_source_id: ":id"
#      → { versions: [{id, version, created_by_type, note, created_at}, ...], count: N }
```

```ruby
# rails runner — diff two versions' manifests to see exactly what changed.
ds = Ai::DataSource.for_account(account).find_by!(slug: "open-meteo-weather")
v_old, v_new = ds.config_versions.ordered.last(2)          # ascending → the two most recent
require "json"
puts JSON.pretty_generate(v_new.manifest)                  # full credential-free snapshot
# (manifests are byte-stable except exported_at, so a plain Hash/JSON diff is honest)
```

- The unique index is `(ai_data_source_id, version)`; `next_version_for` is a `MAX(version)+1` check-then-act, so a concurrent snapshot that collides on the index is **retried** (up to 3×, recomputing the next version) rather than failing — versions stay gap-tolerant but never duplicate.
- The listing carries metadata only (`version` / `created_by_type` / `note` / `created_at`) — the full `manifest` jsonb is read at the model layer (`ds.config_versions`), not in the compact MCP listing.
- There is **no MCP/REST action that snapshots on demand** — versions are written by `ConfigPortabilityService#snapshot!` (manual/auto) and by `rollback!` (the `rollback` row). To capture a manual checkpoint before a risky hand-edit, call `snapshot!` from `rails runner`:

```ruby
Ai::DataSources::ConfigPortabilityService.new(account: account)
  .snapshot!(ds, created_by_type: "manual", note: "before widening forecast query_template")
```

### Rolling back a bad config change

When a config edit goes wrong — a broken `transforms` pipeline, a bad `response_mapping`, a wrong base URL, a fat-fingered rate limit — restore a known-good version with `data_source_rollback_config`. It does **not** blindly overwrite: `ConfigPortabilityService#rollback!` **captures the current (pre-rollback) state first**, then replays the historical manifest through the same transactional `#import` (so credentials are never touched and a partial replay rolls itself back).

```bash
# Restore the source's config to a prior version NUMBER (from data_source_config_versions).
#    platform.data_source_rollback_config  data_source_id: ":id"  version: 3
#      → { restored_version: 3, created: false, updated_endpoints: [...], errors: [],
#          message: "Rolled config back to version 3" }
```

**The pre-rollback snapshot is what makes a rollback reversible.** The sequence is deliberate:

1. `rollback!` builds the **current** manifest in memory (`export(data_source)`) but does **not** persist it yet.
2. It replays version *N*'s historical manifest via `#import`.
3. **Only if the replay succeeds** does it persist the pre-rollback manifest as a **new `rollback`-type version** (`note: "pre-rollback state before restoring v<N>"`). A *failed* replay therefore leaves **no spurious `rollback` row** behind.

So a rollback never loses the state it replaced — it becomes the newest version in the history. If the rollback itself was a mistake, **roll forward** by rolling back *to that pre-rollback `rollback` version* (it is now just another numbered version you can restore). Recovery is always "pick a version, restore it," in either direction.

**What a failed rollback returns.** The replay is `#import`, which is transactional — a bad historical manifest (e.g. an endpoint that no longer validates under current model rules) rolls its own partial writes back. `rollback!` then returns `restored_version: nil` with a **populated `errors`** array (and the pre-rollback snapshot is **not** written). The MCP action inspects exactly that and surfaces it as a **failure**, not a misleading success:

```jsonc
// data_source_rollback_config on a replay that failed:
{ "success": false, "error": "endpoint forecast: Response mapping is invalid" }
```

- A **version not found for this source** returns `{ error: "config version not found for this data source" }` up front (the version is resolved account- and source-scoped, so you can't restore another source's version).
- `version` is **required** — omitting it is an `ArgumentError` (`"version is required"`).
- A rollback is a **mutation** gated by `ai.data_sources.manage`; an agent lacking it files a proposal (`proposed_changes: { action: "rollback_config", data_source_id:, version: }`) rather than rolling back.

> **A rollback restores CONFIG, not credentials or cache.** Per the credential-free contract, replaying a manifest never re-attaches credentials — if the rolled-back-to version pre-dated a credential change, the *current* credentials still apply (re-attach/re-point per [the security contract](#exports-are-credential-free--the-security-contract) if needed). And because a config change can alter the response shape, **if the rollback changed an endpoint's `transforms`/`response_mapping`, invalidate that endpoint's cache** (see [Cache-tag invalidation operations](#cache-tag-invalidation-operations)) so stale-shaped entries are dropped and the next fetch re-derives under the restored config.

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `data_source_rollback_config` returns `success: false` with an endpoint error | The historical manifest no longer validates under current model rules; the transactional replay rolled back | Read the `error`; fix the offending field, or roll back to a *different* (still-valid) version. No `rollback` snapshot was written |
| `error: "config version not found for this data source"` | The `version` number doesn't exist for this source (or belongs to another source) | List valid versions with `data_source_config_versions`; the version is account+source scoped |
| Rolled back but the source still fetches the wrong shape | The endpoint's old transformed/mapped payload is still cached (transforms/cache are pre-change) | Invalidate the endpoint's cache (`endpoint:<id>` tag or scope) so the next fetch re-runs under the restored config |
| Rolled back but the source can't authenticate | Rollback restores config only — credentials are never touched, and the rolled-back-to manifest carries no secret | Re-attach/`make_default` the credential and re-point any `vault_path`/`external_id` per the security contract |
| Want to undo the rollback itself | The pre-rollback state was snapshotted as a new `rollback`-type version | Roll *forward* by restoring that pre-rollback version number — it's just another entry in the history |

## Multi-source failover, forensic replay & RAG ingestion (Phase 4b-3c)

Phase 4b-3c adds the **multi-source long-tail** plus two adjacent operator capabilities, all built **on top of** the unchanged governed `QueryService` — none of them adds a fetching, signing, or credential path of its own:

1. **Failover** (`Ai::DataSources::FailoverService`) — try an **ordered** list of equivalent targets (primary + mirrors) and return the **first** success.
2. **Reconciliation** (`Ai::DataSources::ReconciliationService`) — **merge** the records from several sources into one list by exact canonical-key match. (Deterministic; see [its own section](#reconciliation-determinism-same-inputs--same-merge).)
3. **Replay** (`Ai::DataSources::ReplayService`) — reconstruct a **past** fetch from its redacted audit row, with **no** network call.
4. **RAG ingestion** (`Ai::DataSources::RagIngestionService`) — pipe canonical records into a knowledge base as embedded documents.

Five MCP actions on the existing `data_source_management` tool drive them:

| Action | Permission | Fetches upstream? | What it does |
|--------|------------|-------------------|--------------|
| `data_source_failover_query` | `ai.data_sources.query` | yes (ordered, until one wins) | Try `targets` in order; return the first success (or last failure) with failover provenance |
| `data_source_reconcile` | `ai.data_sources.query` | yes (every target) | Fetch all `targets`, merge their records by `key` per `strategy` |
| `data_source_replay` | `ai.data_sources.read` | **no** | Reconstruct a recorded fetch by `query_id`/`correlation_id` from the audit row |
| `data_source_ingest_to_kb` | `ai.data_sources.manage` | yes (one fetch) | Fetch a source+endpoint, embed the records into `knowledge_base_id` |
| `data_source_invalidate_cache` | `ai.data_sources.update` | no | (Phase 4b-3a — listed here for the permission contrast below) |

> **Two permission tiers, two unauthorized behaviors.** `failover_query` / `reconcile` are **query** actions (they exercise the upstream fetch) gated by `ai.data_sources.query`; a caller without it is **hard-denied** (`permission_denied`), same as `data_source_query`. `data_source_ingest_to_kb` **writes** `Ai::Document` rows + embeddings, so it is a **managed mutation** (`ai.data_sources.manage`) and an agent lacking the grant files an `Ai::AgentProposal` (`action: "ingest_to_kb"`) rather than ingesting — mirroring `data_source_rollback_config`. `data_source_replay` is **read-only** (`ai.data_sources.read`). **`MAX_TARGETS = 25`** caps the fan-out a single reconcile/failover request can trigger.

### Configuring a primary + mirror failover group

There is **no "failover group" model** — a group is just an **ordered `targets` list you pass at call time**, primary first. `FailoverService#query` walks them in order through a full governed `QueryService#call` per attempt and returns the **first** envelope with `success: true`, stopping immediately (no later mirror is touched). Every governance gate applies **independently per source** on each attempt — the per-source kill flag, per-source + per-agent quota, query-time ABAC/compliance, the response cache (a mirror may serve a warm cache **hit** and win without an upstream call), SSRF egress, the per-source circuit breaker, schema/quality, redacted audit persistence, and cost attribution. There is **no sleep/backoff** between attempts — the per-source circuit breaker already governs upstream pressure.

```bash
# Primary first, then mirrors, in preference order. Returns the WINNING FetchEnvelope
# (verbatim, like data_source_query) with failover provenance stamped on it.
#   platform.data_source_failover_query
#     targets: [ { data_source_id: "<primary>", endpoint_id: "<ep>" },
#                { data_source_id: "<mirror-1>", endpoint_id: "<ep>" },
#                { data_source_id: "<mirror-2>", endpoint_id: "<ep>" } ]
#     params:  { ... }          # forwarded VERBATIM to every attempt
```

What counts as a **failed** attempt (advance to the next target): the envelope has `success: false` for **any** reason — `error` / `timeout` / `rate_limited` / **`blocked`** (a governance/egress deny on that source is just a failure here, so failover transparently routes *around* a source an agent is fenced off from) — or the `QueryService` construction itself raised (defensive; `QueryService` is documented never to raise, but a malformed target is caught and counts as a failure). A failed attempt never aborts the batch.

**The all-fail outcome is a real, audited failure — not a synthesized one.** When **every** target fails, failover returns the **last** mirror's actual failure envelope (each attempt was independently audited) with `failover_source: nil`, so you see a genuine governed failure rather than a fabricated one. Only an **empty/blank `targets` list** yields a synthesized `"no data sources available for failover"` error (nothing was tried).

> **`params` are forwarded verbatim to every target — the endpoints must be genuinely interchangeable.** Failover does no per-mirror param translation; if a mirror expects a different query shape, it will simply fail and be skipped. Equivalence is the operator's contract.

### Reading the failover provenance flags

Every returned envelope — success, all-fail, **and** the no-targets error — carries the **same three** failover keys on `provenance`, so a caller can read them unconditionally:

| Provenance key | Type | Meaning |
|----------------|------|---------|
| `failover_used` | bool | `true` when **more than one** target was attempted (the primary did **not** win outright). `false` when the first target succeeded on the first try. |
| `failover_attempts` | int | How many targets were actually tried (1 when the primary won; 0 for the no-targets error). |
| `failover_source` | string \| nil | Slug of the target that **won**, or `nil` when all failed / nothing was tried. |

```bash
# Read the failover bookkeeping off the returned envelope.
#   platform.data_source_failover_query  targets: [...]  params: {...}
#   → .provenance.failover_used     (true ⇒ a mirror was needed)
#     .provenance.failover_attempts (how many targets were tried)
#     .provenance.failover_source   (which slug actually served; nil ⇒ all failed)
```

Operational reading: a steadily rising `failover_attempts` / a `failover_source` that is consistently a **mirror** (not the primary) means the **primary is unhealthy** — go check the primary's circuit breaker, quota, and health (`data_source_health`). `failover_used: false` is the steady state (primary serving). On a failover-attempted envelope, a **non-Hash/missing** provenance from a source is normalized to a Hash, and any stale string-keyed `"provenance"` is dropped so the three keys live under a single (symbol) source of truth.

> **A synthesized per-attempt failure is flagged.** A target that could not even produce an envelope (construction fault) contributes a `provenance.failover_synthesized: true` failure internally; the *returned* envelope (a real source's, on all-fail) carries the three bookkeeping keys above. The all-fail return is the last real attempt, so its `error`/`status` are that mirror's actual values.

### Investigating a past fetch with replay

`data_source_replay` reconstructs a **FetchEnvelope-shaped view of a past query** from its already-redacted `ai_data_source_queries` audit row — for forensics, audit, and "what did this agent actually receive." It is a **reconstruction, not a re-execution**: it **NEVER** performs an upstream fetch, **NEVER** re-signs a request, and **NEVER** resolves credentials. The replayed envelope carries `status: "replayed"` (a forensic token, **not** a `DataSourceQuery::STATUSES` member — a replay persists **nothing**); the original live status is preserved under `provenance.original_status`.

Resolve the row by **`query_id`** (the row UUID) **or** **`correlation_id`** — both are **account-scoped**, so a replay can never reach across tenants (an out-of-account ref is treated as not-found):

```bash
# Replay by audit-row id (or pass correlation_id instead).
#   platform.data_source_replay  query_id: "<ai_data_source_queries uuid>"
#   → { success: true, status: "replayed", replayed: true,
#       replayed_from_query_id, correlation_id, recorded_at,
#       data: [...]|[],  provenance: { ...forensic... } }
```

The reconstructed `provenance` surfaces the recorded forensic linkage straight off the row + its metadata jsonb: `response_sha256`, `served_stage`, the **already-redacted** `source_url` (nothing is un-redacted), `original_status`, `http_status`, `from_cache`, `rows_returned`, the original `anomalies`, the `audit_chain` anchor, the `redacted_params` / `redacted_response_snippet`, and the `policy_decision`. `recorded_at` is the row's `created_at` as ISO8601 UTC; `duration_ms` is **0** (a replay does no work — the original duration lives on provenance for reference).

**The body is withheld unless it is still recoverable AND you are still authorized.** The audit row deliberately stores **only** a redacted snippet + the `response_sha256`, never the full body. So `data` is populated **only** when **all** of these hold — otherwise `data: []` with `provenance.note: "payload_not_cached"` (forensic metadata only):

1. **You supplied the original `params`.** The row stores only a one-way `params_hash` (SHA256), so the cache key is otherwise unreconstructable. The supplied params are re-hashed **the exact same way `QueryService` did** (deep-sorted canonical JSON → SHA256 → first 64 hex) and must **match** the recorded `params_hash` — a mismatch (or a row predating `params_hash`) refuses the read rather than risk surfacing a *different* param-variant's payload.
2. **The original (source, endpoint, params) cache entry is still present.** Replay does a **read-only** `ResponseCacheService.read` (never a write); an evicted/aged-out entry is a miss ⇒ `payload_not_cached`.
3. **The CURRENT requester passes the live governance authorize gate** for that source **right now** (`GovernanceService#authorize`), and the recovered records are **RE-MASKED** for the current requester (`#mask_records`) before return.

> **Replay can never leak more than a live read would today.** Point (3) is the load-bearing security property: the body is gated by the **same** authorization a live read enforces and re-masked for the **current** requester — so even if a source's masking config (or the requester's privileges) tightened *after* the original fetch, the replayed body reflects **today's** egress controls, not the original (possibly looser) ones. The authorize gate **fails CLOSED** (withhold the body) on any error; the forensic provenance still returns. `provenance.masking_applied` / `masked_field_count` report the re-mask outcome, not the original fetch's.

```bash
# Recover the (re-masked) body too — supply the ORIGINAL params so the cache key is
# reconstructable. Body comes back ONLY if it is still cached AND you are authorized.
#   platform.data_source_replay  correlation_id: "<corr-id>"  params: { lat: 52.5, lon: 13.4 }
#   → .data                          ([] when not cached / params omitted / unauthorized)
#     .provenance.note               ("payload_not_cached" when the body was withheld)
#     .provenance.masking_applied    (re-mask outcome for the CURRENT requester)
#     .provenance.original_status    (the live status of the original fetch)
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `status: "replay_not_found"` | The `query_id`/`correlation_id` doesn't exist **in this account**, or no ref supplied | Confirm the ref and that it belongs to the current account (replay is account-scoped); list recent rows via `data_source_provenance` |
| `data: []` + `note: "payload_not_cached"` despite supplying `params` | The cache entry **aged out / was evicted**, the params **didn't hash-match** the recorded `params_hash`, or the row predates `params_hash` | Expected when the entry expired; if it should be warm, verify the params are byte-identical to the original request (deep order doesn't matter, values do) |
| `data: []` even though the entry is warm and params match | The **current requester is not authorized** for that source now (authorize gate fails closed), or the source/endpoint association was destroyed | Check `GovernanceService` authz for the current agent (see [Query-time governance](#query-time-governance-phase-4b-2b)); the forensic provenance still returned |
| `status: "replay_error"` | A reconstruction fault (rescued to a safe error) | A replay never raises into the caller; capture the `[DataSources::ReplayService] replay failed (<class>)` backend log line |
| Replayed body **more redacted** than what the agent originally saw | Working as designed — the body is re-masked for **today's** config/requester, not the original | This is the anti-leak guarantee; to see the original masking outcome read the **original** row via `data_source_provenance` |

### RAG ingestion operations

`data_source_ingest_to_kb` is the **fetch → embed** bridge: it governed-fetches a source+endpoint via `QueryService`, then pipes the **canonical records** into a knowledge base as embedded `Ai::Document` rows via `RagIngestionService#ingest`, so the same point-in-time data is **semantically retrievable** through the existing RAG path long after the fetch (without re-fetching + re-parsing on every question). It **reuses** `Ai::RagService` end-to-end (`create_document` → `process_document` → `embed_chunks`) — it invents **no** new model and **no** new embedding path. Documents are stamped `source_type: "api"` (the only `Ai::Document` allow-list value that fits an external-API record).

> **Ingested records are the ALREADY-MASKED QueryService output.** The bridge embeds exactly what the governed fetch returned — i.e. the **masked** records (egress masking from [Query-time governance](#query-time-governance-phase-4b-2b) has already run at envelope finalization). So a redacted field (`[REDACTED:email]`, etc.) is embedded **as the redacted placeholder**; the knowledge base never sees the unmasked value. Masking happens upstream in `QueryService`, not in the ingestion bridge — the bridge is a pure sink. This means the source's `metadata.governance.mask` config governs what lands in the KB.

```bash
# Fetch a source+endpoint and embed the records into a knowledge base.
#   platform.data_source_ingest_to_kb
#     data_source_id: "<ds>"  endpoint_id: "<ep>"  knowledge_base_id: "<kb-uuid>"
#     key:    "id"            # OPTIONAL canonical record-key for incremental re-embed
#     params: { ... }         # query/path/body params for the fetch
#   → { fetch_status, fetch_success,
#       ingest: { ingested, updated, skipped, capped, errors, knowledge_base_id } }
```

**Incremental re-embed by `record_key`.** When you pass **`key:`**, records are deduplicated by their canonical `record[key]` against prior ingested documents **in this KB** (located by the `metadata->>'record_key'` stamped on each `Ai::Document`, **scoped to this source+endpoint** so two different sources sharing a key value in the same KB never clobber each other):

| Per-record outcome | Condition | Tally bucket |
|--------------------|-----------|--------------|
| **SKIP** (no re-embed) | Same `record_key` **and** same `content_sha256` as the prior doc — unchanged | `skipped` |
| **UPDATE** | Same `record_key`, **different** `content_sha256` — content changed | `updated` |
| **CREATE** | No prior doc with this `record_key` (or `key:` omitted ⇒ always create) | `ingested` |

> **An UPDATE never leaves a zero-document window for a key.** The update path **creates the new doc first, then deletes the stale one(s)** (scoped to source+endpoint+key, including any accumulated duplicates, excluding the freshly created doc) — so if create/chunk raises, the **prior** document stays intact. Re-running the same ingest with **no upstream change** is therefore cheap and idempotent: every record SKIPs (no re-embed). Without `key:`, dedup is impossible, so **every** record CREATEs a fresh doc — re-running **duplicates**.

**The per-call cap.** At most **`MAX_RECORDS_PER_CALL = 5_000`** records are ingested per call; the overflow is reported as **`capped`** (and logged) so a single ingest can never kick off a runaway embedding storm over a huge fetched batch. (A pathological single record's body is also defensively bounded at `MAX_CONTENT_CHARS = 100_000`.)

**Batch embedding — one pass, not per-record.** `create_document` + `process_document` run **per record** (create + chunk), but **embedding is deferred** to a **single** post-loop `embed_chunks(kb.id)` pass (no `document_id:` ⇒ embeds every chunk lacking an embedding) — so the KB's `complete_indexing!` fires **once for the whole batch** rather than once per record. The embed pass runs only when at least one doc was created or updated.

**Resilience + scoping.** A per-record failure is logged + counted under **`errors`** and **never aborts the batch**. The knowledge base **must** belong to the caller's account (`KnowledgeBase.for_account` — an out-of-account KB resolves to `"knowledge base not found for account"`). The bridge never raises.

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `data_source_ingest_to_kb` returns `requires_approval: true` | The agent lacks `ai.data_sources.manage` — it filed a proposal (`action: "ingest_to_kb"`) instead of ingesting | Approve the proposal, or grant `ai.data_sources.manage`; this is a managed write (documents + embeddings), not a read |
| `error: "knowledge base not found for account"` | The `knowledge_base_id` doesn't exist **or** belongs to another account | Confirm the KB UUID via `platform.list_knowledge_bases`; ingestion is account-scoped |
| `ingest.skipped` == record count, `ingested`/`updated` == 0 | Re-ran with `key:` and **nothing changed** upstream — every record matched a prior doc's `content_sha256` | Expected and cheap (no re-embed). This is the steady state of incremental re-embed |
| Re-running **duplicates** documents | You omitted **`key:`**, so dedup is impossible and every record CREATEs anew | Pass `key:` (a stable canonical field) to enable skip/update incremental dedup |
| `ingest.capped` > 0 | The fetched batch exceeded `MAX_RECORDS_PER_CALL` (5_000) | Narrow the endpoint `response_mapping`/`query_template`, or page the source so each call stays under the cap; the overflow was not silently dropped |
| `fetch_success: false` but `ingest.errors: 0` | The **fetch** failed (kill flag / quota / governance block / upstream error), so there were no records to embed | Read `fetch_status`; this is a fetch problem, not an ingestion one — diagnose the source per the fetch-pipeline runbook |
| Embedded fields are `[REDACTED:…]` | The source has egress masking on — the bridge embeds the **already-masked** `QueryService` output | Expected; the KB never sees unmasked values. Change `metadata.governance.mask` on the source if the redaction is wrong (see [Masking](#masking--fields-coming-back-redacted)) |
| Records ingested but not retrievable | The embed backend is down (chunks created, never embedded) | Check `embed_chunks` health; the batch embed is best-effort and logs `batch embed failed` — re-run the ingest once the backend recovers |

### Reconciliation determinism (same inputs ⇒ same merge)

`data_source_reconcile` fetches **every** target independently (each through the full governed `QueryService` pipeline), collects the records from each **successful** envelope, then collapses them into **one** list by **exact canonical-key match** via `ReconciliationService`. It records a per-source `status` for **every** target (including failures, which simply contribute no records) so you can see exactly what merged.

```bash
#   platform.data_source_reconcile
#     targets:  [ { data_source_id: "<a>", endpoint_id: "<ep>" },
#                 { data_source_id: "<b>", endpoint_id: "<ep>" } ]
#     key:      "id"                 # canonical key field shared across the sources
#     strategy: "last_wins"          # first_wins | last_wins | merge  (default last_wins)
#     params:   { ... }              # forwarded to EVERY target fetch
#   → { key, strategy, reconciled: [...], reconciled_count,
#       sources: [ { data_source_slug, success, status, record_count, error }, ... ],
#       source_count, succeeded_count }
```

**The merge is PURE and DETERMINISTIC — the same record sets always produce the same merged output.** `ReconciliationService#reconcile` touches **no DB, no network, no Redis, no clock**, and does **not mutate its inputs** (winners are shallow-duped before any in-place merge). Given the same `targets` results, `key`, and `strategy`, the output is **byte-identical** every time — so a reconcile is safe to call inline on a request, and a discrepancy between two runs always traces to a **fetch** difference (a target returned different/over data), never to the merge. The determinism rests on three fixed rules:

- **Exact-key grouping, never fuzzy.** Records group **only** by the **exact** value of the `key` field, **string-coerced** (so `1` and `"1"` reconcile together; `"Acme"` and `"ACME"` are **different** keys — there is **no** probabilistic / fuzzy entity resolution, no cross-source SQL/join, no query plan). The key is read string/symbol-tolerant. An **empty-string** value (`""`) is a **real** key, distinct from absent.
- **Stable output order.** The **first appearance** of each distinct key **fixes its slot** in the output, regardless of strategy — so `last_wins` keeps the winner in the key's **original** position (it does **not** move to the end). Keyless records (below) hold their own first-appearance slots, interleaved with keyed groups.
- **Three fixed collapse strategies:**

| `strategy` | A group of same-key records collapses to… |
|------------|-------------------------------------------|
| `first_wins` | The **first** record seen for the key (earliest set, earliest index). Later duplicates discarded. |
| `last_wins` (**default**) | The **last** record seen — each later duplicate **wholly replaces** the prior winner. |
| `merge` | Shallow field-merge: start from the first record, overlay each later same-key record's **non-nil** fields (later non-nil wins per field; earlier values survive where the later record is nil/absent). **One level deep** — a nested Hash/Array value is replaced **wholesale**, never deep-merged (this is what keeps `merge` deterministic and structurally unambiguous). An unknown `strategy` falls back to `last_wins` (logged), never raising. |

> **Keyless records are passed through, not dropped.** A record missing the `key` entirely (no String and no Symbol key field, or a `nil` value) is **not** discarded — it passes through **unmerged** in first-appearance order, flagged with **`_unreconciled: true`** so a caller can tell a passed-through record from a reconciled one. Keyless records never collide with each other. (An empty-string key value is *not* keyless — it groups normally under `""`.)

**Bounded + resilient.** At most **`MAX_OUTPUT = 100_000`** records are emitted; once the cap is hit, **new** distinct keys / new keyless rows are dropped (and it logs once), but **updates to already-admitted keys still apply** — so the cap never produces a partially-merged winner. A reconcile fault degrades to a **flat pass-through** of all input records (logged, class only) so the caller still gets data; the per-source fetch loop is independently guarded so one bad target never aborts the batch.

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `reconciled_count` < total fetched records | Expected — same-key duplicates across sources collapsed to one per key | Read `sources[].record_count` vs `reconciled_count`; the delta is the de-duplication |
| Two runs return **different** merged output | The **fetch** differed (a target returned different/extra data), **not** the merge — the merge is deterministic | Compare `sources[].record_count`/`status` between runs; chase the source whose count changed (cache vs live, partial upstream) |
| Records you expected to merge stayed separate | The `key` values differ by **case/whitespace/type-as-string** (`"Acme"` ≠ `"ACME"`) — matching is exact, never fuzzy | Normalize the key upstream (an endpoint `transforms` `computed`/`rename` step) so the canonical key is identical across sources |
| Output has `_unreconciled: true` records | Those records **lack the `key`** field (or it's nil) — passed through unmerged by design | Add/repair the key field upstream if they should participate; otherwise this flag is the intended "could not reconcile" marker |
| `merge` didn't combine a nested object | `merge` is **one level deep** — nested Hashes/Arrays are replaced wholesale, not deep-merged | Expected; flatten the nested field with a `transforms` step first if you need field-level merge inside it |
| `succeeded_count` < `source_count` | One or more targets **failed** to fetch (they contribute no records) | Inspect `sources[].status`/`error`; a failed target is silently excluded from the merge — fix it per the fetch-pipeline runbook |

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

## Incremental sync stuck / not advancing

Incremental sync is an **opt-in, per-endpoint** monitor-loop feature: an endpoint declares an `incremental` jsonb config and each successful poll advances a high-watermark `sync_cursor` on the **subscription**, so the next poll only asks the upstream for rows newer than the watermark. It is **OFF by default** — a blank `incremental` (`{}`) leaves the poll path byte-for-byte unchanged. When it *is* on but the watermark never moves, the subscription keeps re-fetching the same window every tick. This section is how to recognize and inspect that.

The config (on `Ai::DataSourceEndpoint#incremental`, see `Ai::DataSources::IncrementalSync`):

```jsonc
{
  "cursor_param": "since",            // outbound query/body param the cursor is stamped onto
  "cursor_path":  "provenance.next",  // dotted path to the NEXT cursor in the response
  "mode":         "cursor"            // "cursor" | "timestamp" (advisory only — both dig the same path)
}
```

How the loop is *supposed* to advance (`MonitorService#poll_subscription`):

1. **Before** the fetch — `apply_cursor` stamps the subscription's stored `sync_cursor` onto the outbound params under `cursor_param`. With **no cursor yet** (the first incremental poll) this is a no-op, so the first poll runs a **full fetch and seeds** the watermark — that is expected, not a bug.
2. **After** a successful fetch — `extract_cursor` pulls the *next* watermark out of the `FetchEnvelope`. It checks in order: `provenance[:incremental_cursor]` (the cursor `QueryService` already dug from the **raw** body via `cursor_from_body` — see below), then `cursor_path` dug against `provenance`, then `cursor_path` dug against the canonical `data` (records).
3. `record_poll!(cursor:)` persists it — **but only when the cursor is non-blank**. A `nil`/blank cursor **leaves the existing `sync_cursor` untouched**, so a response that omits the token never clobbers progress (it also never advances it).

So "stuck" almost always means **step 2 resolved to nil** every poll.

> **Why `provenance[:incremental_cursor]` exists.** The JSON decoder's `records_path` unwrap **discards top-level paging tokens** — a body like `{"meta":{"next_cursor":"…"},"items":[…]}` becomes just the `items` array in `envelope[:data]`, so `meta.next_cursor` is unreachable from the records. To handle that, `QueryService` runs `IncrementalSync.cursor_from_body` against the **raw, pre-unwrap** body at fetch time and stashes the result at `provenance[:incremental_cursor]`, which `extract_cursor` prefers. **Timestamp-mode** sources (cursor embedded *in* a record, e.g. the last row's `updated_at`) carry no top-level token, so `cursor_from_body` returns nil for them and they fall through to the records-based `cursor_path` dig — which is exactly the intended split.

### How to inspect

```sql
-- The subscription's stored high-watermark. If this never changes across polls,
-- the cursor is not advancing. NULL = no watermark yet (first poll not yet run,
-- or every extract resolved to nil).
SELECT id, last_polled_at, sync_cursor, last_checksum, status, consecutive_failures
FROM   ai_data_source_subscriptions
WHERE  id = '<subscription_id>';
```

```ruby
# rails runner — inspect the endpoint's incremental config and dry-run the extract
sub = Ai::DataSourceSubscription.find("<subscription_id>")
ep  = sub.endpoint
ep.incremental                  # the jsonb config — confirm cursor_param / cursor_path / mode
ep.incremental?                 # => true only when the config is present (blank == OFF)
sub.sync_cursor                 # the current watermark (nil until first successful seed)
```

To see what the upstream actually returns and whether the cursor resolves, run one governed fetch and read the provenance:

```bash
# MCP: a single governed fetch; inspect provenance.incremental_cursor
#   platform.data_source_query  data_source_id: ":id"  endpoint_id: ":ep"
#   → look at .provenance.incremental_cursor (the cursor QueryService dug from the raw body).
#     Present  => extract WILL advance the watermark next poll.
#     Absent   => the path/token did not resolve — see the table below.
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Subscription keeps re-fetching the **same window**; `sync_cursor` never changes | `extract_cursor` resolves to nil every poll, so `record_poll!` leaves the watermark untouched | Run one `data_source_query` and check `provenance.incremental_cursor`; if absent, the cursor isn't being found — work down the rows below |
| `provenance.incremental_cursor` absent but the upstream *does* return a token | **Wrong `cursor_path`** — `cursor_from_body` dug the wrong dotted path so it returned nil | Fix `cursor_path` to the actual location in the **raw** JSON (e.g. `meta.next_cursor`); top-level paging tokens live in provenance, not the records |
| `sync_cursor` stays NULL forever on a timestamp-mode endpoint | `cursor_path` points at a top-level field, but timestamp-mode carries the cursor *inside a record* | Point `cursor_path` at the record-relative path (e.g. `0.updated_at` against the data array); `cursor_from_body` legitimately returns nil for these and the records dig takes over |
| Upstream **omits** the token on some responses | A response with no cursor returns nil → `record_poll!` deliberately keeps the old watermark (never clobbers progress) | Expected safety behavior; if the watermark is *always* stale, the upstream may never emit a usable token — switch `mode`/`cursor_path` to a field it does return |
| `sync_cursor` is set but the upstream still returns the full window | **Mode mismatch** — the cursor value is stamped onto `cursor_param`, but the upstream expects a different param name or value semantics | Confirm `cursor_param` matches the upstream's incremental parameter; `mode` is advisory only (both modes dig the same path) — the real lever is `cursor_param` + `cursor_path` |
| First incremental poll fetched everything | Expected — with no `sync_cursor` yet, `apply_cursor` no-ops and the first poll seeds the watermark | None; the *second* poll should carry the cursor. Confirm `sync_cursor` populated after the first successful poll |

> **Cursor injection / extraction never fails the poll.** Both `apply_sync_cursor` and `extract_sync_cursor` in `MonitorService` are wrapped — an error injecting the cursor falls back to the un-cursored params (logged `cursor inject failed`), and an error extracting returns nil (logged `cursor extract failed`). So a malformed `incremental` config degrades to a **full fetch that doesn't advance**, never a failed subscription. Check the monitor log for those two warnings if a configured endpoint silently behaves like incremental is off.

## Crawl politeness troubleshooting

Crawl politeness applies **only to the background monitor loop**, and **only when a source opts in** — `respect_robots = true` (default `false`) **or** a positive `crawl_delay_seconds`. The interactive `QueryService` path **never** sleeps or paces. Two independent mechanisms can hold back a background poll:

- **robots.txt** (`Ai::DataSources::RobotsService`) — a fetched-and-parsed robots.txt that **explicitly Disallows** the path.
- **per-host pacing** (`Ai::DataSources::HostPacer`) — the host was hit more recently than its min-interval, so the monitor **defers** the poll to a later tick.

Both fail **open** (a fault degrades to "allowed" / "not paced"), so neither can wedge a source on an unrelated network or Redis blip.

### robots blocking legitimate fetches

The single most important fact: **robots is DEFAULT-ALLOW.** A missing robots.txt (404 / any 4xx), an empty body, a fetch failure (timeout / transport / SSRF rejection / oversized), or a Redis fault **all resolve to allowed**. The **only** thing that returns `false` is a robots.txt that *successfully loaded and parsed* and carries an **explicit `Disallow`** matching the request path (longest-match wins; `Allow` beats `Disallow` on a length tie). So if politeness is blocking a fetch you believe is legitimate, there is a **real `Disallow` rule** in the cached ruleset — go read it.

Parsed rules are cached in **Redis DB 0** (the shared client) under `data_source_robots:<scheme>:<authority>`, TTL **86400s** (1 day) for a successful parse, **900s** for a negative/failed result (which is cached as a sentinel `{"__robots_unavailable": true}` that the read path maps back to "default allow"). robots matching uses the **same User-Agent** the connection factory advertises on real fetches (`HttpConnectionFactory.user_agent`) — a rule keyed to a different UA group won't apply.

Inspect the cached ruleset for a host:

```bash
# Read the cached parsed robots rules (DB 0). authority = host[:port-if-non-default].
redis-cli -n 0 GET 'data_source_robots:https:api.example.com' | jq
# A real block looks like:  {"rules":[{"allow":false,"pattern":"/v1/"}], "crawl_delay": null}
# default-allow sentinel:    {"__robots_unavailable": true}   (fetch failed/missing — NOT a block)
# permissive (loaded, no rules for us):  {"rules":[], "crawl_delay": null}

# See the actual robots.txt the host serves (sanity-check the rule is real)
curl -s https://api.example.com/robots.txt
```

Clear the cache to force an immediate re-fetch + re-parse (e.g. after the upstream un-Disallows a path, or to drop a stale negative sentinel without waiting out the TTL):

```bash
# Drop one host's cached ruleset; the next poll re-fetches robots.txt and re-parses.
redis-cli -n 0 DEL 'data_source_robots:https:api.example.com'
# Or sweep all cached robots rulesets (use sparingly — forces a robots re-fetch per host)
redis-cli -n 0 --scan --pattern 'data_source_robots:*' | xargs -r redis-cli -n 0 DEL
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Monitor never fetches a path you expect; source has `respect_robots: true` | A loaded robots.txt has a real `Disallow` matching the path (the **only** thing that blocks) | Read the cached ruleset (`GET data_source_robots:<scheme>:<authority>`); confirm against the live `/robots.txt`. If the upstream changed it, `DEL` the key to re-parse |
| robots was un-Disallowed upstream but the monitor still skips | The 1-day (86400s) cached ruleset is stale | `DEL` the host's `data_source_robots:*` key to force an immediate re-fetch; otherwise it self-corrects within a day |
| A `__robots_unavailable` sentinel is cached but robots.txt is actually fine | A transient fetch failure (timeout / SSRF / oversized) was negatively cached for 900s | This is **default-allow** — it does **not** block. If you want a fresh parse sooner, `DEL` the key; otherwise it re-probes in ≤15 min |
| robots changes have no effect at all | `respect_robots` is `false` (the default) — robots is never consulted | robots applies only when `respect_robots: true`; if you only set `crawl_delay_seconds`, the robots.txt `Crawl-delay` is **not** read |

### pacing causing deferred polls

Per-host pacing is **deferral, not failure** — and that distinction is the whole point. When a source is paced and its host was hit within the min-interval, `MonitorService#poll_subscription` calls `subscription.schedule_next_poll!` and **returns without recording a failure** — the poll simply rolls to a later tick. This is **expected back-pressure** when `crawl_delay_seconds` (or a robots `Crawl-delay`) is throttling a host, not a problem to fix.

The min-interval the monitor enforces is `max(effective_crawl_delay, HostPacer::DEFAULT_MIN_INTERVAL_SECONDS)` where the floor is **1 second**. The effective crawl-delay is resolved by `RobotsService#crawl_delay`: when `respect_robots` is on it prefers the robots.txt `Crawl-delay` and falls back to the source's `crawl_delay_seconds`; otherwise it uses `crawl_delay_seconds` directly (no robots fetch). The last-request timestamp lives in **Redis DB 0** under `data_source_pacer:<host>` (TTL 86400s), stamped via `HostPacer.touch` **only after a successful poll**. `HostPacer.ready?` **never sleeps** — pacing is achieved purely by deferring work across ticks, which is why the interactive path is never slowed.

**The deferred-not-failed signal** — how to tell a deferral apart from an error:

- The monitor logs an **info** line (not a warn/error): `subscription <id> deferred: host pacing (<host>)` (quota deferrals log `deferred: quota (<limit>)`).
- The subscription's `consecutive_failures` does **not** increment and `status` stays `active` (a deferral never touches the failure counter or trips the `error` status). `last_polled_at` is also **not** advanced — only `next_poll_at` moves.
- The monitor-tick summary counts the subscription in **neither** `changed` nor `errors`; it just isn't polled this tick.

```bash
# Deferrals are INFO, not errors. Tail the monitor and look for "deferred: host pacing".
journalctl -u powernode-backend@default -f | grep -E 'deferred: (host pacing|quota)'

# Inspect a host's last-request stamp (epoch seconds). A recent value means the
# next poll within min-interval will defer.
redis-cli -n 0 GET 'data_source_pacer:api.example.com'

# Force the next poll to NOT pace (clears the stamp) — use only to break a stuck cadence.
redis-cli -n 0 DEL 'data_source_pacer:api.example.com'
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Subscription polls far less often than its cadence; **no** failures recorded | Host pacing is **deferring** every tick — `crawl_delay_seconds` (or robots `Crawl-delay`) exceeds the poll cadence | Expected throttle. Confirm via the `deferred: host pacing` info log + flat `consecutive_failures`. Lower `crawl_delay_seconds` (or the robots `Crawl-delay`) if you need a tighter cadence |
| Polls are minimum 1s apart even with `crawl_delay_seconds` unset | The `DEFAULT_MIN_INTERVAL_SECONDS = 1` floor applies once **any** politeness is enabled (e.g. `respect_robots: true`) | Expected — 1s/host is the conservative background floor. There is no way below it while politeness is on; disable politeness entirely (both `respect_robots: false` and no `crawl_delay_seconds`) to remove pacing |
| Operator can't tell deferral from failure | Deferrals are **info** logs and don't bump `consecutive_failures`; failures go through `record_failure!` | Check `consecutive_failures` / `status` — a paced subscription stays `active` with a flat counter; an erroring one climbs toward `status: "error"` |
| Two hosts on the same source pace independently | Pacing is **per host** (`data_source_pacer:<host>`), keyed off the source's `api_base_url` host | Expected; a source whose base URL host is missing/unparseable is **skipped** for pacing entirely (no defer) |
| Pacing seems to stop working entirely | Redis fault — `HostPacer` **fails open** (`ready?` returns true, `touch` is a no-op) | A Redis outage degrades to "no pacing", never a wedge. Restore Redis; pacing resumes once stamps can be written/read |

## Nightly schema sync (Phase 4)

A third thin worker cron — `AiDataSourceSchemaSyncJob` (`0 4 * * *`, daily at 04:00 UTC, queue `ai_orchestration`) — POSTs the mTLS worker-only internal endpoint `POST /api/v1/internal/ai/data_sources/schema_sync_tick` (handled by `Api::V1::Internal::Ai::DataSourcesController#schema_sync_tick`), which calls server-side `Ai::DataSources::SchemaSyncService.new.sync(limit:)`. Like the monitor/health ticks it holds **no business logic** — it triggers, the server does the work. `schema_sync_tick` accepts an optional `limit` (clamped 1..1000, default 100); the service returns `{ synced:, errors: [{endpoint_id:, error:}] }`.

| Job class | Cron | Internal endpoint (POST) | Server entry point | Returns |
|-----------|------|--------------------------|--------------------|---------|
| `AiDataSourceSchemaSyncJob` | `0 4 * * *` | `/api/v1/internal/ai/data_sources/schema_sync_tick` | `SchemaSyncService#sync(limit: 100)` | `{ synced:, errors: [{endpoint_id:, error:}] }` |

**What it samples.** `SchemaSyncService#sync` walks endpoints that are **due** — `track_schema = TRUE` **OR** `response_schema` blank (`NULL` / `{}`) — on **active** sources only (account-scoped when constructed with an account; the cron runs account-less = all accounts). For each due endpoint it runs a **governed sample fetch** through the full `QueryService` (same kill-flag / quota / cache / circuit-breaker / decode pipeline as any read, `params: {}`), infers a top-level-**array** JSON-Schema from the canonical records (the same shape `QueryService#infer_schema` emits, so drift comparisons across the two entry points are apples-to-apples), records a version via `SchemaDriftService#record_version!`, and — **only when the endpoint had no baseline** — seeds the inferred schema onto `endpoint.response_schema` (via `update_column`, off the audit/validation path).

> **First-run sampling fan-out caveat.** The due-clause matches **every endpoint with a blank `response_schema`** — which, on first run after enabling Phase 4, is *most* endpoints (only those that already captured a schema are excluded). Each due endpoint triggers one **live** sample fetch against its upstream. So the **first** nightly tick can fan out into a burst of outbound calls (up to `limit`, default 100, per tick) across many sources. Mitigations baked in:
>
> - The sample fetch respects each source's `check_quota!` — a **throttled / blocked / errored** sample is recorded as a **skip, not a hard error** (`sync_endpoint` returns `:skipped`, it is not counted in `synced` and not added to `errors`), so a busy source does not spam the error list or burn its budget.
> - Per-endpoint failures are caught and collected into `errors`; one bad endpoint **never aborts the batch** (mirrors `MonitorService#tick`).
> - `limit` (default 100) caps endpoints per tick — a large backlog drains over successive nightly runs (or trigger a one-off `schema_sync_tick` POST with a higher `limit`). Once an endpoint's `response_schema` is seeded, it drops out of the due set unless it also has `track_schema = true`.
>
> **Operational guidance:** the very first post-upgrade 04:00 tick is the heavy one. If a large account has thousands of baseline-less endpoints, watch the source quotas / upstream rate limits that night, and let subsequent ticks (which see far fewer due endpoints) settle the steady state.

```bash
# Tail the schema-sync cron summary (synced / errors per tick)
journalctl -u powernode-worker@default -f | grep AiDataSourceSchemaSyncJob
```

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| First 04:00 tick fans out to many upstreams | Most endpoints are baseline-less (blank `response_schema`) so all are "due" | Expected once; watch source quotas that night — throttled samples skip safely; later ticks see far fewer due endpoints |
| `synced` is 0 but no `errors` | Every sample was throttled / blocked / returned no records (all skipped) | Confirm sources have quota headroom and the endpoints actually return array records; skips are not failures |
| An endpoint never gets a baseline schema | Its sample fetch keeps failing or skipping (quota, upstream down, non-array body) | Check the source `quota_status` and run a manual `data_source_query`; a non-array response yields an empty-properties array schema |
| Drift versions appearing nightly without a live read | Expected — the sync tick *is* a live sample fetch on `track_schema` endpoints | This is the batch counterpart to inline drift; see [Monitoring schema-drift signals](#monitoring-schema-drift-signals) |

## Outbound pagination operational limits (Phase 4)

When an endpoint sets a non-blank `pagination` config with a supported `type` (`offset` / `page` / `cursor` / `link`), `QueryService#perform_fetch` drives `Ai::DataSources::Paginator` to walk the upstream's pages and concatenate the decoded canonical records into a **single** `FetchEnvelope` (the [guide](../guides/data-sources.md#configuring-outbound-pagination-phase-4) covers the config keys). A **blank `pagination`** (the column default `{}`) is OFF — the ordinary single request runs, byte-identical to pre-Phase-4. The operational rails:

- **`HARD_MAX_PAGES = 20`** — an absolute ceiling on pages per fetch, independent of and **capping** the endpoint's configured `max_pages`. The effective cap is `config["max_pages"]` clamped to `[1, HARD_MAX_PAGES]`; an unset/`<=0` `max_pages` defaults to the full 20. This is the runaway-upstream safety rail — no single fetch can issue more than 20 outbound requests regardless of config.
- **Per-page quota** — the parent source's `check_quota!` is re-evaluated **before each subsequent page** (`paginate_quota_veto` → `quota_exceeded?`, the same per-source + per-agent budget the single-request path enforces). A veto **stops the walk and keeps the partial result** (`stopped_reason: "quota:<limit>"`) rather than blowing past the budget — a paginated walk can therefore return fewer pages than configured when the source is near its limit.
- **Other stop conditions:** an **empty page** (zero records → ran off the end), the strategy terminator (no next cursor / no `rel="next"` link), or a **failed page** (non-2xx / transport — the records gathered so far are returned and the real outcome is recorded). The walk **never raises**: a callback error ends it and returns what was gathered.
- **Default page size** for `offset`/`page` strides when no `limit`/`page_size` is configured is `DEFAULT_PAGE_SIZE = 100`.

The aggregate fetch surfaces the walk in provenance — `provenance.pagination = { type, pages_fetched, stopped_reason, truncated }` — and appends `paginated_<N>_pages` to `provenance.anomalies` (plus `pagination_truncated` when the walk hit `max_pages` with more likely available). `truncated: true` / the `pagination_truncated` anomaly is the signal that the cap (configured or `HARD_MAX_PAGES`) cut the result short.

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Paginated result looks truncated (`pagination_truncated` anomaly) | Hit `max_pages` (configured or the `HARD_MAX_PAGES = 20` ceiling) with more pages available | Raise the endpoint's `max_pages` (still capped at 20), or narrow the query so the result fits; you cannot exceed 20 pages per fetch |
| Walk stops early with `stopped_reason: "quota:…"` | The per-page `check_quota!` vetoed the next page | Expected back-pressure — the partial result is returned; raise the source `rate_limits` or reduce paginated reads |
| Cursor pagination stops after one page | `cursor_path` doesn't resolve in the body, or the cursor is unchanged/blank | Verify `cursor_path` (dotted path / JSON pointer) against the actual response JSON |
| `link` pagination never advances | The upstream omits an RFC 5988 `Link` header with `rel="next"` | Confirm the upstream sends `Link: <…>; rel="next"`; otherwise use `offset`/`page` |
| Far more outbound calls than expected from one fetch | Pagination is enabled and the upstream has many pages | Each fetch can issue up to `max_pages` (≤20) requests; budget source quota accordingly |

## Sync & Health Jobs

Provider model sync and health monitoring for data sources run in the worker. Jobs tag logs with `data_source_id` and post health transitions via the audit log, so operators see state flips in both `Monitoring` dashboards and the audit log (where applicable). The Phase-3 monitor + health crons are documented above in [Monitoring a source for changes](#monitoring-a-source-for-changes-phase-3); the Phase-4 nightly schema-sync cron is in [Nightly schema sync (Phase 4)](#nightly-schema-sync-phase-4).

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
| Model — Data Source | `server/app/models/ai/data_source.rb` (Phase 4: free-form `source_type`, `SUGGESTED_SOURCE_TYPES`/`SOURCE_TYPES` alias, `category` + `protocol` attrs, `by_type`/`by_category` scopes; `record_query!`, `recalculate_effectiveness!`, `usage_success_rate`) |
| Model — Endpoint (Phase 2b/3/4) | `server/app/models/ai/data_source_endpoint.rb` (2b: `track_schema`/`quality_checks_enabled`/`quarantine_on_failure`/`sla_max_age_seconds`/`owner`/`contract`; 3: `stale_while_revalidate_seconds`/`stale_if_error_seconds`; 4: `pagination` jsonb; `has_many :schema_versions`/`:expectations`/`:subscriptions`) |
| Model — Subscription (Phase 3) | `server/app/models/ai/data_source_subscription.rb` (`POLL_FREQUENCIES`, `STATUSES`; `.active`/`.due_for_poll`/`.for_data_source`/`.for_endpoint`; `record_poll!`/`record_failure!`/`schedule_next_poll!`/`activate!`/`pause!`) |
| Model — Credential | `server/app/models/ai/data_source_credential.rb` |
| Brokers — base + registry (Phase 4b-2a) | `server/app/services/ai/data_sources/credentials/base_broker.rb` (`#acquire` fail-safe template, `#broker_http_connection` SSRF guard, `#audit_log` — `broker=`/`source=`/`outcome=`), `credentials/registry.rb` (`BROKERS` map, `.for`; unknown ⇒ `StaticBroker`) |
| Brokers — concrete (Phase 4b-2a) | `credentials/static_broker.rb` (no-op), `credentials/aws_sts_broker.rb` (`AssumeRole`), `credentials/aws_sts_web_identity_broker.rb` (`AssumeRoleWithWebIdentity`, OIDC token via inline/file/`token_url`), `credentials/oauth2_client_credentials_broker.rb` (`client_credentials` grant, `max_redirects: 0`), `credentials/vault_dynamic_broker.rb` (dynamic mount), `credentials/presigned_url_broker.rb` (S3 presign / Azure SAS) |
| Broker — cache + value object (Phase 4b-2a) | `credentials/broker_cache.rb` (`NAMESPACE = "ds_cred_broker:"`, `MIN_TTL = 5`, `LOCK_TTL = 10`, `.fetch` singleflight, `.ttl_with_skew`; fail-open), `credentials/brokered_credential.rb` (signer contract, redacted `#inspect`/`#to_s`, `#expires_at`/`#expired?`/`#presigned_url`) |
| QueryService brokering wiring (Phase 4b-2a) | `server/app/services/ai/data_sources/query_service.rb` (`#resolve_credential`, `#maybe_broker_credential`, `#broker_config`; presigned honor hook `#presigned_url_for`) |
| SSRF guard + outbound mTLS (Phase 4b-2b) | `server/app/services/ai/data_sources/http_connection_factory.rb` (`SsrfError`, `.validate_url!`, `SsrfGuardMiddleware`, `.user_agent`; mTLS: `MtlsConfigError`, `.client_ssl_options`, `.load_mtls_material`, `.read_vault_secret` with `cache: false`, `.build_ssl_hash`; `required` ⇒ fail-closed, optional ⇒ degrade to plain TLS) |
| Service — Governance (Phase 4b-2b) | `server/app/services/ai/data_sources/governance_service.rb` (`#authorize` — ABAC `Ai::AgentPrivilegePolicy` + compliance `Ai::CompliancePolicy` `data_access`; `#mask_records` via `Ai::Security::PiiRedactionService`; fail-open on infra / deny on explicit; `RESOURCE_PREFIX`, `MAX_MASKED_VALUES = 50_000`) |
| Model — Policy violation | `server/app/models/ai/policy_violation.rb` (`.for_source(type, id)`, `.open`/`.recent`; `resolve!`/`dismiss!`) recorded by `Ai::CompliancePolicy#record_violation!` on a blocking compliance deny |
| QueryService governance wiring (Phase 4b-2b) | `server/app/services/ai/data_sources/query_service.rb` (`#governance_authorize`, `#blocked_by_governance_envelope` — `provenance.policy_decision` + `governance_blocked` anomaly; `#mask_response_records` — `provenance.masking_applied`/`masked_field_count`; cache holds RAW, masking per-request) |
| Service — Transform pipeline (Phase 4b-3a) | `server/app/services/ai/data_sources/transform_service.rb` (`.new(config).apply(records)`; ordered `flatten`/`unnest`(alias `explode`)/`select`(alias `project`)/`rename`/`computed` pipeline; whitelisted `computed` interpreter — NO eval/send; `MAX_RECORDS = 50_000`, `MAX_FLATTEN_DEPTH = 32`, `MAX_PIPELINE_STEPS = 100`; pure/stateless, fully rescued — blank `{}` == passthrough) |
| Model — Endpoint transforms (Phase 4b-3a) | `server/app/models/ai/data_source_endpoint.rb` (`transforms` jsonb default `{}`; `transforms?` predicate — non-empty `"pipeline"` == ON, blank == OFF) |
| QueryService transform + dry-run wiring (Phase 4b-3a) | `server/app/services/ai/data_sources/query_service.rb` (transform: `#apply_transforms`/`#transforms_enabled?` run post-normalize/pre-cache, set `provenance[:transforms_applied]` + `transform_error` anomaly; dry-run: `dry_run:` ctor flag, `STATUS_DRY_RUN`, `#dry_run_envelope`/`#build_cost_estimate`/`#cache_hit_available?` via `read_stale`/`#recent_query_stats` (`DRY_RUN_HISTORY_SAMPLE = 20`)/`#estimated_cost_usd` — short-circuits after kill/quota/governance, no side effects) |
| Cache tag invalidation (Phase 4b-3a) | `server/app/services/ai/data_sources/response_cache_service.rb` (`TAG_NAMESPACE = "data_source_cache:tag"`, `.invalidate_by_tag`, `.default_tags` — `ds:`/`endpoint:`/`slug:`; `#index_tags` on write — TTL `ttl+grace`, extend-only, self-expiring; fail-open) |
| MCP cache-invalidation action (Phase 4b-3a) | `server/app/services/ai/tools/data_source_tool.rb` (`data_source_invalidate_cache` — `INVALIDATE_CACHE_PERMISSION = "ai.data_sources.update"` or `.manage`; hard-deny (no proposal); `tag` > scope precedence; `#invalidate_cache`) registered in `platform_api_tool_registry.rb` |
| Migration (Phase 4b-3a) | `server/db/migrate/20260607000000_add_transforms_to_ai_data_source_endpoints.rb` (adds `ai_data_source_endpoints.transforms` jsonb default `{}`; no index — config blob read with its endpoint row) |
| Service — Config portability (Phase 4b-3b) | `server/app/services/ai/data_sources/config_portability_service.rb` (`#export`/`#import`/`#snapshot!`/`#rollback!`; `SOURCE_EXPORT_KEYS`/`ENDPOINT_EXPORT_KEYS` allowlists, `AUTH_CONFIG_ALLOWED_KEYS` + `SECRET_KEY_SUBSTRINGS`/`SECRET_KEY_EXACT` denylist, `#sanitize_auth_config`/`#scrub_value` — credentials never traversed, `external_id` excluded; transactional import, slug/name de-dup, `persist_manifest_snapshot` retry-on-collision) |
| Library — Templates (Phase 4b-3b) | `server/app/services/ai/data_sources/template_library.rb` (`.all`/`.find`/`.install`; credential-free starter manifests `generic-rest-json`/`rss-feed`/`open-meteo-weather`/`generic-graphql`; `base_manifest`/`default_source`; install routes through `ConfigPortabilityService#import` — re-sanitizes, never sets credentials) |
| Model — Config version (Phase 4b-3b) | `server/app/models/ai/data_source_config_version.rb` (`CREATED_BY_TYPES` auto/manual/rollback; `for_data_source`/`ordered`/`latest_first`; `.next_version_for`; credential-free `manifest` jsonb — SECURITY invariant) |
| Migration (Phase 4b-3b) | `server/db/migrate/20260607010000_create_ai_data_source_config_versions.rb` (append-only `ai_data_source_config_versions`; unique `(ai_data_source_id, version)`, FK index suppressed — covered by the composite's leftmost prefix) |
| MCP onboarding actions (Phase 4b-3b) | `server/app/services/ai/tools/data_source_tool.rb` (`data_source_export`/`_import`/`_list_templates`/`_install_template`/`_config_versions`/`_rollback_config`; `MUTATION_PERMISSIONS` — import/install ⇒ `.create`, rollback ⇒ `.manage`; proposal fallback with `sanitized_manifest_for_proposal`; `#rollback_config` surfaces `restored_version: nil` + errors as a failure) |
| Model — Schema version (Phase 2b) | `server/app/models/ai/data_source_schema_version.rb` (`CLASSIFICATIONS`; `for_endpoint`/`ordered`/`latest_first`/`breaking`) |
| Model — Quality expectation (Phase 2b) | `server/app/models/ai/data_source_expectation.rb` (`RULE_TYPES`, `SEVERITIES`; `active`/`errors`) |
| Model — KG node | `server/app/models/ai/knowledge_graph_node.rb` (`data_source` entity type, `.data_source_nodes`, `.for_data_source`) |
| Service — KG bridge (Phase 2a) | `server/app/services/ai/data_source_graph/bridge_service.rb` (`sync_data_source`, `sync_all_data_sources`) |
| Service — Semantic discovery (Phase 2a) | `server/app/services/ai/data_sources/semantic_discovery_service.rb` (`WEIGHTS`, `#discover`) |
| Service — Schema drift (Phase 2b) | `server/app/services/ai/data_sources/schema_drift_service.rb` (`#diff`, `#record_version!`; `INITIAL`/`NONE`/`ADDITIVE`/`BREAKING`) |
| Service — Quality (Phase 2b) | `server/app/services/ai/data_sources/quality_service.rb` (`#evaluate`) |
| Service — OpenAPI import (Phase 2b) | `server/app/services/ai/data_sources/open_api_import_service.rb` (`#import`) |
| Service — Contract (Phase 2b) | `server/app/services/ai/data_sources/contract_service.rb` (`#validate`) |
| QueryService wiring (Phase 2b/3/4) | `server/app/services/ai/data_sources/query_service.rb` (2b: `#apply_observability_stages`, `#track_schema_drift`, `#evaluate_quality`, `#quarantine_records`; 3: `#maybe_serve_stale_if_error`, `#build_stale_if_error_result`; 4: `#pagination_enabled?`, `#perform_paginated_fetch`, `#dispatch_page`, `#paginate_quota_veto`) |
| Service — Monitor (Phase 3) | `server/app/services/ai/data_sources/monitor_service.rb` (`#tick`, `#health_tick`, `#refresh!`; `CHANGE_SIGNAL_KEY = "data_source_changed"`; pacing: `#pacing_defer?`/`#effective_crawl_delay`/`#touch_host_pacer`; incremental: `#apply_sync_cursor`/`#extract_sync_cursor`) |
| Service — Incremental sync | `server/app/services/ai/data_sources/incremental_sync.rb` (pure/stateless `apply_cursor`/`extract_cursor`/`cursor_from_body`; digs `cursor_param`/`cursor_path` from `endpoint.incremental`; watermark on `subscription.sync_cursor`) |
| Service — robots.txt | `server/app/services/ai/data_sources/robots_service.rb` (`#allowed?`/`#crawl_delay`; **DEFAULT ALLOW**; Redis `data_source_robots:<scheme>:<authority>`, TTL 86400/900; only on `respect_robots`) |
| Service — Host pacer | `server/app/services/ai/data_sources/host_pacer.rb` (`.ready?`/`.touch`/`.seconds_until_ready`; never sleeps — defers across ticks; Redis `data_source_pacer:<host>`; `DEFAULT_MIN_INTERVAL_SECONDS = 1`; fail-open) |
| Adapters — registry + protocols (Phase 4) | `server/app/services/ai/data_sources/adapters/registry.rb` (`ADAPTERS`, `.for`, `known_protocol?`), `adapters/graphql_adapter.rb` (POST `{query,variables}`, `data` unwrap), `adapters/rss_adapter.rb` (`RestAdapter` subclass; canonical feed records) |
| Service — Paginator (Phase 4) | `server/app/services/ai/data_sources/paginator.rb` (`SUPPORTED_TYPES` offset/page/cursor/link, `HARD_MAX_PAGES = 20`, `DEFAULT_PAGE_SIZE = 100`; `#each_page`) |
| Service — Schema sync (Phase 4) | `server/app/services/ai/data_sources/schema_sync_service.rb` (`#sync(limit:)`, due = `track_schema` OR blank `response_schema` on active sources; throttled sample = skip) |
| Decoder — XML (Phase 4 fix) | `server/app/services/ai/data_sources/decoders/xml.rb` (repeated siblings aggregate via `Array.wrap` — fixes the `Array()` hash-explosion) |
| Cache SWR/SIE (Phase 3) | `server/app/services/ai/data_sources/response_cache_service.rb` (`.read_stale`, `#grace_window`, `#schedule_background_refresh`) |
| Controller — Sources | `server/app/controllers/api/v1/ai/data_sources_controller.rb` (`#discover`; subscription permission gating) |
| Controller concern — Endpoints (Phase 2b/3) | `server/app/controllers/concerns/ai/data_source_endpoints.rb` (2b: `#schema_history`, `#quality`, `#contract`, `#introspect`; 3: `#subscriptions_index`, `#subscriptions_create`, `#subscriptions_destroy`) |
| Internal controller (Phase 3/4) | `server/app/controllers/api/v1/internal/ai/data_sources_controller.rb` (`#monitor_tick`, `#health_tick`; 4: `#schema_sync_tick`; mTLS worker-only, `Internal::Ai` namespace) |
| Worker crons (Phase 3/4) | `worker/app/jobs/ai_data_source_monitor_job.rb` (`*/5`), `worker/app/jobs/ai_data_source_health_job.rb` (`*/10`), `worker/app/jobs/ai_data_source_schema_sync_job.rb` (`0 4 * * *`) — thin triggers to the internal ticks |
| Controller — Credentials | `server/app/controllers/api/v1/ai/data_source_credentials_controller.rb` |
| Serialisation concern (Phase 4) | `server/app/controllers/concerns/ai/data_source_serialization.rb` (effectiveness/usage fields; 4: `serialize_data_source` emits `category`+`protocol`, `serialize_data_source_endpoint` emits `pagination`) |
| Controller params/filters (Phase 4) | `server/app/controllers/api/v1/ai/data_sources_controller.rb` (`data_source_params` permits `:category`/`:protocol`; `apply_filters` `by_category(params[:category])`), `concerns/ai/data_source_endpoints.rb` (`endpoint_params` permits `pagination: {}`) |
| Migration (Phase 4) | `server/db/migrate/20260606122000_*.rb` (adds `ai_data_sources.category` + partial index, `ai_data_source_endpoints.pagination` jsonb; backfills `category` from legacy `source_type`). `20260606120000_*` adds `ai_data_sources.protocol` (default `"rest"`) |
| MCP tool | `server/app/services/ai/tools/data_source_tool.rb` (`data_source_discover` / `_provenance` / `_impact`; 2b: `_schema_history` / `_quality` / `_contract` / `_introspect`; 3: `_subscribe` / `_unsubscribe`, `STREAM_ACTIONS` gated by `ai.data_sources.stream`) |
| Routes | `server/config/routes.rb` (`resources :data_sources`; collection `post :discover`; 2b: `endpoints/:endpoint_id/{schema_history,quality,contract}`, `post :introspect`; 3: `{get,post} :subscriptions` + `delete subscriptions/:subscription_id`; internal `ai/data_sources/{monitor_tick,health_tick}`; 4: internal `ai/data_sources/schema_sync_tick`) |
| Permissions (Phase 3) | `server/config/permissions.rb` (`ai.data_sources.stream` — granted to `member`/`manager`/`ai_specialist`) |

---

## Related runbooks

- [data-source-fetch-pipeline.md](data-source-fetch-pipeline.md) — Phase 1: the governed fetch pipeline (kill flag, per-agent fairness, response cache, circuit breaker, SSRF guard, decode/normalize, cost, hash-chained query log) and its troubleshooting
- [../guides/data-sources.md](../guides/data-sources.md) — Phase 2a/2b/3/4 from the agent/author angle: discover → describe → query, how effectiveness accrues, reading trust signals, enabling per-endpoint quality/drift/contracts, creating monitoring subscriptions, enabling SWR/stale-if-error, and onboarding GraphQL/RSS sources + configuring outbound pagination
- [ai-operations.md](ai-operations.md) — AI provider sister system; same encryption / credential patterns
- [worker-operations.md](worker-operations.md) — Sync / health jobs schedule

## Materials previously at

- `docs/platform/DATA_SOURCES.md`

_Last verified: 2026-06-07 (Phase 4b-3b onboarding portability + config versioning/rollback + template library + credential-free export contract added)_
