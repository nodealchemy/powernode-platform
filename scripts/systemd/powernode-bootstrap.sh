#!/usr/bin/env bash
# Powernode single-node bootstrap helper
#
# Wraps the gotcha-prone steps from docs/operations/single-node-bootstrap.md
# into idempotent subcommands. Designed to be re-runnable: each subcommand
# checks current state and skips work that's already done.
#
# Usage (one step at a time):
#   sudo scripts/systemd/powernode-bootstrap.sh deps
#   sudo scripts/systemd/powernode-bootstrap.sh ruby      (runs as operator, not root)
#   sudo scripts/systemd/powernode-bootstrap.sh node
#   sudo scripts/systemd/powernode-bootstrap.sh postgres
#   sudo scripts/systemd/powernode-bootstrap.sh installer
#   sudo scripts/systemd/powernode-bootstrap.sh secrets
#   sudo scripts/systemd/powernode-bootstrap.sh dbinit
#   sudo scripts/systemd/powernode-bootstrap.sh workerid
#   sudo scripts/systemd/powernode-bootstrap.sh start
#
# Or one-shot:
#   sudo scripts/systemd/powernode-bootstrap.sh all
#
# ACME credentials + cert issuance are intentionally NOT automated — they
# require choosing a DNS provider and storing an API token securely. Use
# the rails console snippets in docs/operations/single-node-bootstrap.md
# Step 12 after this script completes.

set -euo pipefail

OPERATOR_USER="${SUDO_USER:-${USER:-$(whoami)}}"
OPERATOR_HOME="$(getent passwd "$OPERATOR_USER" | cut -d: -f6)"
PLATFORM_BASE="${POWERNODE_BASE:-${OPERATOR_HOME}/powernode-platform}"
RAILS_ENV_TARGET="${RAILS_ENV_TARGET:-production}"
DB_NAME="${DB_NAME:-powernode_production}"
DB_USER="${DB_USER:-powernode}"
RUBY_VERSION="${RUBY_VERSION:-3.2.8}"
NODE_VERSION="${NODE_VERSION:-24.5.0}"
CONFIG_DIR=/etc/powernode

log()   { printf "\033[0;34m[%-8s]\033[0m %s\n" "$1" "$2"; }
ok()    { printf "\033[0;32m[OK]\033[0m       %s\n" "$1"; }
warn()  { printf "\033[0;33m[WARN]\033[0m     %s\n" "$1"; }
err()   { printf "\033[0;31m[ERR]\033[0m      %s\n" "$1" >&2; }

as_operator() {
  # Run a command as the operator user (not root). Loads their interactive
  # shell so RVM / nvm are sourced.
  sudo -u "$OPERATOR_USER" -i bash -lc "$1"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "This subcommand must be run via sudo"
    exit 1
  fi
}

# ──────────────────────────────────────────────────────────────────
cmd_deps() {
  require_root
  log "DEPS" "Installing apt dependencies"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    postgresql-16 postgresql-16-pgvector postgresql-contrib \
    redis-server \
    build-essential libssl-dev libreadline-dev libyaml-dev libpq-dev \
      libxml2-dev libxslt1-dev zlib1g-dev libffi-dev libgmp-dev libsqlite3-dev \
    git curl wget rsync jq pkg-config autoconf bison \
    ca-certificates gnupg
  systemctl enable --now postgresql redis-server
  ok "apt deps installed; postgres + redis running"
}

# ──────────────────────────────────────────────────────────────────
cmd_ruby() {
  require_root
  if as_operator "[[ -x ~/.rvm/rubies/ruby-${RUBY_VERSION}/bin/ruby ]]"; then
    ok "Ruby ${RUBY_VERSION} already installed for ${OPERATOR_USER}"
    return 0
  fi
  log "RUBY" "Installing RVM + Ruby ${RUBY_VERSION} for ${OPERATOR_USER}"
  as_operator "
    set -e
    if [[ ! -d ~/.rvm ]]; then
      curl -sSL https://rvm.io/mpapis.asc 2>/dev/null | gpg --import - 2>/dev/null || true
      curl -sSL https://rvm.io/pkuczynski.asc 2>/dev/null | gpg --import - 2>/dev/null || true
      curl -sSL https://get.rvm.io | bash -s stable >/dev/null 2>&1
    fi
    source ~/.rvm/scripts/rvm
    rvm install ${RUBY_VERSION} --binary
    rvm use ${RUBY_VERSION} --default
    gem install bundler --conservative
  "
  ok "Ruby ${RUBY_VERSION} ready"
}

# ──────────────────────────────────────────────────────────────────
cmd_node() {
  require_root
  if as_operator "[[ -x ~/.nvm/versions/node/v${NODE_VERSION}/bin/node ]]"; then
    ok "Node ${NODE_VERSION} already installed for ${OPERATOR_USER}"
    return 0
  fi
  log "NODE" "Installing nvm + Node ${NODE_VERSION} for ${OPERATOR_USER}"
  as_operator "
    set -e
    if [[ ! -d ~/.nvm ]]; then
      curl -sSL -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null 2>&1
    fi
    export NVM_DIR=\$HOME/.nvm
    source \$NVM_DIR/nvm.sh
    nvm install ${NODE_VERSION} >/dev/null 2>&1
    nvm alias default ${NODE_VERSION}
  "
  ok "Node ${NODE_VERSION} ready"
}

# ──────────────────────────────────────────────────────────────────
cmd_postgres() {
  require_root
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" | grep -q 1; then
    ok "Database ${DB_NAME} already exists; skipping"
    return 0
  fi

  local pass_file="${OPERATOR_HOME}/.postgres_password"
  if [[ ! -f "$pass_file" ]]; then
    sudo -u "$OPERATOR_USER" bash -c "openssl rand -hex 24 > '$pass_file' && chmod 600 '$pass_file'"
    ok "Generated DB password → $pass_file (mode 600)"
  fi
  local db_pass
  db_pass=$(cat "$pass_file")

  log "POSTGRES" "Creating user + database + extensions"
  sudo -u postgres psql <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${db_pass}' CREATEDB;
  END IF;
END \$\$;
SQL
  sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
  sudo -u postgres psql -d "${DB_NAME}" <<SQL
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
SQL
  ok "Postgres ready: ${DB_USER}@localhost → ${DB_NAME}"
}

# ──────────────────────────────────────────────────────────────────
cmd_installer() {
  require_root
  if [[ -f "${CONFIG_DIR}/backend-default.conf" ]]; then
    ok "${CONFIG_DIR}/backend-default.conf exists — installer already ran"
    return 0
  fi

  log "INSTALLER" "Running scripts/systemd/powernode-installer.sh install"
  pushd "$PLATFORM_BASE" >/dev/null
  scripts/systemd/powernode-installer.sh install
  popd >/dev/null

  # The installer ships reverse-proxy disabled — enable it now.
  systemctl enable powernode-reverse-proxy@default 2>&1 | grep -v "^$" || true
  ok "systemd units installed and enabled"
}

# ──────────────────────────────────────────────────────────────────
cmd_secrets() {
  require_root
  local conf_be="${CONFIG_DIR}/backend-default.conf"
  local conf_wk="${CONFIG_DIR}/worker-default.conf"
  local conf_ww="${CONFIG_DIR}/worker-web-default.conf"

  if grep -q "^SECRET_KEY_BASE=" "$conf_be" 2>/dev/null && \
     grep -q "^ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=" "$conf_be" 2>/dev/null; then
    ok "Secrets already populated; skipping"
    return 0
  fi

  log "SECRETS" "Generating fresh secrets + injecting into /etc/powernode/*.conf"
  local pass_file="${OPERATOR_HOME}/.postgres_password"
  if [[ ! -f "$pass_file" ]]; then
    err "DB password file missing — run 'postgres' subcommand first"
    exit 1
  fi
  local db_pass=$(cat "$pass_file")
  local secret_key_base=$(openssl rand -hex 64)
  local jwt_secret=$(openssl rand -hex 32)
  local worker_api_key=$(openssl rand -hex 32)
  local ar_primary=$(openssl rand -base64 48 | tr -d '\n=/+' | head -c 32)
  local ar_deterministic=$(openssl rand -base64 48 | tr -d '\n=/+' | head -c 32)
  local ar_salt=$(openssl rand -base64 48 | tr -d '\n=/+' | head -c 32)

  # ── backend-default.conf ────────────────────────────────────────
  cat > "$conf_be" <<EOF
# Generated by powernode-bootstrap.sh — single-node bootstrap (${RAILS_ENV_TARGET})
PORT=3000
HOST=0.0.0.0
RAILS_ENV=${RAILS_ENV_TARGET}

DATABASE_HOST=localhost
DATABASE_USER=${DB_USER}
DATABASE_NAME=${DB_NAME}
POWERNODE_DATABASE_PASSWORD=${db_pass}

REDIS_URL=redis://localhost:6379/0
ACTION_CABLE_REDIS_URL=redis://localhost:6379/2

SECRET_KEY_BASE=${secret_key_base}
JWT_SECRET_KEY=${jwt_secret}
JWT_ALGORITHM=HS256
WORKER_API_KEY=${worker_api_key}

ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${ar_primary}
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${ar_deterministic}
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${ar_salt}

RAILS_MAX_THREADS=16
WEB_CONCURRENCY=2
DB_POOL=24

LD_PRELOAD=/lib/x86_64-linux-gnu/libjemalloc.so.2
MALLOC_CONF=dirty_decay_ms:1000,narenas:2,background_thread:true
RAILS_LOG_TO_STDOUT=true

POWERNODE_LIBVIRT_MODE=disabled
POWERNODE_PLATFORM_URL=http://localhost:3000
EOF

  # ── worker + worker-web ─────────────────────────────────────────
  for f in "$conf_wk" "$conf_ww"; do
    cat > "$f" <<EOF
# Generated by powernode-bootstrap.sh
WORKER_ENV=${RAILS_ENV_TARGET}
REDIS_URL=redis://localhost:6379/1
WORKER_CONCURRENCY=10
WORKER_ID=

PRIMARY_SERVICE_URL=http://localhost:3000
BACKEND_API_URL=http://localhost:3000

JWT_SECRET_KEY=${jwt_secret}

ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${ar_primary}
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${ar_deterministic}
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${ar_salt}

DATABASE_HOST=localhost
DATABASE_USER=${DB_USER}
DATABASE_NAME=${DB_NAME}
POWERNODE_DATABASE_PASSWORD=${db_pass}
EOF
  done

  # worker-web has a couple extras
  cat >> "$conf_ww" <<EOF
SIDEKIQ_WEB_HOST=127.0.0.1
SIDEKIQ_WEB_PORT=4567
EOF

  # Restrictive permissions
  chown root:"${OPERATOR_USER}" "$conf_be" "$conf_wk" "$conf_ww"
  chmod 640 "$conf_be" "$conf_wk" "$conf_ww"
  ok "Secrets generated and written to /etc/powernode/*.conf"
}

# ──────────────────────────────────────────────────────────────────
cmd_dbinit() {
  require_root
  log "DBINIT" "Running db:create + db:migrate + db:seed (idempotent)"

  # GOTCHA #5: business extension's installation_service references missing
  # InstallWorkflow concern; production eager_load surfaces it. Disable for
  # core-mode single-node deploys.
  local ext_state="${PLATFORM_BASE}/config/extensions_state.json"
  if [[ -f "$ext_state" ]] && ! grep -q '"business"' "$ext_state"; then
    log "DBINIT" "Adding 'business' to disabled extensions (core mode)"
    as_operator "cd ${PLATFORM_BASE} && python3 -c '
import json
state = json.load(open(\"config/extensions_state.json\"))
state.setdefault(\"disabled\", [])
if \"business\" not in state[\"disabled\"]:
    state[\"disabled\"].append(\"business\")
json.dump(state, open(\"config/extensions_state.json\", \"w\"), indent=2)
print(state)'"
  fi

  # GOTCHA #4: SEED_ADMIN_USERS=true forces admin Account + User creation
  # in production. Without it, system_worker seed fails because no Account
  # exists for it to belong to.
  as_operator "
    source ~/.rvm/scripts/rvm
    set -a
    . ${CONFIG_DIR}/powernode.conf
    . ${CONFIG_DIR}/backend-default.conf
    set +a
    export SEED_ADMIN_USERS=true
    cd ${PLATFORM_BASE}/server
    bundle exec rails db:create 2>&1 | tail -3 || true
    bundle exec rails db:migrate 2>&1 | tail -5
    bundle exec rails db:seed 2>&1 | tail -20 || true
    # Second pass in case the first hit transient issues (idempotent seeds)
    bundle exec rails db:seed 2>&1 | tail -10
  "
  ok "Database initialized + seeded"
}

# ──────────────────────────────────────────────────────────────────
cmd_workerid() {
  require_root
  log "WORKERID" "Populating WORKER_ID in worker configs"
  local worker_id
  worker_id=$(as_operator "
    source ~/.rvm/scripts/rvm
    set -a
    . ${CONFIG_DIR}/powernode.conf
    . ${CONFIG_DIR}/backend-default.conf
    set +a
    cd ${PLATFORM_BASE}/server
    bundle exec rails runner 'puts Worker.system_worker&.id' 2>/dev/null | tail -1
  ")
  if [[ -z "$worker_id" || "$worker_id" == "nil" ]]; then
    err "Could not resolve Worker.system_worker.id — db:seed may not have completed"
    exit 1
  fi
  sed -i "s|^WORKER_ID=.*|WORKER_ID=${worker_id}|" \
    "${CONFIG_DIR}/worker-default.conf" "${CONFIG_DIR}/worker-web-default.conf"
  ok "WORKER_ID=${worker_id} written to worker + worker-web configs"
}

# ──────────────────────────────────────────────────────────────────
cmd_start() {
  require_root
  log "START" "Starting powernode.target"
  systemctl daemon-reload
  systemctl start powernode.target
  sleep 5
  systemctl --no-pager status 'powernode-*' 2>&1 | grep -E "(●|Active:)" | head -20
}

# ──────────────────────────────────────────────────────────────────
cmd_all() {
  cmd_deps
  cmd_ruby
  cmd_node
  cmd_postgres
  cmd_installer
  cmd_secrets
  cmd_dbinit
  cmd_workerid
  cmd_start
  echo ""
  ok "Bootstrap complete. Next: configure ACME via rails console (see docs/operations/single-node-bootstrap.md §Step 12)"
}

# ──────────────────────────────────────────────────────────────────
case "${1:-}" in
  deps|ruby|node|postgres|installer|secrets|dbinit|workerid|start|all)
    "cmd_${1}"
    ;;
  *)
    cat <<USAGE
Usage: sudo $0 <subcommand>

Subcommands (in canonical order):
  deps        Install apt dependencies
  ruby        Install RVM + Ruby ${RUBY_VERSION} for operator user
  node        Install nvm + Node ${NODE_VERSION} for operator user
  postgres    Create DB user + database + extensions
  installer   Run powernode-installer.sh install (systemd units + config templates)
  secrets     Generate + inject SECRET_KEY_BASE, JWT_SECRET_KEY, AR encryption keys, etc.
  dbinit      rails db:create + db:migrate + db:seed (handles seed-ordering race)
  workerid    Resolve Worker.system_worker.id + populate worker configs
  start       systemctl start powernode.target

  all         Run all of the above in order

See docs/operations/single-node-bootstrap.md for the full runbook, including
ACME credential setup (Step 12) which is intentionally NOT automated.
USAGE
    exit 1
    ;;
esac
