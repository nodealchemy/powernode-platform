# Data Sources

**Managed integration for external data APIs with quota tracking and credential management**

**Version**: 1.0 | **Last Updated**: April 2026

---

## Overview

Data Sources is the unified registry for external data providers that the platform consumes — weather, economic indicators, sports, news, etc. Each source has a stable configuration (capabilities, rate limits, default parameters), separately-encrypted credentials with first-class multi-credential support, and per-source health tracking. Rate-limiting is enforced client-side via `check_quota!` before outbound calls, and admins can test connections and rotate credentials without redeploying.

## Supported Source Types

From `Ai::DataSource::SOURCE_TYPES`:

| Type | Description |
|------|-------------|
| `noaa_ncei` | NOAA National Centers for Environmental Information — historical climate data |
| `noaa_gfs` | NOAA Global Forecast System — numerical weather prediction |
| `noaa_observations` | NOAA current observations |
| `open_meteo` | Open-Meteo — free weather API (no key for historical/forecast) |
| `fred` | Federal Reserve Economic Data — macroeconomic indicators |
| `yahoo_finance` | Yahoo Finance — market data |
| `espn` | ESPN — sports data |
| `newsapi` | NewsAPI — news aggregation |
| `custom` | Arbitrary custom-adapter source |

Health status values: `healthy`, `degraded`, `critical`, `unknown`.

---

## Models

### Ai::DataSource (`ai_data_sources`)

```ruby
belongs_to :account
has_many :credentials, class_name: "Ai::DataSourceCredential",
         foreign_key: "ai_data_source_id", dependent: :destroy

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

- `active_credential` — returns the active+default credential, else most recent active credential
- `api_key` — convenience delegate to `active_credential.decrypted_api_key`
- `healthy?` — active + health status in `{healthy, unknown}`
- `check_quota!` — returns `{ allowed: true }` or `{ allowed: false, retry_after: N, limit: "name" }` based on current per-minute/per-hour/per-day usage

**Scopes:** `active`, `by_type(type)`, `for_account(account)`, `ordered_by_priority`, `requiring_auth`.

### Ai::DataSourceCredential (`ai_data_source_credentials`)

Encrypted credential records bound to a DataSource. Each data source can have multiple credentials (e.g., rotating keys, per-environment keys). Exactly one can be marked default per source. `decrypted_api_key` returns the plaintext for outbound requests — handled inside services only, never exposed on the wire.

---

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

Credentials obey the cryptographic-material safety rules in the root `CLAUDE.md` — API keys are never returned in responses or logged; `decrypted_api_key` is accessed only from backend services that need to make outbound HTTP calls.

---

## Quota Enforcement Pattern

Before any outbound request:

```ruby
source = Ai::DataSource.find_by!(slug: "noaa_gfs")
quota = source.check_quota!
unless quota[:allowed]
  raise "Rate limited on #{quota[:limit]}, retry_after=#{quota[:retry_after]}s"
end

# Proceed with API call using source.api_key (if required)
```

`check_quota!` reads from `current_quota_usage` (hour/minute/day counters tracked per source). Exceeding any configured limit returns a non-allowed response with `retry_after`.

---

## Sync & Health Jobs

Provider model sync and health monitoring for data sources run in the worker. Jobs tag logs with `data_source_id` and post health transitions via the audit log, so operators see state flips in both `Monitoring` dashboards and `Trading::AuditLog` (where applicable).

---

## Key Files

| Role | Path |
|------|------|
| Model — Data Source | `server/app/models/ai/data_source.rb` |
| Model — Credential | `server/app/models/ai/data_source_credential.rb` |
| Controller — Sources | `server/app/controllers/api/v1/ai/data_sources_controller.rb` |
| Controller — Credentials | `server/app/controllers/api/v1/ai/data_source_credentials_controller.rb` |
| Serialization concern | `server/app/controllers/concerns/ai/data_source_serialization.rb` |
| Routes | `server/config/routes.rb` (`resources :data_sources`) |

## See Also

- [AI_ORCHESTRATION_GUIDE.md](AI_ORCHESTRATION_GUIDE.md) — Core AI platform architecture
- [AI_PROVIDER_ROUTING.md](AI_PROVIDER_ROUTING.md) — Sister concept for AI model providers (same encryption and credential patterns)
- [AI_SECURITY_GUARDRAILS.md](AI_SECURITY_GUARDRAILS.md) — Credential safety rules
