#!/bin/bash
# check-extension-bundle-migrations.sh — verify a private extension's migrations
# are actually APPLIED to the test database, not just that its bundle loads.
#
# IMP-d4583399ba5c background: scripts/validate.sh already detects a MISSING
# server/Gemfile.private (public checkout: the extension is entirely absent,
# specs never even attempt to load) and skips cleanly. That is not the only
# way private extension specs go bad. On a maintainer checkout where
# Gemfile.private IS present, the bundle loads fine — Gemfile.private itself
# sets POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1, so extensions_loader_helper.rb
# picks up the extension and its models/constants resolve — but that says
# nothing about whether the TEST DATABASE actually has the extension's
# tables. `db:schema:load` / `db:prepare` load the core-only schema.rb and
# then mark every migration version <= the schema version as already-applied
# via assume_migrated_upto_version, WITHOUT running the private engine's own
# migrations (full mechanism: scripts/prepare-extension-test-db.sh header).
# The result is a bundle that loads cleanly against a database missing every
# business_*/trading_* table, so specs explode with hundreds of
# PG::UndefinedTable failures the instant they touch one — a wall
# indistinguishable, to anyone skimming validate.sh output, from real
# regressions.
#
# rails_helper.rb's own schema-staleness guard
# (ActiveRecord::Migration.check_all_pending!) does NOT catch this: verified
# empirically that ActiveRecord::Migrator.migrations_paths stays pinned to
# ["db/migrate"] and never absorbs the engine's own
# `app.config.paths["db/migrate"] << ...` addition, even though
# Rails.application.config.paths["db/migrate"] itself lists every extension's
# migrate dir correctly. That's a separate, pre-existing Rails-wiring gap —
# out of scope for this check, which instead asks the question directly
# instead of relying on that guard: does schema_migrations contain every
# migration version this extension's own db/migrate ships?
#
# Usage: check-extension-bundle-migrations.sh <ext_migrate_dir>
#   Prints "OK" and exits 0            — every migration version in
#                                         <ext_migrate_dir> is recorded in
#                                         schema_migrations (safe to run specs),
#                                         or the dir doesn't exist / ships no
#                                         migrations (nothing to check).
#   Prints "STALE:<missing>/<total>" and exits 1
#                                       — some migration versions are missing;
#                                         running specs now reproduces the
#                                         851-failure wall. Remediate with
#                                         `bash scripts/prepare-extension-test-db.sh`.
#
# Test seam: CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=ok|stale bypasses the real
# bundle/DB round-trip (see scripts/checks/tests/extension_bundle_migrations_check_test.sh).

set -eo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ext_migrate_dir="${1:-}"

if [[ -n "${CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST:-}" ]]; then
  case "$CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST" in
    ok)
      echo "OK"
      exit 0
      ;;
    stale)
      echo "STALE:2/5"
      exit 1
      ;;
    *)
      echo "unknown CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST value: $CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST" >&2
      exit 2
      ;;
  esac
fi

if [[ -z "$ext_migrate_dir" || ! -d "$ext_migrate_dir" ]]; then
  echo "OK"
  exit 0
fi

if [[ -z "$(find "$ext_migrate_dir" -name '*.rb' -print -quit 2>/dev/null)" ]]; then
  echo "OK"
  exit 0
fi

# Resolve to an absolute path FIRST: the ruby below runs with CWD set to
# server/ (so bundler picks up the right Gemfile), and a caller-relative
# path resolved against that CWD instead of the caller's would silently glob
# zero files — read as "no migrations to check" i.e. a false OK, exactly the
# silent-pass failure mode this check exists to prevent.
ext_migrate_dir="$(cd "$ext_migrate_dir" && pwd)"

# Read-only: lists this extension's own migration versions and checks them
# against schema_migrations. Never mutates the database.
#
# `|| true` is load-bearing under this script's own `set -eo pipefail`: if
# `bundle exec rails runner` genuinely crashes (bundler failure, DB error)
# rather than cleanly printing OK/STALE, the assignment would otherwise abort
# the script right here — before the "${result:-STALE:unknown}" fallback below
# ever runs — leaving it silent instead of fail-closed.
result="$(cd "$PROJECT_ROOT/server" && BUNDLE_GEMFILE="$PROJECT_ROOT/server/Gemfile.private" RAILS_ENV=test \
  bundle exec rails runner '
    versions = Dir[ARGV[0] + "/*.rb"].filter_map { |f| File.basename(f)[/\A(\d+)_/, 1] }
    applied = ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations")
    missing = versions - applied
    puts missing.empty? ? "OK" : "STALE:#{missing.size}/#{versions.size}"
  ' "$ext_migrate_dir" 2>/dev/null | tail -1 || true)"

result="${result:-STALE:unknown}"
echo "$result"
[[ "$result" == "OK" ]]
