#!/usr/bin/env bash
# prepare-extension-test-db.sh — build the test database INCLUDING private-extension tables.
#
# WHY THIS EXISTS (root cause of "private tables missing from the test DB")
# ------------------------------------------------------------------------
# The committed server/db/schema.rb is CORE-ONLY by design: private-extension tables must never
# leak into the public core schema. Private extensions instead ship their tables as mounted-engine
# migrations under extensions/private/*/server/db/migrate/. Those migrations are timestamped far
# BELOW the current core schema version, so the Rails-standard preparation path
# (`db:prepare` / `db:schema:load`) loads the core schema and then `assume_migrated_upto_version`
# records EVERY migration version <= the schema version as already-applied — including the private
# ones — WITHOUT running them. The private tables are therefore never created, yet schema_migrations
# claims they are, so a follow-up `db:migrate` is a no-op. Net effect: business_* / trading_* and
# every other private table is silently absent from any test DB prepared the normal way, while the
# schema_migrations table insists everything is up.
#
# THE FIX (CI-safe — no live DB needed — keeps schema.rb core-only)
# -----------------------------------------------------------------
#   1. (re)create the TEST database and load the CORE schema,
#   2. delete the private extensions' migration versions from schema_migrations (un-assume them),
#   3. run db:migrate with the PRIVATE bundle so those engine migrations actually execute and
#      create their tables,
#   4. never touch the tracked core-only schema.rb: the post-migrate auto-dump is disabled
#      (config/initializers/schema_dump_isolation.rb) and step 3 sends any dump to a SCHEMA= temp
#      sink, so a full/private-mode dump can never land in it — and uncommitted edits survive.
#
# Private extensions are discovered dynamically from extensions/private/* — NONE is named here
# (public-safe). In core mode (no private extensions present) this degrades to a plain core
# `db:prepare`. Operates on the TEST database ONLY (RAILS_ENV=test); never touches dev/prod.
#
# RELATION TO maintain_test_schema! (purge-deadlock hardening)
# -------------------------------------------------------------
# server/spec/rails_helper.rb deliberately does NOT call
# ActiveRecord::Migration.maintain_test_schema!. That Rails default auto-invokes
# db:test:prepare, whose purge (a) can deadlock/half-complete against concurrent
# rspec processes and leave schema_migrations dropped or empty, and (b) reloads
# the CORE-ONLY schema.rb, re-assuming the private-extension migrations as applied
# without running them — silently destroying the tables this script built.
# rails_helper instead runs a READ-ONLY check_all_pending! and aborts with a
# pointer here. THIS SCRIPT is the one sanctioned way to (re)build a test DB.
#
# RECOVERY (stale schema / "pending migrations" abort / deadlocked half-prepare)
# ------------------------------------------------------------------------------
#   1. Stop any rspec/parallel_tests processes still attached to the test DB
#      (a half-completed purge usually means one is holding a connection):
#          pkill -f rspec   # scoped to this checkout if you run multiple
#   2. Re-run this script from the repo root of the affected checkout/worktree:
#          bash scripts/prepare-extension-test-db.sh
#      It drops and rebuilds the isolated test DB (TEST_ENV_NUMBER from
#      server/.env.test.local) including private-extension tables.
#   3. If db:drop itself hangs on "database is being accessed by other users",
#      terminate the stragglers, then retry step 2:
#          psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity
#                   WHERE datname = '<your powernode_test…>' AND pid <> pg_backend_pid();"
#
# TWO LOCKS, two different concerns:
#
#   1. Per-checkout lock (fd 9, keyed by repo path): correctness. Serializes
#      concurrent invocations for the SAME checkout so two sessions can't
#      interleave drop/create/migrate (the other cause of a half-prepared
#      DB). Different worktrees use different lock files here (and different
#      TEST_ENV_NUMBER databases), so they are logically independent and
#      would otherwise be free to run at the same time.
#
#   2. Global I/O lock (fd 8, one fixed path shared by every worktree):
#      throughput. Logical isolation doesn't imply physical isolation — every
#      worktree's Postgres connections land on the SAME running instance and
#      the SAME disk. Several worktrees each running db:drop/create/schema:load
#      or db:migrate at once causes severe fsync contention (observed: a
#      prep that normally takes well under a minute took 15+ minutes with 3
#      concurrent worktrees). This lock wraps only the heavy DB-mutating
#      commands so those steps run one-at-a-time platform-wide, while
#      unrelated work (bundling, migration-version scanning, etc.) still
#      proceeds in parallel.
#
# Usage:
#   scripts/prepare-extension-test-db.sh                 # prepare the test DB for THIS checkout/worktree
#   (the isolated TEST_ENV_NUMBER is read from server/.env.test.local automatically in the test env)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Serialize concurrent preps of the SAME checkout (see header, lock 1). Keyed
# by repo path so distinct worktrees (distinct test DBs) don't contend.
LOCK_FILE="${TMPDIR:-/tmp}/prepare-extension-test-db.$(printf '%s' "$REPO" | sha1sum | cut -d' ' -f1).lock"
exec 9>"$LOCK_FILE"
if ! flock -w 900 9; then
  echo "error: another prepare-extension-test-db.sh run for $REPO is still holding" >&2
  echo "       $LOCK_FILE after 15min — investigate/kill it, then retry." >&2
  exit 1
fi

# Serialize heavy DB I/O ACROSS ALL worktrees (see header, lock 2). Fixed
# path (not keyed by repo) so every worktree contends for the same lock.
# Separate fd (8, not 9) since a single process holds both locks at once.
# GLOBAL_IO_LOCK_FILE / fd 8 are opened below, once the target cluster (hence its port) is known.
db_io_lock() {
  if ! flock -n 8; then
    echo "[prepare-extension-test-db] waiting for another worktree's DB prep to finish (I/O-serializing lock)..." >&2
    # Poll with a bounded wait per attempt instead of one 30min blocking call, so we can
    # log a heartbeat while waiting — a silent multi-minute block is indistinguishable
    # from a hang to anyone watching output.
    local elapsed=0
    local interval=60
    local budget=1800
    until flock -w "$interval" 8; do
      elapsed=$((elapsed + interval))
      if [ "$elapsed" -ge "$budget" ]; then
        echo "error: timed out after 30min waiting for the GLOBAL DB I/O lock" >&2
        echo "       ($GLOBAL_IO_LOCK_FILE) — this is the cross-worktree I/O lock," >&2
        echo "       distinct from the per-checkout lock above. Investigate which" >&2
        echo "       worktree's prepare-extension-test-db.sh is stuck holding it." >&2
        exit 1
      fi
      echo "[prepare-extension-test-db] still waiting on global DB-IO lock, ${elapsed}s elapsed..." >&2
    done
  fi
}
db_io_unlock() {
  flock -u 8
}
SERVER="$REPO/server"
[ -d "$SERVER" ] || { echo "error: $SERVER not found" >&2; exit 1; }

export RAILS_ENV=test

# Use the private bundle ONLY in private mode (private extensions on disk), so the engine migrations are
# on the migration path; otherwise the default bundle (core mode) is correct. Gemfile.private is tracked,
# so its presence alone proves nothing. Private extensions without an installed private bundle abort.
# shellcheck source=lib/test-pg.sh
. "$REPO/scripts/lib/test-pg.sh"
BUNDLE_MODE="$(test_pg_bundle_mode "$REPO")" \
  || { echo "error: [prepare-extension-test-db] refusing to guess the bundle (see above)" >&2; exit 1; }
if [ "$BUNDLE_MODE" = private ]; then
  export BUNDLE_GEMFILE="$SERVER/Gemfile.private"
fi

# Collect private-extension migration versions (the leading numeric stamp of each migration file).
PRIVATE_VERSIONS=()
if [ -d "$REPO/extensions/private" ]; then
  while IFS= read -r f; do
    base="$(basename "$f")"
    PRIVATE_VERSIONS+=("${base%%_*}")
  done < <(find "$REPO/extensions/private" -path '*/server/db/migrate/*.rb' 2>/dev/null | sort)
fi

# Warn on version collisions ACROSS private extensions: schema_migrations is keyed by version, so
# if two extensions share a migration version only ONE of them can ever run — the other is silently
# treated as already-applied and its tables are never created (in test OR production). Surface it
# loudly rather than producing a partial DB that looks complete.
if [ "${#PRIVATE_VERSIONS[@]}" -gt 0 ]; then
  DUPES="$(printf '%s\n' "${PRIVATE_VERSIONS[@]}" | sort | uniq -d || true)"
  if [ -n "$DUPES" ]; then
    echo "[prepare-extension-test-db] WARNING: private-extension migration version collision(s):" >&2
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      echo "  version $v is used by:" >&2
      find "$REPO/extensions/private" -path "*/server/db/migrate/${v}_*.rb" 2>/dev/null | sed "s|$REPO/|    |" >&2
    done <<< "$DUPES"
    echo "  Only one migration per version will run; the rest are skipped (tables NOT created)." >&2
    echo "  Re-timestamp the colliding migration(s) to unique versions to fix." >&2
  fi
fi

# Which cluster? RAILS is the source of truth: ask it for the database name and port it will actually use
# (database.yml + dotenv incl. server/.env.test.local), and abort if a DATABASE_PORT declared in the
# environment/dotenv disagrees. The bare psql/createdb/dropdb below are then pointed at that same cluster:
# the shared one by default, or the optional tmpfs cluster (scripts/test-pg-tmpfs.sh) when Rails' port is
# that cluster's live socket in TEST_PG_DIR. Any other port aborts rather than let the bare client hit the
# wrong cluster (the golden refresh drops/re-labels databases, so a mismatch would hit the shared one).
TEST_PG_DIR="${TEST_PG_DIR:-$TEST_PG_DEFAULT_DIR}"
RAILS_INFO="$(cd "$SERVER" && bin/rails runner 'c = ActiveRecord::Base.connection_db_config; print "\nPNTESTDB\t#{c.database}\t#{c.configuration_hash[:port]}\n"' 2>/dev/null | sed -n 's/^PNTESTDB\t//p' | tail -1 || true)"
TARGET_DB="" RAILS_PORT=""
if [[ "$RAILS_INFO" == *$'\t'* ]]; then TARGET_DB="${RAILS_INFO%%$'\t'*}"; RAILS_PORT="${RAILS_INFO#*$'\t'}"; fi   # one tagged line; stray runner stdout is ignored
ENV_PORT="${DATABASE_PORT:-}"
[ -n "$ENV_PORT" ] || ENV_PORT="$(test_pg_dotenv_port "$SERVER/.env.test.local")"
CLUSTER="$(test_pg_resolve_cluster "$ENV_PORT" "$RAILS_PORT" "$TEST_PG_DIR")" \
  || { echo "error: [prepare-extension-test-db] refusing to run against an ambiguous cluster (see above)" >&2; exit 1; }
GLOBAL_IO_LOCK_FILE="${TMPDIR:-/tmp}/prepare-extension-test-db.GLOBAL-db-io.lock"
if [ "$CLUSTER" = tmpfs ]; then
  # PGUSER matters: the bare client would otherwise connect as the OS user and own the golden DB and its
  # clones, so a later db:drop by the app role (powernode) would fail "must be owner".
  export PGPORT="$RAILS_PORT" PGHOST="$TEST_PG_DIR" PGUSER="${DATABASE_USER:-powernode}"
  # Own I/O lock per cluster: tmpfs preps still serialise the non-atomic golden drop/create/COMMENT among
  # themselves, but never queue behind (or race with) the shared 5432 cluster's preps.
  GLOBAL_IO_LOCK_FILE="${TMPDIR:-/tmp}/prepare-extension-test-db.GLOBAL-db-io.${RAILS_PORT}.lock"
  echo "[prepare-extension-test-db] tmpfs test cluster: port $PGPORT, socket $PGHOST"
fi
exec 8>"$GLOBAL_IO_LOCK_FILE"

cd "$SERVER"

if [ "${#PRIVATE_VERSIONS[@]}" -eq 0 ]; then
  # Core mode: load the schema WITHOUT seeding. `db:prepare` runs `db:seed`,
  # and the seed path fails on a fresh core+baseline test DB (RecordInvalid /
  # "Value can't be blank"; agent + skill-binding seeds require a demo admin
  # account that the test DB doesn't have). RSpec builds its own state via
  # factories and needs no seed data, so mirror the private-extension path
  # below: drop → create → schema:load only. (imp 605b follow-on / BUG-I)
  echo "[prepare-extension-test-db] core mode (no private extensions) → schema-load only (no seed)"
  db_io_lock
  bin/rails db:drop db:create db:schema:load
  db_io_unlock
  exit 0
fi

# ---------------------------------------------------------------------------------------------------
# Golden-template fast path (throughput). Building a private-ext test DB from scratch
# (drop/create/schema:load + un-assume + migrate) is the slow, fsync-heavy work that serializes
# badly across worktrees under the global I/O lock. Instead, build ONE canonical "golden" DB with
# the full schema, then each worktree's DB is a cheap `CREATE DATABASE ... TEMPLATE` clone (a
# Postgres block-copy — seconds, not minutes). The golden is rebuilt only when the schema SHAPE
# changes (fingerprint = core schema.rb + sorted private migration versions). Fallback to the full
# build is automatic on any template error; force it with TEST_DB_NO_TEMPLATE=1.
GOLDEN_DB="powernode_test_golden"
# TARGET_DB (authoritative, from Rails config) was resolved above together with the cluster.
FINGERPRINT="fp:$( { cat "$REPO/server/db/schema.rb"; printf '%s\n' "${PRIVATE_VERSIONS[@]}" | sort; } | sha1sum | cut -d' ' -f1)"
# Read the fingerprint comment off the golden DB without connecting to it (empty if golden absent).
golden_fp() { psql -tAX -d postgres -c "SELECT shobj_description(oid,'pg_database') FROM pg_database WHERE datname='${GOLDEN_DB}'" 2>/dev/null | tr -d '[:space:]'; }
# SAFETY: the raw dropdb/createdb below bypass Rails' built-in test-env protection, so the golden
# path is HARD-GATED to names starting with `powernode_test` — it can never drop/clone the live
# development or production database even if RAILS_ENV or the resolved name were somehow wrong.
template_ok() { [ -z "${TEST_DB_NO_TEMPLATE:-}" ] && [ -n "$TARGET_DB" ] && [ "$TARGET_DB" != "$GOLDEN_DB" ] && [[ "$TARGET_DB" == powernode_test* ]]; }
clone_from_golden() { # drop TARGET_DB and recreate it as a template clone of golden; nonzero on failure
  db_io_lock
  psql -qX -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${TARGET_DB}' AND pid<>pg_backend_pid()" >/dev/null 2>&1 || true
  dropdb --if-exists "$TARGET_DB" >/dev/null 2>&1
  local rc=0; createdb "$TARGET_DB" --template="$GOLDEN_DB" >/dev/null 2>&1 || rc=$?
  db_io_unlock
  return $rc
}

if template_ok && [ "$(golden_fp)" = "$FINGERPRINT" ]; then
  echo "[prepare-extension-test-db] golden template is fresh → cloning ${TARGET_DB} (fast path)…"
  if clone_from_golden; then
    echo "[prepare-extension-test-db] done — ${TARGET_DB} cloned from ${GOLDEN_DB} (private tables included)."
    exit 0
  fi
  echo "[prepare-extension-test-db] WARNING: template clone failed — falling back to the full build." >&2
fi

echo "[prepare-extension-test-db] (re)creating TEST database and loading core schema…"
db_io_lock
bin/rails db:drop db:create db:schema:load
db_io_unlock

echo "[prepare-extension-test-db] un-assuming ${#PRIVATE_VERSIONS[@]} private migration version(s) so they run for real…"
# Delete via the app connection so the right (test) database and credentials are used. Versions
# are passed through the environment (not ARGV) and the body avoids a top-level `next` ("Can't
# escape from eval with next" under `rails runner`); `abort` exits non-zero so a failed un-assume
# can't be silently swallowed and leave the private migrations still assume-migrated.
PRIVATE_VERSIONS_CSV="$(IFS=,; echo "${PRIVATE_VERSIONS[*]}")"
export PRIVATE_VERSIONS_CSV
bin/rails runner "$(cat <<'RUBY'
versions = ENV.fetch("PRIVATE_VERSIONS_CSV", "").split(",").reject(&:empty?)
abort("[prepare-extension-test-db] no private migration versions to un-assume") if versions.empty?
sql = ActiveRecord::Base.sanitize_sql_array(["DELETE FROM schema_migrations WHERE version IN (?)", versions])
deleted = ActiveRecord::Base.connection.exec_delete(sql)
STDERR.puts "[prepare-extension-test-db] removed #{deleted} assume-migrated private version(s) from schema_migrations"
RUBY
)"

echo "[prepare-extension-test-db] running private engine migrations…"
# The tracked server/db/schema.rb is never written here. The post-migrate auto-dump is disabled
# everywhere (config/initializers/schema_dump_isolation.rb), and SCHEMA= points any dump that does
# happen at a throwaway sink. Nothing restores the tracked file afterwards: a `git checkout` of it
# discarded whatever UNCOMMITTED schema.rb edits the checkout held — in a shared checkout, another
# session's in-flight migration work (IMP-01a08cc5; guarded by
# scripts/checks/tests/prepare_extension_test_db_schema_safety_test.sh).
SCHEMA_DUMP_SINK="$(mktemp "${TMPDIR:-/tmp}/prepare-extension-test-db-schema.XXXXXX.rb")"
db_io_lock
SCHEMA="$SCHEMA_DUMP_SINK" bin/rails db:migrate
db_io_unlock
rm -f "$SCHEMA_DUMP_SINK"

# Seed/refresh the golden template from the freshly-built target so the NEXT worktree clones instead
# of rebuilding. Re-check freshness first: if another worktree already rebuilt golden while we
# waited, don't redo it. Non-fatal — a failure here only means the next prep does a full build too.
if template_ok && [ "$(golden_fp)" != "$FINGERPRINT" ]; then
  echo "[prepare-extension-test-db] refreshing golden template ${GOLDEN_DB} from ${TARGET_DB}…"
  db_io_lock
  psql -qX -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${TARGET_DB}' AND pid<>pg_backend_pid()" >/dev/null 2>&1 || true
  dropdb --if-exists "$GOLDEN_DB" >/dev/null 2>&1
  if createdb "$GOLDEN_DB" --template="$TARGET_DB" >/dev/null 2>&1; then
    psql -qX -d postgres -c "COMMENT ON DATABASE ${GOLDEN_DB} IS '${FINGERPRINT}'" >/dev/null 2>&1 \
      && echo "[prepare-extension-test-db] golden template refreshed (fingerprint ${FINGERPRINT#fp:})."
  else
    echo "[prepare-extension-test-db] note: could not refresh golden template (non-fatal)." >&2
  fi
  db_io_unlock
fi

echo "[prepare-extension-test-db] done — test DB now includes private-extension tables."
