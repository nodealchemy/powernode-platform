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

Provider model sync and health monitoring for data sources run in the worker. Jobs tag logs with `data_source_id` and post health transitions via the audit log, so operators see state flips in both `Monitoring` dashboards and `Trading::AuditLog` (where applicable). The Phase-3 monitor + health crons are documented above in [Monitoring a source for changes](#monitoring-a-source-for-changes-phase-3); the Phase-4 nightly schema-sync cron is in [Nightly schema sync (Phase 4)](#nightly-schema-sync-phase-4).

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
| SSRF guard | `server/app/services/ai/data_sources/http_connection_factory.rb` (`SsrfError`, `.validate_url!`, `SsrfGuardMiddleware`, `.user_agent`) |
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

_Last verified: 2026-06-06 (Phase 4b-2a credential brokering added)_
