# Single-Node Bootstrap (systemd installer path)

> Status: active
>
> When to use this runbook: deploying Powernode to a fresh Linux host as the **systemd-managed installation** — backend, worker, worker-web, frontend, and reverse-proxy as native services with apt-installed PostgreSQL + Redis underneath. This is the path used by `dev.ipnode.net`, the `ops` control plane, and (with `--production`) the first Vultr cutover before the modular self-host migration.
>
> This runbook covers the base install. For production operations around it (storage, backups, monitoring, scaling, rollback, readiness), see [`production-deployment.md`](production-deployment.md). If you want the long-term modular self-host path via the Go agent + System modules, that's a separate runbook (see [Golden Eclipse M3+](../../extensions/system/docs/CONTAINER_RUNTIMES.md)).

## Why this path exists

The systemd installer (`scripts/systemd/powernode-installer.sh`) is the **canonical single-node deployment** the platform's own dev environment uses. Production-grade in terms of hardening posture (`NoNewPrivileges`, `AmbientCapabilities` for CAP_NET_BIND_SERVICE only, dedicated service users), but lightweight in terms of dependencies — no Docker Engine, no Kubernetes, no container runtime. The reverse-proxy (Traefik) is bundled as a vendored binary that wraps go-acme/lego for DNS-01 challenges, and certificates are managed end-to-end through the platform's own `System::AcmeDnsCredential` + `Acme::CertificateManager` pipeline.

## Prerequisites

| Item | Requirement |
|---|---|
| OS | Ubuntu 24.04 LTS (other Debian-likes likely work; not tested) |
| Privilege | Operator user with `sudo` (NOPASSWD recommended for unattended installs) |
| Network | Outbound to apt mirrors, cloud-images.ubuntu.com, RVM, NVM, Cloudflare API, Let's Encrypt; inbound on 80/443 if the proxy will face the internet directly (DNS-01 doesn't require inbound 80) |
| Disk | 20 GB minimum, 80 GB recommended (Ruby gems + frontend node_modules + Postgres data) |
| RAM | 4 GB minimum, 8 GB recommended for production workloads |
| DNS / TLS | If terminating TLS on this host: API token at the DNS provider (Cloudflare/Route53/DigitalOcean/Hetzner/Porkbun/OVH) with DNS-edit + Zone-read on the target zone(s) |

## Procedure

### Step 1 — Install apt dependencies

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  postgresql-16 postgresql-16-pgvector postgresql-contrib \
  redis-server \
  build-essential libssl-dev libreadline-dev libyaml-dev libpq-dev \
    libxml2-dev libxslt1-dev zlib1g-dev libffi-dev libgmp-dev libsqlite3-dev \
  git curl wget rsync jq pkg-config autoconf bison \
  ca-certificates gnupg
```

Postgres and Redis come up as systemd services automatically (`postgresql@16-main.service` and `redis-server.service`). Both bind to localhost by default — leave it that way.

### Step 2 — Install Ruby via RVM

```bash
# RVM keys (signed install — required since 2014)
curl -sSL https://rvm.io/mpapis.asc | gpg --import -
curl -sSL https://rvm.io/pkuczynski.asc | gpg --import -

# Stable RVM
curl -sSL https://get.rvm.io | bash -s stable

# Source for current shell + install + default Ruby
source ~/.rvm/scripts/rvm
rvm install 3.2.8 --binary
rvm use 3.2.8 --default
```

The platform pins Ruby 3.2.8 (see `Gemfile`). RVM is preferred over rbenv/asdf because the installer's `detect_rvm_path` looks for `~/.rvm` or `/usr/local/rvm`.

### Step 3 — Install Node via nvm

```bash
curl -sSL -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR=$HOME/.nvm
source $NVM_DIR/nvm.sh
nvm install 24.5.0
nvm alias default 24.5.0
```

### Step 4 — Configure PostgreSQL

```bash
# Generate a random DB password (don't reuse dev's; ops/prod should have its own)
DB_PASS=$(openssl rand -hex 24)
echo "$DB_PASS" > ~/.postgres_password
chmod 600 ~/.postgres_password

# Create user + database via heredoc (avoid shell-escaping pitfalls of `psql -c`)
sudo -u postgres psql <<SQL
CREATE ROLE powernode WITH LOGIN PASSWORD '${DB_PASS}' CREATEDB;
CREATE DATABASE powernode_production OWNER powernode;
SQL

# Required extensions
sudo -u postgres psql -d powernode_production <<SQL
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
SQL
```

> **Gotcha #1**: `psql -c "CREATE ROLE ... PASSWORD '$DB_PASS'"` mangles the quoting via SSH and through bash `-c`. Always use a heredoc.

### Step 5 — Get the platform source code

Either clone fresh (production-style):

```bash
git clone https://github.com/nodealchemy/powernode-platform.git /home/$USER/powernode-platform
cd /home/$USER/powernode-platform
git submodule update --init --recursive
```

Or rsync from a working dev host (faster for ops adjacent to dev on the LAN):

```bash
# From the dev workstation:
rsync -az --info=stats2 \
  --exclude node_modules --exclude tmp/ --exclude log/ --exclude .bundle/ \
  --exclude server/storage/files/ --exclude server/coverage/ \
  --exclude frontend/dist/ --exclude frontend/build/ \
  --exclude .env \
  --exclude config/extensions_state.json \
  --exclude frontend/.proxy-config-cache.json \
  /path/to/powernode-platform/  target-host:/home/$USER/powernode-platform/
```

> **Gotcha #16**: `config/extensions_state.json` and `frontend/.proxy-config-cache.json` are deployment-specific state, not source code. The dev tree typically leaves all extensions enabled; ops/prod also need `business` disabled (gotcha #5). Likewise the proxy-cache file holds host allowlists specific to each environment. Always exclude both from rsync so deployment-local choices survive sync runs.

### Step 6 — Install Ruby gems

```bash
source ~/.rvm/scripts/rvm
cd ~/powernode-platform/server
bundle config set --local without development:test
bundle install --jobs 4

cd ~/powernode-platform/worker
bundle config set --local without development:test
bundle install --jobs 4
```

### Step 7 — Run the systemd installer

```bash
cd ~/powernode-platform
sudo scripts/systemd/powernode-installer.sh install
# (add --production to create a dedicated system user named `powernode`)
```

The installer:
- Detects `RVM_PATH`, `POWERNODE_RUBY_VERSION`, `NVM_DIR`, `NODE_VERSION`, `POWERNODE_BASE` from the current shell environment + cwd.
- Copies config templates from `scripts/systemd/configs/` to `/etc/powernode/`. **Skips files that already exist** (idempotent re-runs are safe).
- Installs systemd unit files from `scripts/systemd/units/` to `/etc/systemd/system/`, patching `User=` and `Group=` to the operator user.
- Enables `powernode-backend@default`, `powernode-worker@default`, `powernode-worker-web@default`, `powernode-frontend@default`.

> **Gotcha #2**: the installer auto-detects the Ruby version from `rvm current` output. If RVM isn't sourced in the sudo environment, detection fails silently (`Ruby version: not found` in the install output). The config template will still install, but `POWERNODE_RUBY_VERSION` may stay at the template default. Patch it manually in Step 8.

> **Gotcha #3**: `powernode-reverse-proxy@.service` ships **disabled** by default. The installer's "enable default service instances" loop doesn't include it. Enable it manually: `sudo systemctl enable powernode-reverse-proxy@default`.

### Step 8 — Patch `/etc/powernode/*.conf` for production

The installer's template defaults are tuned for development. Production needs:

#### `/etc/powernode/powernode.conf`

```
POWERNODE_BASE=/home/<operator>/powernode-platform  # or /opt/powernode if --production
POWERNODE_MODE=production
RVM_PATH=/home/<operator>/.rvm
POWERNODE_RUBY_VERSION=ruby-3.2.8
POWERNODE_REGISTRY_URL=<your-internal-registry>/powernode
NVM_DIR=/home/<operator>/.nvm
NODE_VERSION=24.5.0
OLLAMA_API_ENDPOINT=<optional, leave blank to disable>
```

#### `/etc/powernode/backend-default.conf`

```
PORT=3000
HOST=0.0.0.0
RAILS_ENV=production

DATABASE_HOST=localhost
DATABASE_USER=powernode
DATABASE_NAME=powernode_production
POWERNODE_DATABASE_PASSWORD=<from ~/.postgres_password>

REDIS_URL=redis://localhost:6379/0
ACTION_CABLE_REDIS_URL=redis://localhost:6379/2

# Rails secrets — generate ALL of these fresh (openssl rand -hex 64 for SECRET_KEY_BASE)
SECRET_KEY_BASE=<128 hex chars>
JWT_SECRET_KEY=<64 hex chars>        # NOTE: name is JWT_SECRET_KEY, NOT JWT_SECRET
WORKER_API_KEY=<64 hex chars>

# HS256 avoids needing JWT_PRIVATE_KEY (an RSA PEM). RS256 is the
# production-recommended algorithm, but PEM contents don't fit cleanly
# in systemd EnvironmentFile lines without escaping every newline. Set
# JWT_ALGORITHM=HS256 here, OR generate an RSA keypair and load via
# JWT_PRIVATE_KEY / JWT_PUBLIC_KEY (multi-line systemd env supported
# only via base64-encoding + decoding in the wrapper script — see
# powernode-bootstrap.sh).
JWT_ALGORITHM=HS256

# ActiveRecord encryption keys (required in production — initializer
# raises if all three are missing).
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=<32 chars>
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=<32 chars>
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=<32 chars>

# Puma sizing — tune for available RAM (each thread holds DB connections)
RAILS_MAX_THREADS=16
WEB_CONCURRENCY=2
DB_POOL=24

# jemalloc — reduces memory fragmentation under long-lived Rails processes
LD_PRELOAD=/lib/x86_64-linux-gnu/libjemalloc.so.2
MALLOC_CONF=dirty_decay_ms:1000,narenas:2,background_thread:true

RAILS_LOG_TO_STDOUT=true

# Disable libvirt unless this host has libvirtd locally + kvm group access
POWERNODE_LIBVIRT_MODE=disabled

POWERNODE_OCI_REGISTRY=<your-internal-registry>
POWERNODE_PLATFORM_URL=http://localhost:3000
```

#### `/etc/powernode/worker-default.conf` + `worker-web-default.conf`

```
WORKER_ENV=production
REDIS_URL=redis://localhost:6379/1
WORKER_CONCURRENCY=10

# WORKER_ID — populated AFTER db:seed (see step 10)
WORKER_ID=

PRIMARY_SERVICE_URL=http://localhost:3000
BACKEND_API_URL=http://localhost:3000

# Must match backend's JWT_SECRET_KEY (this is the bidirectional auth secret)
JWT_SECRET_KEY=<same value as backend's JWT_SECRET_KEY>

# Same AR encryption keys as backend (worker reads the same DB)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=<same>
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=<same>
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=<same>

DATABASE_HOST=localhost
DATABASE_USER=powernode
DATABASE_NAME=powernode_production
POWERNODE_DATABASE_PASSWORD=<same as backend>
```

#### `/etc/powernode/frontend-default.conf`

```
PORT=3001
HOST=0.0.0.0
VITE_API_BASE_URL=https://<external-hostname>
VITE_WS_BASE_URL=wss://<external-hostname>
NODE_ENV=production
```

After patching, reapply restrictive permissions:

```bash
sudo chown root:<operator-group> /etc/powernode/*.conf
sudo chmod 640 /etc/powernode/*.conf
```

### Step 9 — Initialize the database

```bash
source ~/.rvm/scripts/rvm
cd ~/powernode-platform/server

# Load all env (powernode.conf + backend-default.conf) into the shell so rails
# sees the secrets + connection strings.
set -a
. /etc/powernode/powernode.conf
. /etc/powernode/backend-default.conf
set +a

bundle exec rails db:create db:migrate db:seed
```

> **Gotcha #4**: `db:seed` only creates the admin Account/User in `development` or `test` mode by default. In production it skips the user seed entirely (look for `if Rails.env.development? || Rails.env.test? || ENV['SEED_ADMIN_USERS'] == 'true'` in `db/seeds.rb`), then `system_worker` creation immediately after FAILS with `Account can't be blank, Account must exist` because there's no Account for it to belong to. **Fix**: set `SEED_ADMIN_USERS=true` in the environment for the initial seed run on a fresh production install. This loads `db/seeds/cypress_test_users.rb` which writes admin credentials to `test-credentials.json` — review and rotate the admin password before exposing ops publicly.

> **Gotcha #5**: The business extension's `Ai::Marketplace::InstallationService` references an `InstallWorkflow` concern that doesn't exist in the repo (only 2 of 3 expected concern files are present: `rating_and_serialization.rb` and `update_and_uninstall.rb` — but NOT `install_workflow.rb`). Dev mode doesn't notice because Zeitwerk lazy-loads; production hits `eager_load_all` at boot which surfaces the missing constant. **Fix**: for ops/core-mode single-node deploys that don't need SaaS billing features, add `"business"` to `config/extensions_state.json`'s `disabled` list. The platform falls back to core mode automatically via `Shared::FeatureGateService`.

> **Gotcha #6**: Every extension engine adds `app/decorators/` to autoload_paths AND uses `config.to_prepare` to `load` the files explicitly. The decorator files use `Account.class_eval do ... end` and don't define their own constant — but Zeitwerk's `eager_load_all` in production still scans the dir and raises `Zeitwerk::NameError`. **Fix** (already in master after the ops bootstrap): each engine.rb has an `initializer "*.ignore_decorators"` block calling `Rails.autoloaders.main.ignore(decorators_path)` to tell Zeitwerk to skip the dir. The to_prepare load still runs decorators via path-based `load`. Engines patched: system, business, marketing, supply-chain.

> **Gotcha #7**: `Ai::CodeReview` was BOTH an ActiveRecord model class (`app/models/ai/code_review.rb` → `class CodeReview`) AND a services namespace (`app/services/ai/code_review/*.rb` → `module Ai; module CodeReview`). A Ruby constant can't be both. **Fix**: rename services dir to plural `code_reviews/` and update module declarations inside to `module CodeReviews`. Matches the platform's existing convention of singular-model-class + plural-services-namespace (e.g. `Ai::Agent` model + `app/services/ai/agents/`).

> **Gotcha #8** _(✅ resolved in master)_: the MCP workflow orchestrator (`workflow_executor.rb`) was dead code — its 7 concern files (`broadcasting.rb`, `data_flow.rb`, etc.) plus `concerns/ai_workflow_service.rb` were deleted in commit `a61ca9ef` "remove ai workflow services" but the orchestrator file itself was missed. **Fixed**: the file has since been deleted (no remaining references).

> **Status: not yet implemented** — the rename below has NOT landed in master. The controller still declares `class BaasController` and `inflections.rb` still defines the `BaaS` acronym, so the bug is still present in the tree (boot impact is limited only because this runbook's core-mode flow disables the business extension where the controller lives, per gotcha #5). Treat the fix as planned, not done.
>
> **Gotcha #9** _(⚠ open — see status note above)_: the BaaS controller (`baas_controller.rb`) declares `class BaasController`, but with the BaaS acronym in `inflections.rb` Zeitwerk expects `class BaaSController` (matching the `BaaS` model namespace). **Planned fix**: rename the class to `BaaSController`.

> **Gotcha #10**: Rails 8.1 includes the `solid_cache`, `solid_queue`, and `solid_cable` gems which auto-load `SolidCache::Record`, `SolidQueue::Record`, `SolidCable::Record` at boot — each calls `connects_to(database: { writing: :cache | :queue | :cable })`. Even if you override `CACHE_STORE=redis_cache_store`, `QUEUE_ADAPTER=async`, and `cable.yml` to use Redis, the gems still get required and their `Record` classes still demand the named databases exist in `database.yml`. **Fix**: extend `database.yml` `production:` block to multi-database with stubs for `primary`, `cache`, `queue`, `cable` all pointing to the same Postgres database. The Solid* gems will connect but won't actually be used because the env overrides keep them out of the request path. Future cleanup: `gem ... require: false` would let us drop the database stubs entirely.

> **Gotcha #11**: The server's `Gemfile` does NOT include `sidekiq` (the worker process has it separately). Setting `QUEUE_ADAPTER=sidekiq` in `backend-default.conf` causes `Gem::LoadError: sidekiq is not part of the bundle`. **Fix**: use `QUEUE_ADAPTER=async` for the server. The server enqueues jobs in-process; the worker service polls them via the HTTP API.

> **Gotcha #12**: Frontend systemd service fails with `sh: 1: vite: not found` because the rsync'd repo doesn't include `frontend/node_modules/`. **Fix**: `cd frontend && npm install` before starting the service.

> **Gotcha #13**: The `powernode-reverse-proxy@.service` unit file has `User=rett` hardcoded in the dev-tree version of the unit. The installer DOES patch User= via sed, but only one occurrence. **Fix**: `sudo sed -i 's/^User=.*/User=<operator>/; s/^Group=.*/Group=<operator>/' /etc/systemd/system/powernode-reverse-proxy@.service` to fix both lines, then `systemctl daemon-reload`.

> **Gotcha #14**: The reverse-proxy systemd unit only loads `powernode.conf` (NOT `backend-default.conf`). The wrapper script calls `bundle exec rails runner` to regenerate Traefik static config — but Rails boot needs `RAILS_ENV`, `ACTIVE_RECORD_ENCRYPTION_*`, `SECRET_KEY_BASE`, `JWT_SECRET_KEY`, DB credentials. **Fix**: promote these shared secrets to `/etc/powernode/powernode.conf` (the file ALL services load). Don't duplicate-only-in-backend-default.conf.

> **Gotcha #15**: Even with the env right, the wrapper script fails because Rails 8.1 initializers emit chatter to stdout BEFORE the `print Acme::TraefikConfigWriter.write_static_config!` line — "ActiveRecord Encryption configured", "[Sentry] Skipped - SENTRY_DSN not configured", "Initializing billing automation system", "Billing automation system initialized successfully", "JWT configured with algorithm: HS256", "Vault not configured in production - credentials stored in database". The script's `STATIC_CONFIG="$(bundle exec rails runner '...')"` captures all of this as a multi-line string, then `[[ ! -f "$STATIC_CONFIG" ]]` fails because the multi-line string isn't a valid file path. **Fix** (already in master): the wrapper script pipes through `| tail -n 1` to grab only the final non-newlined line which is the path itself (`print`, not `puts`, avoids a trailing newline so it stays the last line).

### Step 10 — Populate `WORKER_ID` post-seed

```bash
cd ~/powernode-platform/server
WORKER_ID=$(bundle exec rails runner 'puts Worker.system_worker.id' 2>/dev/null | tail -1)
sudo sed -i "s|^WORKER_ID=.*|WORKER_ID=${WORKER_ID}|" \
  /etc/powernode/worker-default.conf /etc/powernode/worker-web-default.conf
```

### Step 11 — Start the platform

```bash
sudo systemctl daemon-reload
sudo systemctl start powernode.target
sleep 5
sudo scripts/systemd/powernode-installer.sh status
```

All five services should be active:
- `powernode-backend@default`
- `powernode-worker@default`
- `powernode-worker-web@default`
- `powernode-frontend@default`
- `powernode-reverse-proxy@default`

Smoke test:

```bash
curl -sI http://localhost:3000/api/v1/health # → HTTP/1.1 200
curl -sI http://localhost:3001               # → HTTP 200 (frontend dev server)
```

### Step 12 — Configure ACME DNS-01

The platform stores DNS provider credentials in the database via `System::AcmeDnsCredential` (model: `extensions/system/server/app/models/system/acme_dns_credential.rb`). The actual API token is stored in Vault (or, in the absence of Vault, the database fallback path). The reverse-proxy systemd service consumes the resulting certs via `Acme::TraefikConfigWriter`.

Setup (Rails console):

```ruby
cred = System::AcmeDnsCredential.create!(
  account: Account.first,
  name: "powernode-cloudflare",  # match dev's naming if applicable
  provider: "cloudflare",        # or route53 / digitalocean / hetzner / porkbun / ovh
  status: "untested"
)
cred.store_in_vault(api_token: "<your-CF-token>")
```

If migrating from a working dev environment:

```ruby
# On the dev host:
src = System::AcmeDnsCredential.where(provider: "cloudflare").first
token = src.vault_credentials[:api_token]
# Then on the new host (via rails runner):
dest = System::AcmeDnsCredential.create!(account: Account.first, name: src.name, provider: src.provider)
dest.store_in_vault(api_token: token)
```

Trigger first cert issuance. `Acme::CertificateManager#issue!` takes a single `certificate:` keyword (a `System::AcmeCertificate` record) — common_name, dns_credential, issuer, and email are all read off that record. Create the record first, then issue:

```ruby
cert = System::AcmeCertificate.create!(
  account: Account.first,
  common_name: "ops.ipnode.net",
  dns_credential: cred,
  challenge_type: "dns-01",            # one of AcmeCertificate::CHALLENGE_TYPES
  issuer: "letsencrypt-prod",          # one of AcmeCertificate::ISSUERS
                                       #   (letsencrypt-prod / letsencrypt-staging / internal-ca)
  metadata: { "acme_email" => "admin@example.com" }  # email is resolved from
  # metadata["acme_email"], else POWERNODE_ACME_EMAIL env, else the account's admin user
)
Acme::CertificateManager.new.issue!(certificate: cert)
# (or the class-method form: Acme::CertificateManager.issue!(certificate: cert))
```

`Acme::RenewalSweepService` (background job, runs daily) handles renewals from here on.

### Step 13 — Verify HTTPS

```bash
curl -vk https://<external-hostname> 2>&1 | grep -E "(subject|issuer|HTTP)"
openssl s_client -connect <external-hostname>:443 -servername <external-hostname> </dev/null 2>&1 | grep -E "(subject=|issuer=)"
```

## Verification checklist

- [ ] All 5 systemd services active (`systemctl status 'powernode-*' --no-pager`)
- [ ] `curl http://localhost:3000/api/v1/health` returns 200 with `{status: "healthy"}` JSON
- [ ] `psql -U powernode -h localhost -d powernode_production -c 'SELECT 1'` succeeds with the DB password
- [ ] Sidekiq web UI reachable at `http://localhost:4567` (worker-web)
- [ ] `bundle exec rails runner 'puts Worker.system_worker.account_id'` returns a non-nil UUID
- [ ] `System::AcmeCertificate.where(status: "valid").any?` is true (after Step 12 issuance — successful issuance transitions the cert to `valid`; there is no `CertificateManager#list_certs` method)
- [ ] External HTTPS endpoint serves a Let's Encrypt cert (not self-signed, not Cloudflare edge)

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `ActiveRecord encryption primary_key not configured` | Production env requires explicit AR encryption keys | Set the three `ACTIVE_RECORD_ENCRYPTION_*` env vars in `backend-default.conf` AND `worker-default.conf`/`worker-web-default.conf` |
| `JWT_SECRET_KEY environment variable is required in production` | The env var name is `JWT_SECRET_KEY` (not `JWT_SECRET` or `JWT_TOKEN`) | Rename in backend-default.conf |
| `JWT_PRIVATE_KEY environment variable is required for RSA signing` | Default `JWT_ALGORITHM=RS256` in production needs an RSA PEM | Set `JWT_ALGORITHM=HS256` to use the existing HMAC secret, OR generate an RSA keypair (see `powernode-bootstrap.sh`) |
| `Failed to create system worker: Validation failed: Account can't be blank` | Production `db:seed` doesn't create admin Account by default (see gotcha #4) | Set `SEED_ADMIN_USERS=true` env var and re-seed |
| `uninitialized constant Ai::Marketplace::InstallationService::InstallWorkflow` | Business extension is referenced but `install_workflow.rb` concern file is missing (gotcha #5) | Add `"business"` to disabled list in `config/extensions_state.json` for core-mode deploys |
| `Zeitwerk::NameError: expected file .../decorators/models/account_decorator.rb to define constant Models::AccountDecorator` | Extension engines add `app/decorators` to autoload_paths but the files monkey-patch core (no own constant) | Already fixed in master (gotcha #6); each engine has `Rails.autoloaders.main.ignore(decorators_path)` |
| `CodeReview is not a module (TypeError)` | `Ai::CodeReview` was both model class and services namespace (gotcha #7) | Already fixed in master; services renamed to `Ai::CodeReviews::*` |
| `uninitialized constant Mcp::WorkflowExecutor::AiWorkflowService` | Dead code (gotcha #8) | Already fixed in master; orphan file deleted |
| `Zeitwerk::NameError: expected ... BaaSController, but didn't` | Controller defines `BaasController`; with the BaaS acronym Zeitwerk expects `BaaSController` (gotcha #9) | **Not yet fixed** — rename has not landed. Disable the `business` extension (gotcha #5) to avoid eager-loading the controller, or rename `BaasController` → `BaaSController` |
| `The 'cache'/'queue'/'cable' database is not configured for the 'production' environment` | Solid* gems demand named DBs even when env overrides disable them (gotcha #10) | Already fixed in master; database.yml production has multi-db stubs |
| `Gem::LoadError: sidekiq is not part of the bundle` | Server doesn't bundle sidekiq directly (gotcha #11) | Set `QUEUE_ADAPTER=async` in backend-default.conf |
| Frontend service: `sh: 1: vite: not found` | npm packages not installed (gotcha #12) | `cd frontend && npm install` before starting the service |
| Reverse-proxy: `Failed to determine user credentials: No such process; status=217/USER` | The `User=rett` line in the dev-tree unit file wasn't patched by installer's sed (gotcha #13) | `sudo sed -i 's/^User=.*/User=<operator>/; s/^Group=.*/Group=<operator>/' /etc/systemd/system/powernode-reverse-proxy@.service && systemctl daemon-reload` |
| `psql: error: connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed: FATAL: database "..." does not exist` | Shell escaping mangled the CREATE DATABASE statement | Use a heredoc, not `psql -c "..."` |
| `RVM not found. Set RVM_PATH in /etc/powernode/powernode.conf` | The reverse-proxy/backend wrapper script can't find RVM | Set `RVM_PATH=/home/<operator>/.rvm` explicitly in `/etc/powernode/powernode.conf` |
| Reverse proxy service stays `disabled` | The installer only enables backend/worker/worker-web/frontend by default | `sudo systemctl enable powernode-reverse-proxy@default` |
| `MTU mismatch` warnings in journald | Service listens on jumbo-frame interface but talks to local services on lo (MTU 65536) | Usually harmless; verify by checking `ss -tlnp` lists the right binds |

## Standardized installer script

A standardized wrapper around the above steps lives at `scripts/systemd/powernode-bootstrap.sh`. It's idempotent (safe to re-run) and exposes the gotcha-prone steps as named subcommands:

```bash
sudo scripts/systemd/powernode-bootstrap.sh deps        # Step 1: apt
sudo scripts/systemd/powernode-bootstrap.sh ruby        # Step 2: RVM + Ruby (runs as operator)
sudo scripts/systemd/powernode-bootstrap.sh node        # Step 3: nvm + Node
sudo scripts/systemd/powernode-bootstrap.sh postgres    # Step 4: DB user + db + extensions
sudo scripts/systemd/powernode-bootstrap.sh secrets     # Step 8: generate + inject secrets
sudo scripts/systemd/powernode-bootstrap.sh dbinit      # Step 9: db:create + migrate + seed
sudo scripts/systemd/powernode-bootstrap.sh workerid    # Step 10: populate WORKER_ID
sudo scripts/systemd/powernode-bootstrap.sh start       # Step 11: systemctl start powernode.target
sudo scripts/systemd/powernode-bootstrap.sh all         # everything in order
```

ACME setup (Step 12) is intentionally kept manual — choosing the right DNS provider + storing the API token securely warrants per-deployment thought.

## Open items / future work

- **Vault integration**: Step 12 currently uses database fallback for credentials. Production deployments should deploy Vault first (`docs/infrastructure/vault-example/`) and have `Acme::DnsCredential.store_in_vault` write to a real Vault.
- **RS256 JWT in production**: HS256 is acceptable but RS256 is preferred for any deployment where the JWT could be inspected by an untrusted party. Generate the RSA pair in `powernode-bootstrap.sh secrets`, base64-encode the PEM, and decode in the backend wrapper script.
- **Modular self-host migration**: The systemd installer path is canonical *for now* but slated to be replaced by the Go agent + System modules path under Golden Eclipse M3+. This runbook should be marked deprecated and a `single-node-modular-bootstrap.md` written when that landed.

---

_Last verified: 2026-06-04_
