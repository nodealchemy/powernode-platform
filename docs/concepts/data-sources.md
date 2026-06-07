# Data Sources

> Status: active

> How a declarative catalog, a template-driven endpoint layer, and a governed fetch pipeline let agents pull from any external API — where adding a new source is configuration, not code — plus the Phase-2a layer that lets agents *discover* the right source by intent and *evaluate* how much to trust it, and the Phase-2b layer that adds per-endpoint **data quality, schema-drift detection, and contracts** with zero overhead until you opt in.

## Table of Contents

- [What this concept covers](#what-this-concept-covers)
- [The generic protocol/adapter/decoder model](#the-generic-protocoladapterdecoder-model)
- [Data model](#data-model)
- [Catalog → endpoints](#catalog--endpoints)
- [The decode layer](#the-decode-layer)
- [Normalization](#normalization)
- [The QueryService pipeline](#the-queryservice-pipeline)
- [Response cache](#response-cache)
- [Security model](#security-model)
- [Provenance and the FetchEnvelope](#provenance-and-the-fetchenvelope)
- [Surfaces: REST + MCP](#surfaces-rest--mcp)
- [Frontend](#frontend)
- [Discovery & Evaluation (Phase 2)](#discovery--evaluation-phase-2)
- [Data quality, schema-drift & contracts (Phase 2b)](#data-quality-schema-drift--contracts-phase-2b)
- [Phase boundaries](#phase-boundaries)
- [Related concepts](#related-concepts)
- [Materials previously at](#materials-previously-at)

## What this concept covers

A **data source** is a registered external API — NOAA, Open-Meteo, FRED, Yahoo Finance, ESPN, NewsAPI, or any `custom` HTTP source — that AI agents and workflows can pull from under platform governance. The data-source subsystem turns "an agent needs weather data" into a single audited, cached, SSRF-guarded, redacted fetch that returns canonical records plus a complete provenance record.

The defining design principle is **a new source is config, not code**. A source is described by rows in the database (a catalog entry, its endpoints, its credentials) and three generic registries — protocol adapters, response decoders, and auth signers — pick the right behavior at runtime from those rows. There is zero per-source Ruby in the common case: the `rest`/`custom` protocols, every JSON/XML/CSV/NDJSON response shape, and the `none`/`api_key`/`bearer`/`aws_sigv4`/`hmac` auth schemes are all driven by stored templates and config. Adding a new bespoke protocol later means registering one class name in a registry; until then every unrecognized source degrades safely to the generic REST adapter and JSON decoder.

This document is the canonical reference for how the catalog, endpoint templates, decoders, normalization, the fetch pipeline, the response cache, and the security model compose. The **operational** counterpart — how to register a source, rotate a credential, and troubleshoot a failing integration — lives in [`operations/data-sources.md`](../operations/data-sources.md).

All backend code lives under `server/app/services/ai/data_sources/` (plus the shared `server/app/services/security/http_signature.rb`). The models are in the `Ai::` namespace; the table prefix is `ai_data_source*`.

## The generic protocol/adapter/decoder model

Three registries make the subsystem source-agnostic. Each follows the same shape used elsewhere in the codebase (e.g. `Ai::Providers::Sync::Generic`): a small static map keyed by a normalized token, resolved via `constantize` to sidestep autoload-order issues, with a generic fallback that **never raises** on an unknown token.

```mermaid
flowchart LR
    DS[Ai::DataSource row<br/>protocol + auth_scheme]
    EP[Ai::DataSourceEndpoint row<br/>path/query/body templates<br/>response_format + mapping]

    subgraph Registries["Runtime registries (token → class)"]
        AR[Adapters::Registry<br/>protocol → adapter]
        SR[Auth::SignerRegistry<br/>auth_scheme → signer]
        DR[Decoders::Registry<br/>format → decoder]
    end

    DS -->|protocol| AR
    DS -->|auth_scheme| SR
    EP -->|response_format| DR
    AR --> Req[build_request]
    SR --> Sign[sign! in place]
    DR --> Rec["decode → Array&lt;Hash&gt;"]
```

| Registry | Lookup key | Map | Generic fallback | Contract |
|----------|-----------|-----|------------------|----------|
| `Ai::DataSources::Adapters::Registry` | `data_source.protocol` | `rest`, `custom` → `RestAdapter` | `RestAdapter` (any unknown/blank protocol) | `.for(data_source)` → adapter with `build_request(endpoint:, params:)` + `parse(raw_body, endpoint:)` |
| `Ai::DataSources::Auth::SignerRegistry` | `data_source.auth_scheme` | `none`, `api_key`, `bearer`, `aws_sigv4`, `hmac` | `NoneSigner` (no-op) | `.for(auth_scheme)` → signer with `sign!(conn_or_env, credential:, config:)` |
| `Ai::DataSources::Decoders::Registry` | `endpoint.response_format` (cross-checked against the sniffed bytes) | `json`, `ndjson`, `xml`, `rss`, `atom`, `html`, `csv` | `Json` (unknown bodies are most often JSON-ish) | `.for(format:, content_type:)` → decoder with `decode(raw_body, endpoint:)` |

"Custom" deliberately maps to the same generic `RestAdapter` as `rest` — it means "a REST source with a hand-rolled template", not "needs its own adapter class". A truly bespoke protocol (GraphQL, SOAP, gRPC-gateway) is a future opt-in: register a class name in `Adapters::Registry::ADAPTERS` and it takes over; absent that, the source still works via REST.

## Data model

Four models under the `Ai::` namespace, all UUIDv7-keyed (see [`concepts/data-model.md`](./data-model.md)), scoped to an `Account`. The namespaced foreign key is `ai_data_source_id` throughout (per the `Ai::` → `ai_` convention).

```mermaid
erDiagram
    accounts ||--o{ ai_data_sources : owns
    ai_data_sources ||--o{ ai_data_source_endpoints : has
    ai_data_sources ||--o{ ai_data_source_credentials : has
    ai_data_sources ||--o{ ai_data_source_queries : "audit log"
    ai_data_source_endpoints ||--o{ ai_data_source_queries : "fetched via"
    ai_data_sources {
        uuid id PK
        uuid account_id FK
        string slug
        string source_type
        string protocol
        string auth_scheme
        jsonb auth_config
        string api_base_url
        jsonb rate_limits
        jsonb configuration
        string health_status
    }
    ai_data_source_endpoints {
        uuid id PK
        uuid ai_data_source_id FK
        string slug
        string http_method
        string path_template
        jsonb query_template
        jsonb body_template
        string response_format
        jsonb response_mapping
        jsonb response_schema
        integer cache_ttl_seconds
        boolean monitorable
    }
    ai_data_source_credentials {
        uuid id PK
        uuid ai_data_source_id FK
        string encrypted_api_key
        string encrypted_api_secret
        string vault_path
        datetime migrated_to_vault_at
        integer consecutive_failures
    }
    ai_data_source_queries {
        uuid id PK
        uuid ai_data_source_id FK
        uuid ai_data_source_endpoint_id FK
        string status
        string redacted_url
        string response_sha256
        jsonb metadata
    }
```

| Model | Table | Role |
|-------|-------|------|
| `Ai::DataSource` | `ai_data_sources` | The catalog entry. Carries `protocol`, `auth_scheme`, `auth_config`, the base URL, `rate_limits`, and `configuration`. `has_many :endpoints`, `:credentials`, `:queries`. Owns quota counting via `Powernode::Redis.client`. |
| `Ai::DataSourceEndpoint` | `ai_data_source_endpoints` | A declarative request template + response contract. Holds `path_template`/`query_template`/`body_template`, `response_format`, `response_mapping`, `response_schema`, `cache_ttl_seconds`, and the `monitorable` + change-detection columns. |
| `Ai::DataSourceCredential` | `ai_data_source_credentials` | Auth material. Rails-8 `encrypts` on `encrypted_api_key`/`encrypted_api_secret`, plus `vault_path` + `migrated_to_vault_at` for Vault-backed secrets. Tracks `consecutive_failures` for health. |
| `Ai::DataSourceQuery` | `ai_data_source_queries` | The **query/audit log**: one row per governed fetch (including cache hits and blocked/rate-limited attempts). Every operator-visible field is redacted before write; the row is hash-chained into the audit log. |

`source_type` is a fixed enum (`SOURCE_TYPES`: `noaa_ncei`, `noaa_gfs`, `noaa_observations`, `open_meteo`, `fred`, `yahoo_finance`, `espn`, `newsapi`, `custom`). `protocol` defaults to `rest`; `auth_scheme` defaults to `none`. JSON columns use lambda defaults per platform convention.

## Catalog → endpoints

The catalog (`Ai::DataSource`) holds the connection-level facts: where the API lives (`api_base_url`), how to authenticate (`auth_scheme` + `auth_config` + credentials), and the rate budget (`rate_limits`). Each endpoint (`Ai::DataSourceEndpoint`) is a **declarative template** for one operation against that source plus the contract for interpreting its response.

The generic `RestAdapter` (`adapters/rest_adapter.rb`) builds the outbound request entirely from the endpoint's stored templates and the caller's params — no per-source code:

- **`path_template`** — a string like `"/v1/stations/{station_id}/obs"`. Placeholders use single-brace `{name}` syntax. Path placeholders are RFC-3986 path-escaped (via `ERB::Util.url_encode`) so a caller-supplied segment can never break out of its path.
- **`query_template`** — a Hash like `{ "limit" => "{limit}", "fmt" => "json" }`. Nil-resulting entries are dropped so optional params don't emit empty keys.
- **`body_template`** — a Hash, sent only for `POST`/`PUT`/`PATCH`.

Interpolation has two modes. A value that is **exactly** one placeholder (`"{ids}"`) is replaced with the *raw* typed param (preserving Integer/Array/Boolean so structured bodies keep their JSON types). Any other string is treated as an embedded template and produces a string. **Unknown placeholders are left intact** rather than blanked, so a misconfiguration surfaces visibly instead of silently producing a malformed request.

`build_request` returns the canonical request envelope every layer agrees on:

```ruby
{ method:, url:, headers:, query:, body: }
# method  : upper-case verb String ("GET")
# url     : path after substitution (relative to api_base_url; the
#           connection factory resolves it against the base)
# headers : Hash<String,String> (static endpoint headers; auth applied later)
# query   : Hash of query-string params
# body    : Hash (dispatcher encodes), String (raw), or nil
```

The response side of an endpoint is `response_format` (which decoder), `response_mapping` (where the records live + normalization rules), and `response_schema` (an optional JSON Schema the decoded payload is validated against).

## The decode layer

Decoding turns raw response bytes into **canonical records** — always `Array<Hash>` — independent of the source. Three pieces collaborate, all under `decoders/`.

```mermaid
flowchart LR
    Raw[raw response bytes<br/>+ declared Content-Type]
    FD[FormatDetector.detect]
    Charset[Registry::Charset.to_utf8]
    Reg[Decoders::Registry.for]
    Dec["decoder.decode → Array&lt;Hash&gt;"]

    Raw --> FD
    FD -->|format + charset + mismatch| Reg
    Raw --> Charset --> Dec
    Reg --> Dec
```

**`FormatDetector`** (`decoders/format_detector.rb`) sniffs the on-the-wire format from the leading bytes (BOM, leading token, XML root probe) and cross-checks it against the provider's declared `Content-Type` and the endpoint's `expected_content_type`. Detection precedence, highest-confidence first: (1) magic-byte/structural sniff, (2) XML root probe, (3) declared `Content-Type`, (4) `endpoint.expected_content_type`, (5) `application/octet-stream` fallback. It returns a stable envelope and **never raises**:

```ruby
FormatDetector.detect(raw_body, declared_content_type:, endpoint:)
# => { format:, content_type:, mismatch:, charset:,
#      declared_format:, detected_format:, source: }
```

The key output is `mismatch` — true when a confident byte-level format disagrees with the declared one (e.g. an HTML error page served with a JSON `Content-Type`). Compatible pairs are tolerated: JSON↔NDJSON, and XML↔RSS↔Atom↔HTML. Downstream, `QueryService` records a mismatch as a `content_type_mismatch` anomaly.

**`Registry::Charset.to_utf8(raw, charset:)`** centralizes encoding so transcoding is uniform across every decoder: it strips the BOM, transcodes the declared/detected charset to UTF-8 with `invalid:/undef: :replace`, and scrubs invalid bytes so a few bad octets never abort an otherwise-valid document.

**Decoders** each implement `decode(raw_body, endpoint:) → Array<Hash>` and are stateless. They degrade to an **empty record set** (logged) rather than raising on malformed input:

| Decoder | Format(s) | Record location & behavior |
|---------|-----------|----------------------------|
| `Decoders::Json` | `json` (also the generic fallback) | `response_mapping["records_path"]` (dotted path or JSON pointer, e.g. `data.items` / `/data/items`). No path → top-level Array = records, Hash = one record, scalar wrapped as `{ "value" => … }`. |
| `Decoders::Ndjson` | `ndjson` | One parsed value per non-blank line; a malformed line is skipped (line independence is the point); non-Hash lines wrapped as `{ "value" => … }`. |
| `Decoders::Xml` | `xml`, `rss`, `atom`, `html` | `record_xpath` or `record_node` from mapping; else auto-detect `<item>`/`<entry>` feeds; else the most-repeated sibling element; else the whole doc. Nokogiri in recover mode, namespaces stripped, attributes prefixed `@`, mixed text under `#text`. |
| `Decoders::Csv` | `csv` (also TSV/semicolon/pipe) | Delimiter sniffed (or pinned via `response_mapping`); header row sniffed (non-numeric, unique) or positional `column_N`; malformed rows skipped. `"city,temp\nNYC,72"` → `[{"city"=>"NYC","temp"=>"72"}]`. |

Because the registry's fallback is `Json` and every decoder fails soft, an unrecognized or malformed body never crashes a fetch — it yields `[]` and an anomaly.

## Normalization

After decoding, `NormalizationService` (`normalization_service.rb`) coerces values into a canonical form and emits a **provenance log** describing every conversion. It is driven by `endpoint.response_mapping` and is useful even with sparse/empty rules (value-shape heuristics still apply).

```ruby
normalized, provenance = NormalizationService.new(rules).apply(records)
```

Three normalization families:

| Family | Canonical form | Rule key |
|--------|----------------|----------|
| Dates/times | UTC ISO-8601 (RFC 3339) strings | `dates.fields` + optional `dates.assume_zone`; ISO-ish strings auto-coerced unless `infer_dates: false` |
| Strings | Unicode NFC (canonical composition) | `strings.normalize_all` (default on) + `strings.exclude` |
| Currency | ISO-4217 validation + canonical `{ amount, currency, minor_units }` via the money gem | `currency.fields.<field>` with `currency` (fixed) or `currency_field` (sibling) |

The provenance is an array of `{ record_index, field, type, from, to, currency, note }` entries — one per applied conversion — so downstream auditing can diff originals against canonical values. Callers redact at the log boundary; the service keeps raw originals.

## The QueryService pipeline

`Ai::DataSources::QueryService` (`query_service.rb`) is the Phase-1 integrator. It composes every data-source module (adapters, signers, decoders, format detection, normalization, the SSRF-guarded connection factory, the response cache) **and** every shared reuse service (per-source kill flag, quotas, circuit breaker, credential vault, JSON-schema validation, PII redaction, the audit hash chain, cost attribution) into one governed external-fetch pipeline.

```ruby
Ai::DataSources::QueryService
  .new(data_source:, endpoint:, params: {}, agent: nil, user: nil)
  .call   # => FetchEnvelope (Hash)
```

It **never raises**: every failure path is mapped to a `FetchEnvelope` with `success: false` and a redacted error message.

```mermaid
flowchart TD
    A[1. kill flag<br/>Shared::FeatureFlagService] -->|disabled| Block1[blocked envelope]
    A -->|enabled| B[2. quota<br/>source + per-agent Redis]
    B -->|exceeded| Rate[rate_limited envelope]
    B --> C[3. ResponseCacheService.fetch<br/>singleflight]
    C -->|hit| Fin
    C -->|miss → block runs 4-8| D[4. resolve credential<br/>Vault or encrypted_*]
    D --> E[5. build_request → sign! → validate_url! → send<br/>circuit-breaker wrapped]
    E --> F[6. FormatDetector + adapter.parse<br/>→ canonical records]
    F --> G[7. JsonSchemaValidator<br/>+ NormalizationService]
    G --> H[8. record_request! + credential health]
    H --> Fin[9. REDACT → persist ai_data_source_queries<br/>hash-chained + CostAttribution row]
    Fin --> I[10. write cache → return FetchEnvelope]
```

The ten stages, in order:

1. **Per-source kill flag.** `data_source.<slug>.enabled` via `Shared::FeatureFlagService` (Flipper). Fail-open: only a present-and-false flag disables; an unset flag is treated as enabled (it's a kill switch, not an opt-in).
2. **Quota.** The shared per-source `data_source.check_quota!` (Redis minute/hour/day windows) **plus** a per-agent counter namespaced under `data_source:<id>:quota:<agent_id>:*`, so one noisy agent can't exhaust the whole source's budget. Over-limit → `rate_limited`.
3. **Cache.** The live fetch (stages 4–8) is wrapped in `ResponseCacheService.fetch` (singleflight). A cache fault falls through to a direct fetch — Redis trouble never breaks a query.
4. **Credential.** Prefer Vault when the active credential carries a `vault_path` (via `Security::VaultCredentialProvider`, adapted to the signer contract by an internal `VaultCredentialView`); otherwise fall back to the Rails-encrypted `decrypted_*` accessors.
5. **Protected dispatch.** Inside `Ai::CircuitBreakerRegistry.protect(service_name: "data_source:<id>")`: `adapter.build_request` → `signer.sign!` → `HttpConnectionFactory.validate_url!` → send over the SSRF-guarded Faraday connection. Idempotent verbs (`GET/HEAD/PUT/DELETE/OPTIONS/TRACE`) get **one** transient-failure retry; **POST is never auto-retried** without an explicit idempotency key.
6. **Decode.** `FormatDetector.detect` (records a `content_type_mismatch` anomaly if needed) → `adapter.parse` → canonical records.
7. **Validate + normalize.** When `endpoint.response_schema` is set, `JsonSchemaValidator` yields `schema_valid` (true/false, or `nil`/"unknown" when no schema); then `NormalizationService` coerces values and produces normalization provenance.
8. **Accounting.** `data_source.record_request!(bytes:)` + the per-agent counter; credential `record_success!`/`record_failure!` (which also recomputes `health_status`). A breaker-open path deliberately leaves credential counters untouched.
9. **Persist + audit + cost.** Everything operator-visible is run through `Ai::Security::PiiRedactionService` **before** the row is written. A `Ai::DataSourceQuery` row is saved, then tied into the SHA256 audit hash chain via a companion `AuditLog` whose `before_create` integrity hook (`Audit::LogIntegrityService`) seals it — the resulting `integrity_hash`/`previous_hash`/`sequence_number` are mirrored back onto the query's `metadata["audit_chain"]` so the anchor is queryable without a join. Exactly one `Ai::CostAttribution` row is emitted via `from_data_source_query` (even cache hits — zero-byte egress is still attributed).
10. **Cache write + return.** Write the cacheable payload only on a **fresh success** (never re-write a hit, never cache an error), then return the `FetchEnvelope`.

A fetch maps to the audit action `api_request` on success/cache, `api_request_failed` otherwise (both members of `AuditActions::ALL_ACTIONS`, required so the hash-chained companion entry validates).

`Ai::DataSources::EndpointQueryRunner` is a thin wrapper the REST controller uses so the controller stays under its size budget — it just constructs `QueryService` with the request's agent/user context and returns the envelope verbatim.

## Response cache

`Ai::DataSources::ResponseCacheService` (`response_cache_service.rb`) is a Redis-backed cache (DB 0, via `Powernode::Redis.client`, SHA256 keys, `setex` TTL) that mirrors the access/metrics shape of `Ai::Learning::PromptCacheService` and adds two cache-stampede protections:

1. **Singleflight.** On a miss, only one caller recomputes, under a per-key Redis `SET NX PX` lock (with a 30s safety TTL so a crashed holder can't wedge the key). Concurrent callers poll briefly for the freshly written value, and serve the previous (stale) value if one is still around before falling back to their own recompute.
2. **Probabilistic early refresh (XFetch).** Each entry stores its recompute cost (`delta`) and hard-expiry epoch. A reader rolls `gamma = delta · BETA · -ln(random)` and treats the value as expired when `now + gamma ≥ expiry`, so exactly one early reader regenerates the value just before it would expire — and that regeneration is still single-flighted. Expensive entries refresh proportionally earlier.

TTL comes from `endpoint.cache_ttl_seconds` (fallback `DEFAULT_TTL` = 5 minutes). Cache keys are a human-readable `data_source_id:endpoint_slug` prefix plus a SHA256 of `[ds_id, slug, normalized_params]` — the prefix keeps invalidation cheap, the digest keeps param-variants bounded. `invalidate(data_source:, endpoint:)` does a SCAN-based prefix delete (endpoint-scoped or whole-source). A second per-source kill flag, `data_source_response_caching`, disables caching for a source without touching Redis. `.metrics` returns `{ hits, misses, total, hit_rate }`.

## Security model

The data-source pipeline is the platform's egress chokepoint for agent-initiated fetches. Four controls, applied at distinct stages:

### SSRF: resolve-and-pin

`Ai::DataSources::HttpConnectionFactory` (`http_connection_factory.rb`) builds an SSRF-guarded Faraday connection and exposes `validate_url!(url)`, which **resolves the host and rejects any resolved address** in a private / loopback / link-local / unique-local / reserved CIDR (IPv4 and IPv6, including IPv4-mapped IPv6 and 6to4/Teredo prefixes). The cloud metadata endpoint `169.254.169.254` is inside the blocked `169.254.0.0/16` link-local range — verified blocking. Disallowed schemes and DNS failures also raise `SsrfError`.

```mermaid
flowchart LR
    URL[request URL] --> V[validate_url!]
    V -->|resolve host| IP{resolved IP in<br/>blocked CIDR?}
    IP -->|yes| Block[raise SsrfError]
    IP -->|no| Send[adapter sends]
    Send -->|3xx redirect| RV[validate_redirect!<br/>re-validate target]
    RV --> IP
```

The guard runs in **two places**: `validate_url!` is called directly before dispatch (resolve-and-pin), and a `SsrfGuardMiddleware` re-validates the initial URL on the way out, while a `follow_redirects` callback re-validates **every redirect hop** — so a public host cannot 30x-bounce into the internal network. The factory also enforces bounded open/read timeouts and a hard response-size cap (`MAX_RESPONSE_BYTES` = 10 MiB; endpoints may lower it via `configuration["max_response_bytes"]` but never raise it), raising `ResponseTooLargeError` on oversized bodies. It advertises a contactable `User-Agent`: `Powernode/<ver> (+<contact>; agent:<slug>)`. (OWASP coverage: A10:2021 SSRF, ASI08 Excessive Agency.)

### Redaction chokepoint

Stage 9 of `QueryService` runs **every** operator/caller-visible string through `Ai::Security::PiiRedactionService` before it is persisted to `ai_data_source_queries` or cached in provenance — the URL, params, response snippet, and error message. Beyond the PII heuristics, a hard `SENSITIVE_QUERY_KEY` pattern unconditionally masks the *values* of query params whose key matches `api_key`/`key`/`token`/`access_token`/`refresh_token`/`secret`/`client_secret`/`auth`/`authorization`/`password`/`sig`/`signature`/`credential`/`session`/`cookie` (and common prefixed forms), so non-standard secret params never persist verbatim. On any redaction failure the URL's query string is stripped entirely rather than risk a leak.

### Request signing

Outbound auth is applied by the signer layer (`auth/`), resolved by scheme from `SignerRegistry`. Every signer mutates the request in place via `sign!(conn_or_env, credential:, config:)`:

| Scheme | Signer | Behavior |
|--------|--------|----------|
| `none` | `NoneSigner` | No-op (also the fallback for unknown schemes) |
| `api_key` | `ApiKeySigner` | Injects the key as a configurable header or query param |
| `bearer` | `BearerSigner` | `Authorization: Bearer <token>` |
| `aws_sigv4` | `Sigv4Signer` | **Wraps** `Aws::Sigv4::Signer` (gem `aws-sigv4`) — canonicalization is delegated to the SDK, never hand-rolled. Region/service from `auth_config`; signs the request-env Hash (per-request, not per-connection). |
| `hmac` | `HmacSigner` | RFC 9421 HTTP Message Signatures, emitting `Signature-Input` + `Signature` headers over configurable covered components. |

`HmacSigner` and the inbound webhook verification path share one audited HMAC implementation: `Security::HttpSignature` (`server/app/services/security/http_signature.rb`) — `hexdigest`/`base64digest`/`sign`/`verify` plus constant-time `secure_compare`. Signing failures are logged without echoing credential material and re-raised; the catch-all keeps secrets out of logs and exception traces.

### Vault + encryption

Credentials are encrypted at rest with Rails-8 `encrypts` on `encrypted_api_key`/`encrypted_api_secret`. The `vault_path` + `migrated_to_vault_at` columns support migrating a credential into Vault; when present, the pipeline reads the secret from Vault at fetch time (stage 4) and never touches the DB copy. Credential health is tracked via `consecutive_failures` — five consecutive failures deactivate the credential and drive `health_status` to `critical`.

## Provenance and the FetchEnvelope

Every `QueryService.call` returns a `FetchEnvelope` — the single contract the REST and MCP surfaces both render:

```ruby
{
  success:,            # Boolean
  data:,               # Array<Hash> — canonical, normalized records
  provenance: {
    slug:, endpoint_id:, fetched_at:, from_cache:, cache_age_seconds:,
    response_sha256:,
    source_url:,        # REDACTED
    declared_vs_detected_content_type:,  # { declared, detected, content_type, mismatch }
    charset:, applied_encoding:,
    schema_valid:,      # true | false | nil (no schema)
    record_count:,
    anomalies: []       # e.g. content_type_mismatch, schema_invalid, http_4xx, decode_error
  },
  status:,             # success | error | timeout | rate_limited | blocked | cached
  duration_ms:,
  bytes:,
  error:               # nil on success; redacted message otherwise
}
```

Provenance answers "where did this data come from and can I trust it" without re-fetching: the `response_sha256` fingerprints the exact bytes, `from_cache`/`cache_age_seconds` say how fresh it is, `declared_vs_detected_content_type` exposes any format mismatch, `schema_valid` reports contract conformance, and `anomalies` lists everything that looked off. The same facts are mirrored into the persisted `ai_data_source_queries` row (with the URL/params/snippet redacted), which is itself sealed into the audit hash chain — so the provenance is both returned to the caller and durably auditable.

## Surfaces: REST + MCP

The capability is exposed two ways with 1:1 parity.

### REST

`Api::V1::Ai::DataSourcesController` (under the `Api::V1` namespace) provides catalog CRUD, `test_connection`, `quota_status`, **nested endpoint CRUD**, and the governed **query** action. Endpoint routes nest under a source (`/api/v1/ai/data_sources/:data_source_id/endpoints/...`); the query route is `POST .../endpoints/:endpoint_id/query`, which calls `EndpointQueryRunner` → `QueryService` and renders the envelope through `render_success`/`render_error` (mapping `rate_limited`→429, `blocked`→403, `timeout`→504, else 502). The nested-endpoint logic lives in the `Ai::DataSourceEndpoints` controller concern to keep the controller under 300 lines.

Permissions (checked in `validate_permissions`, skipped for `current_worker`):

| Action(s) | Permission |
|-----------|-----------|
| `index`, `show`, `quota_status`, `test_connection`, `endpoints_index` | `ai.data_sources.read` |
| `create` | `ai.data_sources.create` |
| `update` | `ai.data_sources.update` |
| `destroy` | `ai.data_sources.delete` |
| `endpoints_create`/`endpoints_update`/`endpoints_destroy` | `ai.data_sources.update` **or** `ai.data_sources.manage` |
| `endpoints_query` | `ai.data_sources.query` |

### MCP

`Ai::Tools::DataSourceTool` exposes the same surface to agents over MCP as `data_source_management`, registered per-action in `PlatformApiToolRegistry`. Actions: `data_source_{list, get, describe, query, health, validate_config, create, update, delete}`.

Authorization mirrors REST: read actions require `ai.data_sources.read`, `data_source_query` requires `ai.data_sources.query`, and the mutations require the matching `ai.data_sources.{create,update,delete}` grant (`ai.data_sources.manage` satisfies any mutation). The distinctive piece is the **proposal fallback**: when the acting agent's account lacks the mutation permission, the mutation actions do **not** mutate — they file an `Ai::AgentProposal` (via `Ai::ProposalService`) describing the intended change and return a `requires_approval: true` result for a human to review. This mirrors the established `AgentAutonomyTool`/`AgentManagementTool` pattern. `data_source_query` returns the `FetchEnvelope` verbatim; `data_source_health` reports the quota summary, `ResponseCacheService.metrics`, and the circuit-breaker state; `data_source_validate_config` checks the base URL is SSRF-safe, the auth scheme is known, and the protocol/formats are supported.

## Frontend

The React UI lives under `frontend/src/features/ai/data-sources/`. Two Phase-1 components surface the endpoint and query layers:

- **`DataSourceEndpointsTab.tsx`** — CRUD for a source's endpoints (templates, response format, mapping, schema, cache TTL, `monitorable`).
- **`DataSourceQueryConsole.tsx`** — runs a governed fetch against an endpoint and renders the returned `FetchEnvelope`, including the provenance panel (SHA256, cache age, content-type mismatch, schema validity, anomalies).

TypeScript contracts are in `frontend/src/shared/types/ai.ts`: `AiDataSourceEndpoint`, `DataSourceEndpointRequest`, `DataSourceQueryStatus`, `DataSourceQueryProvenance`, and `DataSourceFetchEnvelope` (which mirrors the backend `FetchEnvelope` exactly).

Phase 2a adds **`DataSourceDiscoveryPanel.tsx`** (a natural-language search box that calls `dataSourcesApi.discover()` → `POST /discover` and renders each ranked source with its four signal chips), mounted at the top of `AiDataSourcesPage.tsx`. `DataSourceCard.tsx` renders a **trust/effectiveness badge** (`Trusted` / `Reliable` / `Fair` / `Low Trust` tiers off `effectiveness_score`) once the serializer surfaces the score. The new TypeScript contracts are `DataSourceDiscoverySignals`, `DataSourceDiscoveryResult`, and `DataSourceDiscoveryResponse` (also in `frontend/src/shared/types/ai.ts`), and the serialized-source type carries `effectiveness_score`/`usage_count`/`positive_usage_count`/`negative_usage_count`/`usage_success_rate`.

Phase 2b adds three endpoint-level surfaces: **`DataSourceSchemaHistoryTab.tsx`** (the recorded schema versions with their drift classification + structural diff), **`DataSourceQualityTab.tsx`** (the latest quality outcome plus the endpoint's configured expectations), and **`DataSourceImportOpenApiModal.tsx`** (OpenAPI import via `spec`/`spec_url`, with a `dry_run` preview). The backing TypeScript contracts (in `frontend/src/shared/types/ai.ts`) are `AiDataSourceSchemaVersion`, `DataSourceSchemaHistoryResponse`, `AiDataSourceExpectation`, `DataSourceQualityResponse`, `DataSourceContractVerdict`, and `DataSourceOpenApiImportResult`, with matching `DataSourcesApiService` methods.

## Discovery & Evaluation (Phase 2)

Phase 1 answers *"fetch from a source I already named"*. **Phase 2a** answers the two questions that come before that — *"which source should I use for this need?"* (discovery) and *"how much should I trust what it returns?"* (evaluation) — by projecting every source into the knowledge graph as an embedded node and rolling each fetch outcome into a single effectiveness score. All of it is **merged, migrated, and smoke-tested**; it reuses the exact same `GraphService` + `EmbeddingService` + pgvector machinery that already backs skill discovery, so there is no new embedding infrastructure.

```mermaid
flowchart TB
    DS[(Ai::DataSource<br/>effectiveness_score<br/>usage counters)]
    KGN[(KnowledgeGraphNode<br/>entity_type data_source<br/>pgvector embedding)]
    Bridge[DataSourceGraph::BridgeService<br/>sync_data_source]
    QS[QueryService#finalize]
    Rec[record_query!<br/>+ recalculate_effectiveness!]
    Disc[SemanticDiscoveryService#discover]

    DS -->|after_commit<br/>name/description/source_type/slug| Bridge
    Bridge -->|upsert node + embedding| KGN
    QS -->|LIVE fetch only| Rec --> DS
    KGN -->|confidence| Rec
    Disc -->|embed query → cosine NN| KGN
    KGN -->|node → ai_data_source_id| DS
    DS -->|effectiveness / health / recency| Disc
```

### The knowledge-graph node

`Ai::KnowledgeGraphNode::ENTITY_TYPES` now includes `"data_source"`, with scopes `.data_source_nodes` (`entity_type = "data_source"`) and `.for_data_source(id)`, a `belongs_to :data_source` (`class_name: "Ai::DataSource", foreign_key: "ai_data_source_id", optional: true`), and a new nullable `ai_data_source_id` UUID column. That column is deliberately **not** a `t.references` — it carries a single **partial index** (`WHERE ai_data_source_id IS NOT NULL`) so the overwhelming majority of graph nodes (which are not data sources) pay no write-amplification cost. `Ai::DataSource` closes the loop with `has_one :knowledge_graph_node` (`foreign_key: "ai_data_source_id", dependent: :nullify`).

### BridgeService: embedding sync

`Ai::DataSourceGraph::BridgeService.new(account)` mirrors `Ai::SkillGraph::BridgeService` one-for-one and reuses the **same** collaborators — `Ai::KnowledgeGraph::GraphService` and `Ai::Memory::EmbeddingService`:

- **`#sync_data_source(ds)`** upserts the source's `data_source` node: it generates the embedding from `name | description | category: <source_type> | endpoints: <endpoint names>`, sets `properties` to `{ source_type, protocol, auth_scheme, health_status, is_active, effectiveness_score, usage_count, endpoint_count }` (compacted), links the node via `ai_data_source_id`, and stamps `confidence: 1.0` / `status: "active"` / `last_seen_at`. It **returns `nil` on any `StandardError`** (logged) so a sync failure never propagates.
- **`#sync_all_data_sources`** bulk-syncs all active account sources, returning `{ synced:, failed: }`.

Because it leans on `EmbeddingService`, it **degrades gracefully**: with no embedding backend (test/CI) the embedding comes back nil and the node is still created/updated, just without a vector.

The sync is **wired off `Ai::DataSource`'s `after_commit :sync_to_knowledge_graph`** (on create/update), but **guarded** — it only fires when an embedding-relevant field actually changed:

```ruby
return unless saved_change_to_name? || saved_change_to_description? ||
              saved_change_to_source_type? || saved_change_to_slug?
```

This matters because the evaluation counters (next section) write back to the same row on every fetch; without the guard each fetch would trigger a needless re-embed. On `create` every `saved_change_to_*` is true, so the initial node is always built. (Accountless rows are skipped, and the whole callback degrades to a logged warning rather than raising out of the commit.)

### The effectiveness score

Each source carries an `effectiveness_score` (decimal, default `0.5`) plus `usage_count` / `positive_usage_count` / `negative_usage_count` (default `0`) and `last_used_at` — all added by the `AddEvaluationToAiDataSourcesAndKgLink` migration.

`Ai::DataSource#record_query!(outcome:, freshness: nil, agent: nil)` is the hot-path counter update. It does **one** `update_columns` write — bumping `usage_count`, the matching `positive_`/`negative_usage_count`, and `last_used_at` — that deliberately **bypasses the audit hash chain and the KG after_commit sync**, because counter churn on the fetch path must not flood the audit log or trigger re-embeds. It then calls `recalculate_effectiveness!` **only on every 5th recorded outcome** (`total.positive? && (total % 5).zero?`), amortizing the recompute. (`agent:` is accepted but reserved — counters are source-wide today.)

`recalculate_effectiveness!(freshness: nil)` blends three trust signals and writes the result via `update_columns` (same off-the-audit-path rationale):

```
effectiveness_score = (0.3 * kg_confidence
                     + 0.4 * usage_success_rate
                     + 0.3 * freshness).round(4)
```

| Term | Weight | Source |
|------|--------|--------|
| `kg_confidence` | 0.3 | `knowledge_graph_node&.confidence&.to_f`, defaulting to `0.5` when there is no node — the source's semantic standing in the graph |
| `usage_success_rate` | 0.4 | `positive / (positive + negative)`, a neutral `0.5` until there is at least one outcome (so brand-new sources aren't penalized) |
| `freshness` | 0.3 | the caller-supplied `freshness:` (clamped 0..1) when given, else the private `freshness_score` |

`freshness_score` is a **linear 7-day decay** off the most recent of `last_used_at` / `last_health_check_at`: `0.5` when neither is set, `1.0` when just touched, decaying to `0.0` at a week stale.

### Where the score gets fed: QueryService#finalize

`Ai::DataSources::QueryService#finalize` calls `data_source.record_query!(outcome:, freshness:, agent:)` on **live fetches only** — it is deliberately *not* called for cache hits, kill-flag blocks, or quota short-circuits, so the effectiveness score reflects real upstream behavior rather than cache/governance outcomes. This is the single write that turns each governed fetch into a scoring signal.

### SemanticDiscoveryService

`Ai::DataSources::SemanticDiscoveryService.new(account)` is the discovery front door, built in the **`Ai::ConciergeRouter` style** (embedding + `nearest_neighbors`), but ranking `Ai::DataSource` rows instead of skills:

```ruby
Ai::DataSources::SemanticDiscoveryService.new(account).discover(
  query:, agent: nil, limit: 10, rerank: false
)
# => [ { data_source:, score: 0.0..1.0,
#        signals: { semantic:, effectiveness:, health:, recency: } }, ... ]  (desc)
```

The pipeline:

1. **Embed the query** via `Ai::Memory::EmbeddingService` (the same instance the bridge uses).
2. **Nearest-neighbor** over `account.ai_knowledge_graph_nodes.data_source_nodes.active.with_embeddings.nearest_neighbors(:embedding, qemb, distance: "cosine")` (a candidate pool of 50), then map each node's `ai_data_source_id` back to its eager-loaded `Ai::DataSource`.
3. **Keyword fallback** — when there is no embedding backend (hermetic) or no nodes carry embeddings yet, fall through to `KnowledgeGraphNode.search_by_name`, with the semantic signal neutralized to a `0.5` baseline.
4. **Blend** a final 0..1 score from four signals with fixed `WEIGHTS`:

   | Signal | Weight | Definition |
   |--------|--------|-----------|
   | `semantic` | 0.55 | cosine similarity (`1 - distance`), or the `0.5` keyword baseline |
   | `effectiveness` | 0.25 | the source's rolled-up `effectiveness_score` |
   | `health` | 0.10 | `1.0` when `healthy?`, else `0.0` |
   | `recency` | 0.10 | linear 7-day decay of `last_used_at` (`0.5` when never used) |

5. **Optional rerank** — when `rerank: true`, the top candidates are routed through `Ai::Rag::RerankingService` (each adapted to a `:content` blob of name + description + endpoint names), and the returned relevance is folded back into the `semantic` signal before the final sort. It defaults to **off** because it consumes an LLM call when a scoring agent is present; absent an agent the reranker returns a heuristic ordering, keeping it hermetic-safe.

The blend **never raises on missing data** — absent signals fall back to neutral defaults, and both candidate paths rescue to `[]` with a logged warning.

### Provenance and the trust surface

Discovery picks a source; **provenance** answers "can I trust *this specific fetch*", and the **trust surface** answers "can I trust this source overall". Both ride on top of the Phase-1 audit log:

- **Provenance** of a recorded fetch is read straight from an already-redacted `ai_data_source_queries` row (the Phase-1 query/audit log) — `source`, `endpoint`, `fetched_at`, `response_sha256`, `redacted_url`, `schema_valid`, `cached` / `served_stage`, cost, `anomalies`, and the mirrored `audit_chain` anchor. Nothing is re-fetched and nothing new is redacted; Phase 2a only *exposes* what Phase 1 already sealed.
- **Trust signals** are the rolled-up evaluation facts surfaced alongside every source: `effectiveness_score`, `usage_count` / `positive_usage_count` / `negative_usage_count`, `usage_success_rate`, the KG node `confidence`, `last_used_at`, and `health_status` / `healthy?`. The `describe` and `health` MCP payloads now embed these so an agent can reason about reliability before committing to a fetch.

### Surfaces

The Phase-2a capability is exposed on the same REST + MCP surfaces with parity:

**REST.** `POST /api/v1/ai/data_sources/discover` → `DataSourcesController#discover` (guarded by `require_permission("ai.data_sources.read")`). Body `{ query:, limit?, rerank? }`; response `{ query, count, results: [ <serialized source> + score + signals ] }`. `serialize_data_source` now additionally emits `effectiveness_score` / `usage_count` / `positive_usage_count` / `negative_usage_count` / `usage_success_rate` / `last_used_at` on **every** source response, so the trust surface is visible across list/show/discover.

**MCP.** `Ai::Tools::DataSourceTool` grows from 9 to **12 actions** (all gated by `ai.data_sources.read`), registered in `PlatformApiToolRegistry`:

| Action | Purpose |
|--------|---------|
| `data_source_discover` | Semantic discovery via `SemanticDiscoveryService` (`query`, `limit?`, `rerank?`) — returns ranked sources + signals |
| `data_source_provenance` | Reads one `ai_data_source_queries` row's already-redacted provenance columns (by `query_id`, then `correlation_id`, else latest for a source) |
| `data_source_impact` | Usage summary: distinct requesting-agent count, total/successful/failed/cached query counts, `last_used_at`, `effectiveness_score`, health |

The `describe` and `health` payloads also now include `effectiveness_score` and the trust-signal block.

## Data quality, schema-drift & contracts (Phase 2b)

Phase 2a answers *"which source, and can I trust it overall"*. **Phase 2b** answers the per-fetch, per-endpoint question — *"is **this** endpoint's data **shaped** the way I expect, **clean** enough to use, and **fresh** enough to honor its contract?"* — by layering three opt-in observability stages onto the Phase-1 fetch and an OpenAPI importer onto endpoint setup. It is **merged, migrated (zeitwerk-clean), smoke-tested (drift confirmed), and the full suite is green.**

The defining design principle is **zero overhead when off**. The three observability stages are gated by three boolean columns on `Ai::DataSourceEndpoint` — `track_schema`, `quality_checks_enabled`, `quarantine_on_failure` — and **all three default `false`**. When none is set (the default for every endpoint), `QueryService#apply_observability_stages` is a no-op and the `FetchEnvelope` is byte-for-byte identical to its pre-2b form. You pay only for what you turn on, per endpoint.

```mermaid
flowchart TB
    EP[(Ai::DataSourceEndpoint<br/>track_schema / quality_checks_enabled<br/>quarantine_on_failure / sla_max_age_seconds / contract)]
    QS[QueryService#apply_observability_stages<br/>after decode+normalize, OFF by default]

    subgraph Stages["Opt-in observability stages"]
        SD[SchemaDriftService<br/>classify + versioned history]
        QV[QualityService<br/>expectations -> score + passed]
        QN[Quarantine<br/>serve last-known-good]
    end

    CS[ContractService<br/>schema + quality + SLA -> verdict]
    OAI[OpenApiImportService<br/>spec -> endpoint rows]

    EP --> QS
    QS -->|track_schema| SD
    QS -->|quality_checks_enabled| QV
    QV -->|!passed && quarantine_on_failure| QN
    SD -->|breaking| Sig[StigmergicSignalService.emit!<br/>warning / data_source_schema_drift]
    EP -. read-only verdict .-> CS
    OAI -->|create endpoints| EP
```

All Phase-2b backend code lives under `server/app/services/ai/data_sources/` alongside the Phase-1 modules; the new models are `Ai::DataSourceSchemaVersion` and `Ai::DataSourceExpectation`.

### New model + endpoint columns

`Ai::DataSourceEndpoint` gains the opt-in flags plus contract knobs:

| Column | Type | Default | Role |
|--------|------|---------|------|
| `track_schema` | boolean | `false` | Enables schema-drift tracking on each fetch |
| `quality_checks_enabled` | boolean | `false` | Enables the quality-expectations stage |
| `quarantine_on_failure` | boolean | `false` | On a quality failure, serve last-known-good instead of the bad batch |
| `sla_max_age_seconds` | integer | — | Freshness budget for the contract's SLA signal (unset ⇒ no SLA) |
| `owner` | string | — | Free-form endpoint owner label |
| `contract` | jsonb | `{}` | Free-form declarative contract metadata |

It also `has_many :schema_versions` and `:expectations` (both `dependent: :destroy`), and re-exports the enum tokens (`SCHEMA_DRIFT_CLASSIFICATIONS`, `EXPECTATION_RULE_TYPES`, `EXPECTATION_SEVERITIES`) so callers can branch off the endpoint without reaching into the child models.

Two new tables back the stages, plus four new columns on the Phase-1 query log:

- **`Ai::DataSourceSchemaVersion`** (`ai_data_source_schema_versions`): `ai_data_source_endpoint_id`, monotonic `version`, the `schema` jsonb snapshot, a `checksum`, the `classification` (`initial`/`none`/`additive`/`breaking`), and the structural `diff` jsonb. Scopes `for_endpoint` / `ordered` / `latest_first` / `breaking`; unique index on `[endpoint_id, version]`.
- **`Ai::DataSourceExpectation`** (`ai_data_source_expectations`): `ai_data_source_endpoint_id`, `name`, `rule_type` (one of `required_fields`/`min_records`/`max_records`/`non_null`/`allowed_values`/`distribution`), `config` jsonb, `severity` (`warn`/`error`), `is_active`. Scopes `active` / `errors`.
- **`ai_data_source_queries`** gains `quality_score` (decimal), `quality_passed` (boolean), `quarantined` (boolean, default `false`), and `schema_drift` (string) — the per-fetch outcomes of the opt-in stages, persisted on the audit row and mirrored onto provenance.

### SchemaDriftService — classify + versioned history

`Ai::DataSources::SchemaDriftService.new(account = nil)` detects and records response-schema drift for an endpoint. Two methods:

- **`#diff(old_schema, new_schema)`** — a pure structural diff (never persists), returning `{ classification:, added_fields: [], removed_fields: [], type_changes: [{ field:, from:, to: }] }`. It flattens both JSON-Schema-shaped Hashes into dotted property paths → declared type and compares those, so nested objects and array items are compared *structurally* rather than by raw equality.
- **`#record_version!(endpoint, schema)`** — diffs the supplied schema against the endpoint's latest recorded version, classifies, and appends the **next** `Ai::DataSourceSchemaVersion` (`version` = latest + 1). It is **idempotent**: when the schema's checksum is unchanged from the latest version, no row is created — it returns the existing latest version with classification `"none"` for *this* call (an in-memory, read-only override so consumers that branch on the returned token correctly see "no change" on repeat polls, without rewriting the version's true recorded classification).

**Classification semantics** (vs the immediately prior version), exposed as class consts `INITIAL`/`NONE`/`ADDITIVE`/`BREAKING`:

| Token | Meaning |
|-------|---------|
| `initial` | No prior schema (first version for the endpoint) |
| `none` | Structurally identical |
| `additive` | Fields added, none removed or retyped |
| `breaking` | A field was **removed** OR an existing field **changed type** |

Because the platform is on the **consume** side (it reads external APIs), any pure addition is backward-compatible and classified `additive` — the JSON-Schema `required` array is deliberately **not** consulted. The service handles **both** object-root schemas (`{ type: object, properties: {…} }`) **and** array-root schemas (`{ type: array, items: { type: object, properties: {…} } }`) — array-root is exactly what `QueryService#infer_schema` emits, so recursion at the root is load-bearing (guarding it on a non-empty prefix would make drift detection a permanent no-op). This is the path the merged smoke test exercised: added → `additive`, removed/retyped → `breaking`, identical → `none`.

### QualityService — expectations + scoring + quarantine

`Ai::DataSources::QualityService.new(endpoint)` evaluates an endpoint's **active** expectations over the canonical (normalized) records of a fetch. `#evaluate(records)` returns:

```ruby
{
  quality_score: Float,     # 0..1, weighted share of rules passed
  passed: Boolean,          # false ONLY when an ERROR-severity rule fails
  results: [{ name:, rule_type:, passed:, severity:, detail: }],
  anomalies: []             # rule_type tokens of the failed error-severity rules
}
```

It runs `endpoint.expectations.active` — each an `Ai::DataSourceExpectation` whose `rule_type` is one of `required_fields`, `min_records`, `max_records`, `non_null`, `allowed_values`, or `distribution`, with a `severity` of `warn` or `error`. When **no** expectations are configured, two built-in **WARN-severity** defaults run (a non-empty-batch check and a record-shape uniformity check) so a quality signal always exists.

Two scoring rules matter:

- **`passed` is `false` only when an ERROR-severity rule fails.** A failed WARN rule lowers the score but never fails the batch — so the built-in defaults shape the number without ever blocking data on their own.
- The `quality_score` is a **weighted** share of rules passed, with **error-severity rules weighted double** so a passing-but-warn-heavy batch can't mask a failed hard rule in the numeric score.

It **never raises** — a rule that itself blows up is recorded as a failed WARN result rather than aborting the evaluation.

**Quarantine.** When `quality_checks_enabled` is on and a quality check **fails** on an otherwise-successful fetch, and `quarantine_on_failure` is *also* on, `QueryService` swaps the bad batch for the **last-known-good** cached payload (`ResponseCacheService.read`), sets `quarantined: true` on provenance and the query row, and suppresses caching the bad payload (so the cache stays clean — the served data already *is* the last-known-good). With no prior good payload, the served batch falls back to empty. This keeps a downstream agent from ingesting a known-bad batch while the upstream recovers.

### ContractService — one verdict from schema + quality + SLA

`Ai::DataSources::ContractService.new` aggregates a single *"is the data contract met?"* verdict by combining three signals already present on a `FetchEnvelope` and its endpoint. `#validate(data_source:, endpoint:, envelope:)` returns:

```ruby
{ met: Boolean, schema_valid: (Boolean|nil), quality_passed: (Boolean|nil),
  within_sla: (Boolean|nil), violations: [<String>] }
```

The three signals (read with indifferent string/symbol access off the envelope/provenance):

| Signal | Source |
|--------|--------|
| `schema_valid` | The envelope provenance `schema_valid` (true/false, or `nil` "unknown" when the endpoint has no `response_schema`) |
| `quality_passed` | The envelope/provenance quality verdict when the quality stage ran; otherwise a **fresh** `QualityService` run over the envelope's canonical records (nil only when neither is available) |
| `within_sla` | Provenance `cache_age_seconds` ≤ `endpoint.sla_max_age_seconds`; **`true` when no SLA is configured** (an unset budget can't be exceeded), `nil` only when an SLA is set but the age is unknown |

The verdict is **assertion-based**: a `nil` signal is "not asserted" — it adds no violation, so a contract with no configured assertions is **vacuously met** (`met: true`). `met` is true exactly when every *asserted* signal holds; `violations` collects `schema_invalid` / `quality_failed` / `sla_exceeded` for the ones that were asserted-and-failed.

### OpenAPI introspection

`Ai::DataSources::OpenApiImportService.new(data_source)` turns a parsed OpenAPI 3 document into `Ai::DataSourceEndpoint` rows — there is no OpenAPI/JSON-Schema gem in play, so the spec is parsed **structurally**. `#import(spec, dry_run: false)` returns `{ created: [], preview: [], errors: [] }`.

It walks `paths × { get, post, put, patch, delete, head }` and maps each operation to endpoint attributes: `name` from `operationId` ‖ `summary` ‖ `"METHOD path"`, `http_method`, `path_template` = the path, and `response_schema` resolved from the operation's 2xx (then `default`) JSON content schema with **recursive `$ref` resolution** against `#/components` (depth-capped against cyclic refs, inlined so the stored schema is self-contained). On `dry_run` it returns the preview without persisting; a real import **skips duplicate slugs** (both already-present on the source and collisions produced within the same batch) and collects **per-path errors** so one bad operation never aborts the rest.

### How it wires into the fetch (opt-in, after normalization)

The three observability stages run in `QueryService`'s private `apply_observability_stages`, called immediately after decode + normalize and **only** for endpoints that opt in:

- **`track_schema`** → `infer_schema(records)` (a minimal array-root JSON Schema inferred from the first record's keys) → `SchemaDriftService.record_version!`. On a `"breaking"` classification it emits a stigmergic signal via `Ai::Coordination::StigmergicSignalService.emit!(signal_type: "warning", signal_key: "data_source_schema_drift", payload: { data_source_id, endpoint_id, schema_version, classification, diff, … })` so autonomous agents *perceive* the drift. A non-`none` classification also adds a `schema_drift_<token>` anomaly.
- **`quality_checks_enabled`** → `QualityService.evaluate` sets `@quality_score` / `@quality_passed`; failed-rule tokens are folded into `anomalies`. If `!passed` **and** `quarantine_on_failure` is on, the records are replaced with the last-known-good payload (quarantine, above).

The outcomes (`quality_score`, `quality_passed`, `quarantined`, `schema_drift`) are persisted on the `ai_data_source_queries` row **and** mirrored onto the `FetchEnvelope` provenance, so `ContractService` and callers can read the verdict straight off the envelope. Every stage is individually nil-safe: a stage failure is logged and skipped, never allowed to break the fetch.

**All three flags default `false`** — the no-op default path means the `FetchEnvelope` is identical to pre-2b and there is **zero added overhead** until an operator opts an endpoint in.

### Surfaces (REST + MCP)

The Phase-2b capability is exposed on both surfaces. The three read endpoints require `ai.data_sources.read`; introspection is a write surface requiring `ai.data_sources.manage`.

**REST** (in the `Ai::DataSourceEndpoints` concern):

| Route | Purpose | Permission |
|-------|---------|-----------|
| `GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/schema_history` | The endpoint's recorded schema versions (newest-first) + the latest | `ai.data_sources.read` |
| `GET …/endpoints/:endpoint_id/quality` | The latest quality outcome (distilled from the most recent query row) + the configured expectations | `ai.data_sources.read` |
| `GET …/endpoints/:endpoint_id/contract` | The aggregate `ContractService` verdict built from the latest recorded query (a GET never triggers an outbound fetch) | `ai.data_sources.read` |
| `POST /api/v1/ai/data_sources/:id/introspect` | OpenAPI import — body `spec` (parsed) or `spec_url`/`url` (server-fetched through the SSRF-guarded factory), `dry_run` | `ai.data_sources.manage` |

**MCP.** `Ai::Tools::DataSourceTool` grows to **16 actions**, adding `data_source_schema_history`, `data_source_quality`, and `data_source_contract` (all `ai.data_sources.read`), plus `data_source_introspect` (`ai.data_sources.manage`, supports `dry_run`). All four are registered per-action in `PlatformApiToolRegistry`.

The REST response shapes mirror the frontend TypeScript contracts in `frontend/src/shared/types/ai.ts`: `DataSourceSchemaHistoryResponse` (+ `AiDataSourceSchemaVersion`), `DataSourceQualityResponse` (+ `AiDataSourceExpectation`), `DataSourceContractVerdict`, and `DataSourceOpenApiImportResult`. The UI surfaces them through `DataSourceSchemaHistoryTab.tsx`, `DataSourceQualityTab.tsx`, and `DataSourceImportOpenApiModal.tsx`, with matching `DataSourcesApiService` methods.

## Phase boundaries

**Phase 1** is the governed-fetch foundation: catalog + endpoint templates, the three generic registries, decode/normalize, the full `QueryService` pipeline, the response cache, the security model, and the REST + MCP surfaces — all merged, migrated, and smoke-tested.

**Phase 2a** (the [Discovery & Evaluation](#discovery--evaluation-phase-2) section above) adds the discovery + evaluation layer on top: the `data_source` knowledge-graph node + `BridgeService` embedding sync, the blended `effectiveness_score` fed by `record_query!` on live fetches, `SemanticDiscoveryService`, and the discovery / provenance / impact surfaces — also merged, migrated, and smoke-tested.

**Phase 2b** (the [Data quality, schema-drift & contracts](#data-quality-schema-drift--contracts-phase-2b) section above) adds the per-endpoint observability layer: opt-in `SchemaDriftService` versioned history + breaking-drift signal, `QualityService` expectations/scoring/quarantine, the aggregate `ContractService` verdict, and `OpenApiImportService` introspection — with all three endpoint flags defaulting off (zero overhead until opted in). Merged, migrated (zeitwerk-clean), full suite green, drift smoke-confirmed.

Remaining out of scope:

- **Endpoint-level discovery (later Phase 2)** — Phase 2a discovers *sources* by intent; automatic discovery/suggestion of individual endpoints (and per-endpoint effectiveness) is not yet built.
- **Monitoring (Phase 3)** — the `monitorable` flag and the change-detection columns (`etag`, `last_modified`, `change_detection` strategies: `etag`/`last_modified`/`content_hash`/`polling`/`none`) are persisted on endpoints but the active monitoring pipeline that consumes them is a later phase. (Phase 2b's schema-drift tracking is a per-fetch, opt-in observability stage, not the standalone change-detection poller.)

## Related concepts

- [`concepts/architecture.md`](./architecture.md) — the service layer and process model this subsystem lives in
- [`concepts/data-model.md`](./data-model.md) — UUIDv7 keys and the `Ai::` → `ai_` foreign-key convention
- [`concepts/permissions.md`](./permissions.md) — `require_permission` / `has_permission?` semantics behind the `ai.data_sources.*` grants
- [`concepts/mcp-and-tools.md`](./mcp-and-tools.md) — how the `data_source_management` MCP tool dispatches into the service
- [`concepts/cost-and-finops.md`](./cost-and-finops.md) — `Ai::CostAttribution` and the cost rows each fetch emits
- [`operations/data-sources.md`](../operations/data-sources.md) — operational runbook: register a source, rotate a credential, troubleshoot
- [`reference/database-schema.md`](../reference/database-schema.md) — full `ai_data_source*` table reference

## Materials previously at

This is a new concept document for the Phase 1 Data Source feature, extended in place for Phase 2a (discovery + evaluation) and Phase 2b (data quality, schema-drift & contracts). It complements the pre-existing operational runbook at `docs/operations/data-sources.md` (which retains the register/rotate/troubleshoot procedures).

_Last verified: 2026-06-06_
