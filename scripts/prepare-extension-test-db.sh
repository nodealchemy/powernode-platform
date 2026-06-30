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
#   4. restore the core-only schema.rb (db:migrate re-dumps it in full/private mode; that full dump
#      must NEVER be kept or committed — see CLAUDE.md "full-mode schema.rb leak").
#
# Private extensions are discovered dynamically from extensions/private/* — NONE is named here
# (public-safe). In core mode (no private extensions present) this degrades to a plain core
# `db:prepare`. Operates on the TEST database ONLY (RAILS_ENV=test); never touches dev/prod.
#
# Usage:
#   scripts/prepare-extension-test-db.sh                 # prepare the test DB for THIS checkout/worktree
#   (the isolated TEST_ENV_NUMBER is read from server/.env.test.local automatically in the test env)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$REPO/server"
[ -d "$SERVER" ] || { echo "error: $SERVER not found" >&2; exit 1; }

export RAILS_ENV=test

# Use the private bundle when present so the engine migrations are on the migration path; otherwise
# the default bundle (core mode) is correct.
if [ -f "$SERVER/Gemfile.private" ]; then
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

cd "$SERVER"

if [ "${#PRIVATE_VERSIONS[@]}" -eq 0 ]; then
  echo "[prepare-extension-test-db] core mode (no private extensions) → plain db:prepare"
  bin/rails db:prepare
  exit 0
fi

echo "[prepare-extension-test-db] (re)creating TEST database and loading core schema…"
bin/rails db:drop db:create db:schema:load

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
bin/rails db:migrate

# db:migrate just re-dumped schema.rb in FULL (private) mode. Restore the committed core-only file —
# that full dump must never be kept or committed.
if git -C "$REPO" ls-files --error-unmatch server/db/schema.rb >/dev/null 2>&1; then
  git -C "$REPO" checkout -- server/db/schema.rb && \
    echo "[prepare-extension-test-db] restored core-only server/db/schema.rb (discarded full-mode dump)"
fi

echo "[prepare-extension-test-db] done — test DB now includes private-extension tables."
