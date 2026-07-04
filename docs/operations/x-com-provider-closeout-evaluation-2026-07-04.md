# x-com-provider campaign — closeout evaluation (2026-07-04)

Closeout (plan increment I7) for campaign `019f2ba3-9fc2-71fa-9c8f-a7fbe4b4d06c`
(`x-com-provider`), branch `campaign/019f2ba3-9fc2-71fa-9c8f-a7fbe4b4d06c`.
Plan: `~/.claude/plans/can-we-add-x-com-hazy-bachman.md`. Eleven commits, STAGE-only,
delivered increments I1–I6 + I8 (audit-registration fix discovered mid-campaign).

## Recommendation: **GO**

Merge to `develop` and deploy. The delivered seam is complete against the plan, the
security posture is strong and test-asserted, and every gate is green. The residual
risks below are real but none is a landing blocker for a single-user/core-mode
deployment; the top two are queued (campaign proposal `019f2c3d-ff8e`) as fast-follows.

## Verification gate (all green)

| Gate | Result |
|---|---|
| Backend rspec (6 commanded spec files) | **209 examples, 0 failures** |
| Backend rspec (3 additional touched spec files: query_service, registry, credentials request) | **128 examples, 0 failures** |
| Frontend `tsc --noEmit` | clean |
| Frontend jest (`data-sources` + `DataSourcesApiService`) | **16 passed, 0 failed** (13 + 3) |
| `scripts/pattern-validation.sh` | **43/43 pass**, 0 warnings |
| `gitleaks detect` | clean (exit 0) |

## Plan adherence

Every seeded increment landed, matching the plan's specified shape:

- **I2** (f6c7a9a7) — explicit `encrypted_client_id/_secret/_access_token/_refresh_token`
  columns + `access_token_expires_at` + `oauth_scopes` (jsonb, lambda default);
  `token_expired?`/`needs_refresh?(buffer:)`; controller permits `client_id`/`client_secret`
  only — tokens never client-submitted.
- **I1** (f7bee07a) — provider-agnostic authorize/callback pair; S256 PKCE (64-byte
  verifier), 32-byte single-use state (Rails.cache, 10-min TTL, consumed on read),
  path-vs-state cross-check ("never trust the path over the state").
- **I3** (9afe4514 + 10be29bc) — `Oauth2AuthorizationCodeBroker` (registry:
  `oauth2_authorization_code`): silent pre-fetch refresh, rotated-refresh-token
  persistence, RFC 6749 §6 keep-existing-on-omit, loud-but-degrading failure
  (`record_failure!` + scoped `RefreshError` caught by `BaseBroker#acquire`);
  shared `OauthTokenEndpoint` parsing.
- **I4** (ed938ecd + fda5b0a2) — `x_com_template` (read: recent-search, user-tweets;
  write: POST /2/tweets with `cache_ttl_seconds: 0` + `side_effecting: true`);
  QueryService `cacheable_request?` write-safety gate (see Security).
- **I6** (a94321ec + e4000330) — agent-write approval gate (see Security) + the
  provider-onboarding guide + learning/knowledge contribution.
- **I5** (252d5403 + c3dc88e6) — connect panel (permission-gated via
  `currentUser?.permissions?.includes('ai.data_sources.update')`, password fields with
  `autoComplete="new-password"`, redirect-URI copy, connected state + scopes + expiry),
  callback → frontend redirect with `?oauth=` status, consumed once and stripped.
- **I8** (f9f06d5e) — `AI_DATA_SOURCE_ACTIONS` registered in `AuditActions` so the
  oauth/credential key-op audit rows actually persist; request specs assert persisted
  `AuditLog` rows for authorize + callback success/failure.

Live end-to-end (real X app registration, operator authorization, live post) is
correctly **parked** as an operator action, per the plan.

## Security assessment (OAuth2 / crypto-material)

Verified in code and covered by asserted specs:

- **PKCE + state**: S256, verifier never returned or logged; state ≥32 bytes entropy,
  server-side stash keyed by state (account/user/source/credential-scoped), single-use
  (replay spec asserts second callback rejected), 10-min TTL, path cross-check.
- **Token endpoint hardening**: `max_redirects: 0` on BOTH the code exchange and the
  refresh grant; `HttpConnectionFactory.validate_url!` SSRF check on `token_url`
  (spec exercises the real guard with a blocked literal IP); `expires_in` clamped to
  86 400 s in both paths.
- **No secret leakage**: all rescue paths log `e.class` only; specs assert the log
  contains no access/refresh token or client_secret and `last_error` is secret-free;
  serializer exposes only derived booleans (`oauth_configured`/`oauth_connected`/
  expiry), never raw credential fields; gitleaks clean.
- **Storage**: Rails 8 `encrypts` on all four new columns; tokens written only by the
  callback/broker, never accepted from client params.
- **Write-safety (POST never cached/deduped)**: `QueryService#cacheable_request?`
  excludes non-GET/HEAD and `ttl<=0` endpoints from cache lookup, singleflight,
  stale-if-error, AND the finalize write-back (belt-and-suspenders at two layers);
  integration specs assert an identical retried POST re-dispatches and is never
  cache-written. Also fixes the pre-existing `ttl_for(0)→DEFAULT_TTL` trap.
- **Agent-write approval gate**: `write_endpoint?` (non-GET/HEAD or
  `metadata.side_effecting`) gates ALL FOUR execute paths — query, contract,
  reconcile (per-target), failover (up-front pre-scan of every candidate, since a
  fallback attempt could otherwise dispatch mid-iteration). Deny path files an
  `Ai::AgentProposal`; specs assert QueryService is never instantiated on deny and
  dispatches when `ai.data_sources.manage` is held. No bypass found.
- **Audit**: authorize + callback (success and failure) persist audit rows; failure
  attribution preserved via the state's own ids (never the untrusted path param).
- **State stash is cross-process safe**: production cache is SolidCache (DB) by
  default or Redis via `REDIS_URL` — never per-process memory in production.

## Residual risks (ranked; none landing-blocking for core mode)

1. **User-path write-gate asymmetry** (moderate). Interactive
   `endpoints_query` (`data_sources_controller.rb` `validate_permissions`) requires only
   `ai.data_sources.query` with no side-effecting distinction — a query-only user can
   publish (POST /2/tweets), while agents need `ai.data_sources.manage`. Deliberate per
   plan ("interactive user posts execute directly") and low-exposure in single-user core
   mode, but semantically `query` should not imply publish in multi-user accounts.
   → Queued in proposal `019f2c3d-ff8e` (write-gate parity). Recommend fixing before
   granting `ai.data_sources.query` to non-admin users.
2. **`auth_config` serialized raw to `read`-permission holders** (low-moderate).
   By design non-secret (URLs/scopes), and the portability allowlist screens exports —
   but the serializer itself doesn't screen, so a secret-ish knob an operator stuffs
   into `auth_config` would be exposed. Defense-in-depth fast-follow: screen through
   the same `secret_key?` filter.
3. **Callback `code`/`state` in request logs** (low). GET query params can hit Rails
   request logs. PKCE makes a bare logged code unusable and the state is already dead
   (single-use). Documented in knowledge `019f2c04` with the proxy-scrub option; do NOT
   globally filter `:code`/`:state` (over-redaction).
4. **No reactive refresh-on-401** (low). `needs_refresh?` is `false` when the provider
   returned no `expires_in` (nil expiry = treated as non-expiring). X always returns
   7200, so moot here; a future provider omitting it would 401 without auto-refresh.
   Note for provider wave 2 (`019f2c3d-b331`).
5. **Platform-side delete ≠ provider-side revoke** (low, documented). DELETE credential
   doesn't call the provider's revoke endpoint; guide + knowledge tell the operator to
   revoke portal-side too.
6. **Rails.cache read-then-delete not atomic** (very low, documented in-code). Narrow
   replay window on an already-single-use CSRF token; not worth a distributed lock.

## Reusability for provider #2+

Strong. The connect flow, broker, token-endpoint parsing, write gate, and connect UX
are all provider-agnostic (the frontend panel keys off `auth_config.authorize_url`
presence, not the X template). Provider #2 is a template + portal registration:
`docs/guides/adding-oauth2-data-source-provider.md` §7 + knowledge `019f2c04-a0cf` +
new skill `external-oauth2-provider-integration`. One doc drift found and fixed in
this closeout: the guide's "no dedicated UI yet" note predated I5's shipped connect UX.

## Learning-loop verification (I6 contribution)

- Learning `019f2c04-7691` ("Add an external OAuth2 provider via the Ai::DataSource
  seam — template + broker, config not code", best_practice, team) — present, accurate.
- Knowledge `019f2c04-a0cf` ("Procedure: add a new OAuth2 data-source provider",
  procedure, team, 8 steps incl. revocation + log-hardening caveats) — present,
  accurate, already used once.

## Process-health gaps observed (fed into proposals)

- Skill graph grades **F (25.5)** — freshness 0.0, effectiveness 0.23, 119 active
  conflicts, duplicated seed batches; and ALL seeded skills are `is_system: true`,
  immutable to `update_skill`, so the "evolve the relevant skills" loop cannot do
  targeted edits — only new-skill creation works. → proposal `019f2c3d-f16d`.
- No frontend-developer platform agent existed for I5; AuditActions registry has no
  extension seam (the I8 bug class is systemic). → proposal `019f2c3d-ff8e`.

## Closeout actions taken (this session)

- Skills created (additive, individually revertible):
  `019f2c3c-d257` External OAuth2 Provider Integration ·
  `019f2c3d-046f` Write-Safety and Key-Op Audit Review ·
  `019f2c3d-517c` CC Mirror Session Bootstrap.
- Campaign proposals queued (operator approval required, none started):
  `019f2c3d-b331` provider wave 2 · `019f2c3d-c2a3` marketing adoption ·
  `019f2c3d-d25a` content→publish · `019f2c3d-def4` growth analytics ·
  `019f2c3d-f16d` skill-graph health · `019f2c3d-ff8e` self-improvement seams.
