# Data Sources

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

## Sync & Health Jobs

Provider model sync and health monitoring for data sources run in the worker. Jobs tag logs with `data_source_id` and post health transitions via the audit log, so operators see state flips in both `Monitoring` dashboards and `Trading::AuditLog` (where applicable).

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
| Model — Data Source | `server/app/models/ai/data_source.rb` |
| Model — Credential | `server/app/models/ai/data_source_credential.rb` |
| Controller — Sources | `server/app/controllers/api/v1/ai/data_sources_controller.rb` |
| Controller — Credentials | `server/app/controllers/api/v1/ai/data_source_credentials_controller.rb` |
| Serialisation concern | `server/app/controllers/concerns/ai/data_source_serialization.rb` |
| Routes | `server/config/routes.rb` (`resources :data_sources`) |

---

## Related runbooks

- [ai-operations.md](ai-operations.md) — AI provider sister system; same encryption / credential patterns
- [worker-operations.md](worker-operations.md) — Sync / health jobs schedule

## Materials previously at

- `docs/platform/DATA_SOURCES.md`

_Last verified: 2026-05-17_
