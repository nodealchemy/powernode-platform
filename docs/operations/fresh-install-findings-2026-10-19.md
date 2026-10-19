# Fresh-install findings — first clean developer install (2026-10-19)

> **Status:** findings report (audit = report only). Nothing in this file has been fixed in code yet;
> each item records the symptom, the root cause, the workaround used on the install, and a proposed fix.
> Deployment-specific names are placeholders (`<dev-host>`, `<ops-hub-host>`); the real values live in
> platform knowledge (`deployment-*` tags).

## Context

First from-scratch install of Powernode on a **plain Ubuntu 24.04 desktop host** (`<dev-host>`), following
[getting-started/01-quickstart.md](../getting-started/01-quickstart.md) and
[contributing/development-setup.md](../contributing/development-setup.md), with the user-scope systemd path
(`scripts/systemd/powernode-installer.sh install --user`). Toolchains via **mise** (no RVM/NVM), core mode
(no private extensions). Until now every dev environment was a module-composed **dev-cell**, which masks most of
the items below: the cell's modules pre-bake the runtimes, the PKI, the DB and the secrets.

Severity: **P1** blocks a working install · **P2** wrong/misleading, workaround needed · **P3** friction.

## Summary

| # | Sev | Area | Finding |
|---|-----|------|---------|
| 1 | P1 | worker | Worker cert manager reads `node.crt` from a dev-cell path even in dev, defeating the existing dev-mTLS header path |
| 2 | P1 | worker | `worker/config.ru` crashes on a missing `.session.key`; nothing creates it |
| 3 | P1 | installer | `install --user` writes configs with no secrets; the secrets generator is system-scope + RVM only |
| 4 | P1 | worker | `WORKER_ID` chicken-and-egg: it only exists after the first account, which only exists after the wizard |
| 5 | P2 | docs | Quickstart says the seed creates the admin; in core mode it does not (setup wizard + one-time token) |
| 6 | P1 | seeds | `comprehensive_ai_providers_seed.rb` is gated on a hardcoded demo account ⇒ core mode seeds **no real LLM provider** (and prints a false `❌ Error`) |
| 7 | P2 | schema | Committed `schema.rb` lags migrations; `db:test:prepare` leaves the test DB pending |
| 8 | P2 | frontend | `frontend-default.conf` pins `VITE_API_BASE_URL=http://localhost:3000` → broken for any remote browser |
| 9 | P2 | frontend | Vite `allowedHosts` is separate from the backend trusted-hosts list (`manage-proxy-hosts.sh`) |
| 10 | P2 | installer | User-scope units cannot see mise/asdf toolchains; installer auto-detects the wrong ruby |
| 11 | P2 | config | `powernode.conf` template pins stale runtimes (ruby-3.3.0, NODE_VERSION=22) vs repo pins (3.2.8, 24.13) |
| 12 | P3 | docs | Prerequisites omit the native build deps; `database.yml` copy step not in the quickstart |
| 13 | P3 | hooks | `install-git-hooks.sh` suggests `gitleaks@latest`; the gate's pinned version (8.21.2) is not documented |
| 14 | P2 | hub | ops-hub ingress does not route `/.well-known/*` → MCP OAuth discovery fails for Claude Code |
| 15 | P2 | hub | ops-hub cert CN is a different name than the hub's other DNS name → TLS name mismatch |
| 16 | P1 | fleet | Abandoned-instance reaper auto-destroyed the dev-cell (disks included) during a hub-wide heartbeat outage |
| 17 | P3 | knowledge | The canonical dev-mTLS knowledge entry exists as 8+ identical copies (re-imported every few days) |
| 18 | P1 | onboarding | Wizard attaches the operator's API key to the non-routable `claude-code` bookkeeping provider; concierge bound to it ⇒ 412 |
| 19 | P2 | onboarding | Default model is free text with a stale default and no validation against the provider's models |
| 20 | P3 | models | Catalog + seeds pin literal model ids that lag the API (live sync works once a credential exists) |
| 21 | P2 | onboarding | `/onboarding/complete` posts `provider_credential_id: nil` (wizard state lost across steps / token refresh) |
| 22 | P3 | frontend | ProvisioningPage shows a generic "Failed to start a provisioning conversation." and drops the backend's reason |
| 23 | P2 | agents | The GLOBAL canonical concierge agent is bound to one account's (non-routable) provider |
| 24 | P2 | gate | `scripts/validate.sh` fails on a clean `develop` checkout (3 checks unrelated to any local change) |
| 25 | P2 | mcp | Each unclosed MCP session mints a new `<client> #N` agent; idle sessions never expire (13 minted in one day) |
| 26 | P2 | fleet | `system_destroy_instance` always fails in core mode: it queries a private-extension billing table |
| 27 | P3 | approvals | Every approval ends in a "shown once — save it now" modal, even when nothing secret was minted |

## Findings

### 1. Worker requires an mTLS client cert with no dev fallback — P1

- **Symptom:** `powernode-worker-web@default` crash-loops at boot; every Sidekiq job that calls the backend dies:
  `No such file or directory @ rb_sysopen - /persist/var/lib/powernode/pki/node.crt`.
- **Cause:** a dev-mode auth path **already exists** and is half-wired. In development the worker injects a
  synthetic `X-Forwarded-Tls-Client-Cert-Info` header carrying a sentinel CN
  (`worker/app/services/dev_mtls_header.rb`, `BackendApiClient#inject_dev_mtls_header`), and the server binds the
  system Worker to that sentinel (`Workers::EnsureSystemWorker#bind_dev_sentinel`) — no cert, no Traefik needed.
  But `WorkerCertManager#ssl_options` (`worker/app/services/worker_cert_manager.rb`) only tolerates a missing cert
  in the **test** env, so in development it still `File.read`s `node.crt` from
  `DEFAULT_PKI_DIR = '/persist/var/lib/powernode/pki'` (the dev-cell agent's path) even when `BACKEND_API_URL` is
  plain `http://`. Dev-cells always had an agent-provisioned cert there, which masked the contradiction.
  `BackendApiClient` builds its connection in `initialize`, so worker-web dies at boot rather than at first use.
- **Workaround:** none applied yet. Minting a cert with `rails worker:bootstrap_self_host` is not the right answer
  here (it generates a private key from a rake task, against the CLAUDE.md crypto rule, and the dev header path
  makes it unnecessary).
- **Proposed fix:** `ssl_options` returns no client cert when the backend URL is `http://` (TLS options are
  meaningless there) or in development when the PKI files are absent — mirroring the existing test-env branch.
  Spec first (dev env + http URL + no PKI dir ⇒ no `Errno::ENOENT`). Also: clear error instead of a backtrace when
  a cert *is* required, and don't open the backend connection in `BackendApiClient#initialize`.

### 2. `worker/config.ru` crashes on a missing `.session.key` — P1

- **Symptom:** worker-web exits: `config.ru:28:in 'read': No such file or directory - .session.key`.
- **Cause:** `use Rack::Session::Cookie, secret: File.read(".session.key")` with no generator anywhere in the
  install path (the file is correctly gitignored).
- **Workaround:** `openssl rand -hex 64 > worker/.session.key` (mode 0600).
- **Proposed fix:** generate on first boot (or from an env var like `SIDEKIQ_WEB_SESSION_SECRET` written by the
  installer's secrets step).

### 3. `install --user` produces configs without secrets — P1

- **Symptom:** after `powernode-installer.sh install --user`, `~/.config/powernode/*.conf` contain
  placeholders: no `SECRET_KEY_BASE`, no `ACTIVE_RECORD_ENCRYPTION_*`, `WORKER_ID=your_worker_id_here`.
- **Cause:** secret generation lives only in `scripts/systemd/powernode-bootstrap.sh cmd_secrets`, which is
  root-only, writes `/etc/powernode/`, and assumes RVM (`source ~/.rvm/scripts/rvm`) and a
  `~/.postgres_password` file.
- **Workaround:** generated the same values by hand into the user configs (mode 0600), mirroring `cmd_secrets`.
- **Proposed fix:** `powernode-installer.sh install --user` (or a `bootstrap.sh secrets --user`) that writes the
  secrets into `~/.config/powernode/` and is toolchain-agnostic.

### 4. `WORKER_ID` chicken-and-egg — P1

- **Symptom:** worker + worker-web refuse to start: `Missing required environment variables: WORKER_ID`.
- **Cause:** the system Worker is created by `Workers::EnsureSystemWorker`, which no-ops until an Account exists;
  in core mode the first account comes from the setup wizard. So on a fresh install the services cannot start
  until the wizard is done **and** someone runs `db:seed` again **and** copies `Worker.system_worker.id` into two
  config files (`bootstrap.sh cmd_workerid`, system-scope only).
- **Workaround:** wizard → `db:seed` → `rails runner 'puts Worker.system_worker&.id'` → `sed` into
  `worker-default.conf` and `worker-web-default.conf` → restart.
- **Proposed fix:** have `Setup::FirstAdminService` (which already ensures the worker) be the trigger, and have the
  worker resolve its identity from the backend (or the installer write it) instead of a hand-copied UUID.

### 5. Quickstart's admin story is wrong for core mode — P2

- **Symptom:** quickstart step 1 says "The seed step creates the initial admin account"; it does not.
- **Cause:** demo seeding is opt-in (`POWERNODE_SEED_DEMO` / `SEED_ADMIN_USERS`). The real first-admin path is the
  setup wizard, gated by a one-time token that is **only printed in the backend log** (`[setup] Open this one-time
  URL…`). Quickstart step 4 instead shows creating a user in `rails c`, which bypasses the wizard (and the system
  Worker creation that hangs off it — see #4).
- **Proposed fix:** document the wizard + where to find the token (`journalctl --user -u powernode-backend@default
  | grep 'one-time URL'`), and drop or caveat the console snippet.

### 6. Core-mode seed prints a false `❌ Error` — P2

- **Symptom:** every core-mode `db:seed` ends a section with `❌ Error: Could not find admin account and user`.
- **Cause:** `server/db/seeds/comprehensive_ai_providers_seed.rb:9-10` looks up the demo account by name
  (`"Powernode Admin"` / `admin@powernode.org`).
- **Consequence (found via #18):** because the provider catalog is never seeded in core mode, a fresh install
  has **no routable LLM provider at all** — the only Anthropic-typed row is the `claude-code` bookkeeping scope.
- **Proposed fix:** seed the (credential-less) provider catalog as BASELINE per account (not demo), through the same
  seam `ai_claude_code_provider_seed.rb` uses, and drop the hardcoded account lookup.

### 7. Committed `schema.rb` lags migrations — P2

- **Symptom:** `rails db:test:prepare` succeeds, then rspec aborts listing pending migrations.
- **Cause:** `server/db/schema.rb` is at version `2026_09_29_121500`; **6** core migrations are newer (through
  `20261002070000_create_system_task_logs.rb`). [fresh-install.md](./fresh-install.md) documents
  `db:schema:load` as the canonical path, so a fresh install from the committed schema is incomplete.
- **Workaround:** `RAILS_ENV=test bundle exec rails db:migrate`.
- **Proposed fix:** re-dump `schema.rb` (core-only, per the fresh-install procedure) and add a gate check that its
  version ≥ the newest migration.

### 8. Frontend config pins the API to `localhost` — P2

- **Symptom:** the UI served from `http://<dev-host>:3001` makes API/WebSocket calls to the *viewer's*
  `localhost:3000`.
- **Cause:** `scripts/systemd/configs/frontend-default.conf` sets `VITE_API_BASE_URL=http://localhost:3000` and
  `VITE_WS_BASE_URL=ws://localhost:3000`. Without them the app already defaults to same-origin `/api/v1` and Vite
  proxies `/api/v1` + `/cable` to `127.0.0.1:3000` (`frontend/vite.config.ts`).
- **Workaround:** commented both out in `~/.config/powernode/frontend-default.conf`.
- **Proposed fix:** remove them from the template; same-origin is the correct default.

### 9. Two separate "allowed host" lists — P2

- **Symptom:** after adding `<dev-host>` with `scripts/manage-proxy-hosts.sh`, Vite still answers
  `Blocked request. This host ("<dev-host>") is not allowed.`
- **Cause:** `manage-proxy-hosts.sh` manages the backend trusted-hosts list; Vite reads `VITE_ALLOWED_HOSTS` and
  `frontend/.proxy-config-cache.json` (`getAllowedHosts()` in `vite.config.ts`), populated only by
  `npm run refresh-proxy`.
- **Workaround:** `VITE_ALLOWED_HOSTS=<dev-host>,…` in `frontend/.env.local`.
- **Proposed fix:** have `manage-proxy-hosts.sh` refresh the Vite cache too (or have Vite read the backend list),
  and mention it in the script's output.

### 10. User-scope units can't find mise/asdf toolchains — P2

- **Symptom:** services start with the system Ruby 3.2.3 / no Node; the installer's auto-detect wrote
  `POWERNODE_RUBY_VERSION=ruby-3.2.3`.
- **Cause:** the wrappers (`powernode-{backend,worker,frontend}.sh`) know RVM/NVM or bare `PATH`; the systemd user
  manager's `PATH` has no shim dirs.
- **Workaround:** `~/.config/environment.d/50-mise.conf` (`PATH=$HOME/.local/share/mise/shims:…`) plus
  `systemctl --user set-environment PATH=…` for the running manager.
- **Proposed fix:** installer detects mise/asdf/rbenv and writes the environment.d entry (or a `PATH=` line in
  `powernode.conf`).

### 11. `powernode.conf` template runtimes are stale — P2

- `scripts/systemd/configs/powernode.conf` ships `POWERNODE_RUBY_VERSION=ruby-3.3.0` and `NODE_VERSION=22`; the
  repo pins Ruby **3.2.8** (`.ruby-version`) and Node **24.13** (`.node-version`, `>=24.9` in `package.json`).
  Derive them from the pin files instead.

### 12. Prerequisites are incomplete — P3

- Missing from the quickstart table: native build deps (`build-essential`, `libpq-dev`, `libyaml-dev`,
  `libssl-dev`, `zlib1g-dev`, `libffi-dev`), `imagemagick` (mini_magick), `libjemalloc2` (referenced by
  `LD_PRELOAD` in the generated backend config), the distro pgvector package name (`postgresql-16-pgvector`), and
  the superuser-created extensions (`ltree`, `pg_trgm`, `pgcrypto`, `vector` — documented only in
  fresh-install.md).
- The `cp config/database.yml.example config/database.yml` step is not in the quickstart.
- Playwright needs `npx playwright install --with-deps chromium` for the e2e suite.

### 13. gitleaks version — P3

- `scripts/install-git-hooks.sh` suggests `go install …/gitleaks/v8@latest`; the validation gate's version is
  pinned to **8.21.2** only in `extensions/system/modules/gitleaks/manifest.yaml`. Document the pin.

### 14. ops-hub: `/.well-known/*` not routed to the backend — P2

- **Symptom:** Claude Code's MCP OAuth discovery gets the SPA's `index.html` for
  `/.well-known/oauth-protected-resource` and `/.well-known/oauth-authorization-server`.
- **Cause:** `HOST_LOGIN_BACKEND_PREFIXES = %w[/api /up /cable /agent /rails/health]`
  (`server/app/services/core/ingress_config_writer.rb:73`) omits `/.well-known`; everything else falls through to
  the frontend router. Rails serves both documents correctly when reached directly.
- **Workaround:** a Claude Code `headersHelper` that runs the OAuth 2.1 + PKCE flow against `/api/v1/oauth/*` and
  refreshes the token itself.
- **Proposed fix:** add `/.well-known` to the prefix list (spec first).

### 15. ops-hub TLS name mismatch — P2

- The hub's self-signed cert names only one of the hub's two DNS names; clients using the other name fail
  verification even with the cert trusted. Either issue the cert with both SANs or standardise on one name in
  docs/knowledge.

### 16. Reaper destroyed a live dev-cell — P1 (incident)

- **What happened (2026-10-15 05:41Z):** `AbandonedInstanceSensor` flagged the dev-cell instance (`status=error`,
  no heartbeat > 7 days). `approval_reasons` was empty, so the signal carried `requires_approval: false` and
  `system.abandoned_instance_reap` auto-approved; the provider terminate destroyed the VM **and its disks**
  (all of the operator's persisted home: dotfiles, `~/.claude`, workspace).
- **Why it was wrong:** the hub's *own* instance stopped heartbeating 27 s after the dev-cell did (2026-10-07) —
  heartbeat ingestion was down fleet-wide, not the cell. The provider still reported the guest `running` on
  2026-10-09. The sensor keys on platform `status`, not provider power state, and never checks hub self-silence.
- **Proposed fix (`extensions/system/server/app/services/system/fleet/sensors/abandoned_instance_sensor.rb`):**
  (a) treat provider `running` as an approval reason regardless of platform status; (b) suppress the lane while
  the hub's own instance is silent; (c) make guests holding a persistent home (dev-cell template) always require
  approval; (d) snapshot before terminate.
- **Related:** the dev-cell instance row's `cloud_instance_id` VMID was subsequently reused by CI builders, which
  made the loss hard to see.

### 17. Duplicated knowledge entries — P3

- `search_knowledge` for worker mTLS returns the same "Dev worker↔backend mTLS: centralized synthetic cert-info
  header" entry **8 times** (identical content, `source_type: import`, `imported_from: compound_learning`, same
  `source_learning_id`, created at ~2–4-day intervals from 2026-07-03 to 2026-07-19). The learning→knowledge import
  is not idempotent on `source_learning_id`, so recall results are crowded out by copies.
- **Proposed fix:** upsert on `source_learning_id` in the importer; one-off dedupe of existing copies (bulk op —
  operator-confirmed).

### 18. Wizard binds the API key to the `claude-code` bookkeeping provider — P1

- **Symptom:** after completing the wizard the UI lands on "Failed to start a provisioning conversation.";
  backend log: `POST /api/v1/ai/conversations/concierge … Completed 412 Precondition Failed`, reason
  `Provider 'Claude Code (local sessions)' is unavailable: Provider is inactive`. The provider shows
  API Base URL `https://claude-code.invalid`.
- **Cause:** `ai_claude_code_provider_seed.rb` creates one INACTIVE, credential-less, non-routable `claude-code`
  provider per account (a recording scope for Claude Code runs; `.invalid` is deliberate). Its `provider_type` is
  `anthropic`. `onboardingApi.createAiProvider` (`frontend/src/features/onboarding/services/onboardingApi.ts`)
  does `GET /ai/providers?provider_type=anthropic` and reuses `items[0]` — the bookkeeping row, since no real one
  was seeded (#6). The credential lands on it, and `ConversationsController#create_concierge` binds the concierge
  agent to it; `ProviderAvailabilityService.check_provider` then fails on `is_active=false` (it would also fail on
  "No models configured").
- **Proposed fix:** exclude non-routable scope providers from the onboarding lookup (filter on slug / a
  `routable` flag server-side in `/ai/providers`), make the backend refuse credentials on the `claude-code` scope,
  and seed the real catalog (#6).

### 19. Default model: free text, stale default, unvalidated — P2

- `ProviderCredentialForm.tsx` `default_model` is a text input defaulting to `claude-sonnet-4-6`; any string is
  stored in the credential (`opus-5.5` was accepted; the API id is `claude-opus-5-5`). Offer a select populated from
  the provider's synced model list, validated server-side.

### 20. Stale model ids in the catalog and seeds — P3 (corrected)

- `Ai::ProviderCatalog` (`server/app/models/ai/provider_catalog.rb`) ships 5 Anthropic models and lags the API (no
  `claude-opus-5-5` / `claude-sonnet-5-5` / `claude-haiku-5-5` / `claude-fable-5-1`); seeds hardcode Claude 4.x ids
  (`ai_dev_team_seed.rb`, `ai_governance_seed.rb`, `ai_example_templates_seed.rb`, …). **Correction:** the live sync
  (`Ai::ProviderManagementService.sync_provider_models` → `GET /v1/models`) works and returned 14 current ids on this
  install; `claude-fable-5` / `claude-opus-4-8` are real ids (an earlier draft wrongly called them nonexistent;
  `claude-opus-6` only appears in a comment). Remaining gap: seeds/templates pin literal ids instead of resolving
  through the provider's synced list, and nothing triggers a sync when the onboarding credential is created on a
  freshly built provider.

### 21. `/onboarding/complete` loses the credential id — P2

- Backend log shows `POST /api/v1/onboarding/complete {"provider_credential_id"=>nil, "provider_type"=>nil}`
  ~2 minutes after the credential was created (with a 401 → `/auth/refresh` in between). Wizard state should be
  persisted server-side (account setup metadata) rather than held only in client state.

### 22. Generic provisioning error hides the cause — P3

- `frontend/src/pages/ProvisioningPage.tsx:71,75` replace the backend's 412 message with a fixed string; surface
  `error` from the response (it already names the provider and reason) with a link to the provider settings.

### 23. Global canonical concierge bound to an account's provider — P2

- The global canonical "Powernode Assistant" (`account_id` NULL, the template account principals are cloned from)
  has `ai_provider_id` pointing at this account's `claude-code` scope provider. A global template referencing an
  account-scoped row is a cross-tenant reference; every account's principal inherits a provider that isn't theirs
  (and here isn't routable). Canonicals should carry no provider (or a provider *type*), resolved per account at
  clone time (`Ai::Agents::AccountPrincipalResolver`).
- **Local repair (2026-10-19):** only the account principal was rebound (to a catalog-built "Claude AI
  (Anthropic)" provider holding the moved credential, default model `claude-opus-5-5`, live-synced models); the
  canonical was left as found for the fix to address.

### 24. The verification gate is red on a clean `develop` — P2

- `scripts/validate.sh --skip-tests --skip-ts` on `origin/develop` (plus only the #1 worker fix) fails 3 checks that
  touch none of the changed files: *Claude Code agent skeletons are up to date* (`rails claude:sync_agents` stale),
  *No new local copies of shared UI primitives (ledger equality)*, and the *Claude context budget*
  (`.claude/agents/powernode/tools` 48009 bytes vs a 47954 budget). A gate that is red at HEAD can't tell a
  contributor whether *their* change broke it.
- **Proposed fix:** regenerate the skeletons / ledger on `develop`, and make CI block merges that leave the gate red.

### 25. Unclosed MCP sessions mint a new agent each — P2

- **Symptom:** the hub accumulated 13 `Claude Code (headersHelper) #1–#13` agents in one day.
- **Cause:** `Ai::McpClientIdentityService#find_existing_agent` reuses an agent for the same OAuth application only
  when no *active* session occupies it. A client that sends `initialize` per call and never sends `DELETE` (a
  scripted JSON-RPC wrapper used during this install) leaves every session active, so each call mints a new agent;
  sessions have no idle expiry to release them.
- **Workaround:** stopped using the wrapper (native MCP client sessions are long-lived). The 13 agents await
  operator-confirmed cleanup (streamlining campaign C8).
- **Proposed fix:** expire MCP sessions after an idle window (and treat idle-expired sessions as unoccupied for
  reuse); cap agents per OAuth application.

### 26. `system_destroy_instance` is unusable in core mode — P2

- **Symptom:** every call returns "Internal error"; backend log:
  `PG::UndefinedTable: relation "business_billing_provisioning_usage_records" does not exist`. No rows are deleted.
- **Cause:** the verb's FK walk (documented as covering `billing_provisioning_usage_records`) unconditionally touches a
  table that only exists when the private billing extension is installed — a core → private-extension coupling
  (core-purity) that breaks the one sanctioned way to clear ghost instance rows on a core-mode hub. Because
  `system_delete_node` refuses on the SDWAN FKs and points operators at this verb, ghost nodes cannot be removed
  through the platform at all.
- **Workaround used (hub cleanup 2026-10-19):** guarded delete of the 7 blocking SDWAN rows
  (`system_sdwan_host_vrf_assignments`, `system_node_instance_peers`) for terminated instances, then
  `system_delete_node`.
- **Proposed fix:** walk only tables that exist (or register extension-owned dependents through an extension seam);
  include `system_sdwan_host_vrf_assignments` / `system_node_instance_peers` in the walk; spec in core mode.

### 27. "Shown once" modal after every approval — P3

- **Symptom:** approving an ordinary request (e.g. an intervention-policy write) opens `OneShotRevealModal`
  ("Approved — shown once … This approval ran an operation that minted new material … Save it now") and demands an
  acknowledgement click.
- **Cause:** `Ai::DeferredOperation#execute_now!` put every executor's raw return into the reveal-once slot
  (`@revealed_result = result_data`); the approve endpoint returns it as `revealed_result` and the queue and bell both
  open the modal whenever it is non-empty. The slot exists only for executors that MINT secrets (federation
  acceptance tokens, keys).
- **Fix (branch feature/reveal-only-secrets):** reveal only when `Ai::SensitiveParams.filter` masked something — the
  same test that keeps secrets out of the persisted `:result`. Spec: an approved operation whose result holds no
  secret returns no `revealed_result`; the minting case is unchanged.

### 28. Pre-commit hook skips the secret scan on a mise install — P2

- **Symptom:** every commit prints `gitleaks not installed - skipping secret scan` and proceeds, although gitleaks
  8.21.2 is installed through mise (step 2 of the recipe below).
- **Cause:** git runs hooks with a non-interactive environment that does not activate mise, and the hook only looks
  for `gitleaks` on `PATH`; a missing scanner is a warning, not a failure.
- **Workaround:** run `mise exec -- gitleaks git --log-opts="<base>..HEAD"` by hand before pushing.
- **Fix:** resolve the scanner through `mise which gitleaks` (or `$HOME/.local/share/mise/shims`) before falling
  back to `PATH`, and fail closed when `scripts/validate.sh` is the gate. Covered by the `environment.d` PATH fix (#10)
  only for login sessions, not for hooks started from tools that bypass it.

### 29. CI runners auto-upgraded into a broken version — P1

- **Symptom:** the first push after the install (core run 2018, system run 2017) fails every job within ~12 s,
  before any project code runs: `git clone --no-checkout https://github.com/actions/checkout … exec: "git":
  executable file not found in $PATH`. Jobs without a checkout pass.
- **Cause:** the three Gitea Actions runners moved from act_runner v3.2.0 (last green run, 2026-10-03) to v5.1.0
  with no change on the platform side. v5 fetches remote actions with the host's `git` binary, which the runner
  environment lacks; it also logs `docker proxy not started … chown docker.sock: operation not permitted`.
- **Also:** platform knowledge placed the runners on a hypervisor that does not host them, so locating the runner
  host took a cluster-wide search and still needed the operator.
- **Fix:** pin the runner version (or use an image that ships `git`) and turn off auto-update for the runners; record
  the runner host in deployment knowledge. Longer term, CI preflight could check the runner version and fail with a
  clear message instead of a mid-step clone error.

## Install recipe that worked (for the eventual doc fix)

1. Root: apt deps (#12) + `postgresql-16-pgvector` + `redis-server`; create a superuser dev role; `loginctl
   enable-linger`.
2. User: mise → Ruby 3.2.8, Node 24.13.0, Go 1.25, gitleaks 8.21.2; `environment.d` PATH (#10).
3. `bundle install` (server, worker); `npm ci` (root, frontend); `cp database.yml.example database.yml`.
4. `powernode-installer.sh install --user`; write secrets (#3); remove frontend API pins (#8).
5. `db:create db:migrate db:seed`; `RAILS_ENV=test db:migrate` (#7).
6. Start `powernode.target`; complete the wizard with the token from the backend log (#5).
7. `db:seed` again; copy `WORKER_ID` (#4); create `worker/.session.key` (#2).
8. Worker mTLS (#1) — unresolved.
