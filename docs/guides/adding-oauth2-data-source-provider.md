# Adding an OAuth2 provider (data source)

How to onboard a new OAuth2-authenticated external API as an `Ai::DataSource` —
app registration, the connect flow, publishing through a write endpoint, and
revocation. Worked example: **X.com** (Twitter API v2), added in the
`x-com-provider` campaign (I1–I6).

This is a config exercise, not a code exercise: the OAuth2 Authorization Code +
PKCE flow, the silent refresh broker, and the write-endpoint approval gate are
all generic platform capabilities (`Ai::DataSources::OauthAuthorizationCodeService`,
`Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker`,
`Ai::Tools::DataSourceTool`). Adding provider #2 (LinkedIn, Reddit, …) means
writing a new template — a source + endpoint manifest — not touching any of
that machinery.

The data-sources UI ships a connect panel for all of this (I5): any source whose
`auth_config.authorize_url` is set shows an OAuth2 Connection card — enter the app
credentials, copy the redirect URI, and click Authorize. Everything below documents
the underlying REST API / `data_source_management` MCP tool flow the panel drives,
which you can also call directly.

## 1. Register the app on the provider

Every OAuth2 provider requires you to register an application on its developer
portal before anything else. You'll get back a **client ID** and **client
secret**, and the portal will ask for a **redirect URI** to allow.

For X.com: [developer.twitter.com](https://developer.twitter.com/en/docs/twitter-api),
create a project + app, enable OAuth 2.0, and request the scopes your use case
needs (see step 2).

**The redirect URI is computed, not something you invent.** It's
`Ai::DataSources::OauthAuthorizationCodeService#build_redirect_uri`: the
platform's public base URL (`PublicUrlResolver`) plus the named callback route
(`api_v1_ai_data_source_oauth_callback_path`) — never stored, always derived.
You don't need to guess it: call `#authorize` (step 4) once you have even a
placeholder credential attached, and its response's `redirect_uri` field is the
exact value to paste into the provider's app-config page.

## 2. Install (or write) the template

X.com already has a template. Install it via the
`data_source_management` MCP tool:

```
action: data_source_install_template
template_slug: x-com
```

This materializes a credential-free source + endpoint manifest through
`Ai::DataSources::ConfigPortabilityService#import` — no secrets are set by
install. For X.com that's:

- **source**: `auth_scheme: bearer`, `auth_config` carrying `authorize_url`
  (`https://twitter.com/i/oauth2/authorize`), `token_url`
  (`https://api.twitter.com/2/oauth2/token`), `scope`
  (`tweet.read tweet.write users.read offline.access`), and
  `broker: { type: oauth2_authorization_code, token_url: ... }`.
- **endpoints**: `Recent search` (GET), `User tweets` (GET), and `Create post`
  (POST `/2/tweets`) — see step 5 for why the write endpoint looks the way it
  does.

For a NEW provider, write the equivalent manifest yourself (see §7). The
reference implementation is `Ai::DataSources::TemplateLibrary#x_com_template`
(`server/app/services/ai/data_sources/template_library.rb`).

## 3. Attach the OAuth2 app credential

`POST /api/v1/ai/data_sources/:data_source_id/credentials` with `client_id` +
`client_secret` from step 1 (requires `ai.data_sources.update`). This is the
ONLY way `client_id`/`client_secret` get set — `access_token`,
`refresh_token`, and `access_token_expires_at` are NOT accepted here; they are
written exclusively by the OAuth callback in the next step.

## 4. Run the connect flow

1. `POST /api/v1/ai/data_sources/:data_source_id/oauth/authorize` (JWT-authenticated,
   requires `ai.data_sources.update`). Returns `{ authorization_url, redirect_uri, state }`
   — `Ai::DataSources::OauthAuthorizationCodeService#build_authorize_request` mints
   PKCE (`code_verifier`/`code_challenge`) and `state`, stashing them server-side
   (`Rails.cache`, keyed by `state`, single-use, short TTL).
2. Send the operator's browser to `authorization_url`. They approve the requested
   scopes on the provider's consent screen.
3. The provider redirects the browser to
   `GET|POST /api/v1/ai/data_sources/:data_source_id/oauth/callback?code=...&state=...`.
   This action is **unauthenticated** (it's a third-party redirect, not an API
   call from our frontend) — its entire security model is the `state` value:
   the service looks up the pending PKCE/account/user/data_source context by
   `state` and rejects the callback if it's missing, expired, already
   consumed, or doesn't match the path's `data_source_id`. The path's
   `:data_source_id` is NEVER trusted on its own.
4. On a valid callback, the service exchanges `code` + `code_verifier` for
   `access_token`/`refresh_token` at the provider's `token_url` (SSRF-guarded
   connection, zero redirects) and persists them on the credential.

From here the credential silently self-refreshes: every signed fetch through
`Ai::DataSources::QueryService` first asks
`Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker` whether the
access token needs refreshing (`needs_refresh?`, default 60s buffer before
expiry) and, if so, exchanges the refresh token via the RFC 6749 §6
`refresh_token` grant before signing the request. No separate operator or
agent action refreshes anything.

## 5. Reading and publishing

Reads and writes both go through the SAME governed path — there is no
separate "execute" action. An agent (or the API layer, on the operator's
behalf) calls `data_source_query` (or `data_source_contract` /
`data_source_reconcile` / `data_source_failover_query`) with the endpoint to
run; `Ai::DataSources::QueryService` handles the kill flag, quota, cache,
circuit breaker, SSRF guard, decode/normalize/schema-validate/redact, and
audit trail regardless of whether the endpoint reads or writes.

What makes a write endpoint different is two things, both set on the endpoint
itself (see the `Create post` entry in the template above):

- `cache_ttl_seconds: 0` — `QueryService#cacheable_request?` refuses to cache
  or dedupe ANY non-GET/HEAD request (or one with `cache_ttl_seconds <= 0`)
  regardless of any other flag, so a retried POST always really posts rather
  than replaying a cached response.
- `metadata: { side_effecting: true }` — an explicit opt-in for endpoints that
  are technically GET/HEAD but still have a real external side effect (rare;
  most writes are already caught by the HTTP method check).

**Approval gate for autonomous agents.** An agent must not be able to
silently publish. `Ai::Tools::DataSourceTool` checks, for every action that
executes a single endpoint, whether that endpoint is a write (`http_method`
not `GET`/`HEAD`, or `metadata["side_effecting"] == true`). If it is, the
acting agent's account additionally needs `ai.data_sources.manage` (the same
permission the tool already treats as authorizing any state-changing action
against a data source — there is no separate "publish" permission). An agent
whose account lacks it never reaches `QueryService`: the tool instead files an
`Ai::AgentProposal` via `Ai::ProposalService` — the same proposal-fallback
pattern used for data-source-level mutations (create/update/delete) — and
returns `requires_approval: true` so a human can review and apply it. A user
calling through the authenticated API directly (no agent context) is
unaffected — `DataSourceTool#permission?` fails open when there's no agent,
matching the tool's existing model (the API layer already authorized the
call).

## 6. Revocation

`DELETE /api/v1/ai/data_sources/:data_source_id/credentials/:id` removes the
credential from the platform — nothing on this data source can authenticate
after that. This is a LOCAL delete only; it does not call the provider's own
token-revocation endpoint. For a full revoke, also remove the app's access
from the provider's side (for X.com: developer portal → your app →
"Revoke access", or the end-user-facing X.com Settings → Security and account
access → Apps and sessions).

## 7. Hardening note: OAuth callback logging

The callback's `code` and `state` query params can appear in Rails request
logs (as any GET query string can). This is low severity here: PKCE means a
logged `code` alone is useless without the `code_verifier` (which is never
logged, and never leaves the server), and `state` is single-use — consumed on
first read regardless of outcome, so a value seen in a log is already dead.
Deployments with a higher sensitivity bar may still want proxy-level
(reverse-proxy / access-log) scrubbing of the OAuth callback path
specifically. Do **not** add `:code`/`:state` to Rails' global
`filter_parameters` — those names are common enough (pagination cursors,
state-machine fields, feature-flag codes, etc.) across the rest of the
platform that a global filter would redact unrelated data everywhere else.

## Reference: what a new provider's template needs

A minimal OAuth2 provider template (see
`Ai::DataSources::TemplateLibrary#x_com_template` for the full worked
example):

- **source.auth_scheme**: `bearer` (the broker exchanges tokens for a bearer
  header; this is standard for OAuth2 APIs).
- **source.auth_config**: `authorize_url`, `token_url`, `scope` (space-
  separated, provider-specific), and `broker: { type: oauth2_authorization_code,
  token_url: <same> }`.
- **endpoints**: one entry per operation. Reads need nothing special beyond
  the usual `http_method`/`path_template`/`response_mapping`. A write needs
  `cache_ttl_seconds: 0` and, if it isn't already a non-GET/HEAD method,
  `metadata: { side_effecting: true }`.

No code changes are required to onboard a provider that fits this shape —
write the template, install it, register the app, connect, done.

## Files

- `server/app/services/ai/data_sources/template_library.rb` — template catalog
  (`x_com_template` is the worked example)
- `server/app/services/ai/data_sources/oauth_authorization_code_service.rb` —
  `#authorize` / `#callback` (PKCE, state, redirect_uri computation)
- `server/app/services/ai/data_sources/credentials/oauth2_authorization_code_broker.rb` —
  silent refresh
- `server/app/controllers/api/v1/ai/data_source_oauth_controller.rb` — REST
  surface for the connect flow
- `server/app/controllers/api/v1/ai/data_source_credentials_controller.rb` —
  attach/update/revoke the app credential
- `server/app/services/ai/tools/data_source_tool.rb` — the MCP tool, including
  the write-endpoint approval gate (`#write_endpoint?` / `#guarded_fetch` /
  `#propose_write`)
