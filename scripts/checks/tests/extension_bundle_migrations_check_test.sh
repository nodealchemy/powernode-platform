#!/bin/bash
# Red/green test for scripts/check-extension-bundle-migrations.sh — the precondition
# check that gates whether validate.sh may run a private extension's specs.
#
# IMP-d4583399ba5c: a full `scripts/validate.sh` run reported 851 failing
# business-extension examples cascading from one load error. The FILED root
# cause ("private extensions are excluded from the bundle unless
# POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1") turned out to be stale for this
# checkout on re-verification: server/Gemfile.private auto-sets that env var
# and the business extension's models/constants resolve fine under it. The
# REAL cause, confirmed empirically against this checkout's live test DB
# (extensions/private/business/server/spec/db/seeds/compliance_seed_spec.rb
# run under BUNDLE_GEMFILE=Gemfile.private): every business_* table is
# missing — `PG::UndefinedTable: relation "business_compliance_jurisdictions"
# does not exist` — because db:schema:load only loads the CORE-ONLY
# schema.rb and marks every migration version <= the schema version as
# already-applied via assume_migrated_upto_version, WITHOUT running the
# private engine's own migrations (see scripts/prepare-extension-test-db.sh's
# header for the full mechanism). rails_helper.rb's own
# `ActiveRecord::Migration.check_all_pending!` guard does NOT catch this
# either — verified separately that `ActiveRecord::Migrator.migrations_paths`
# stays pinned to `["db/migrate"]` and never picks up the engine's own
# `app.config.paths["db/migrate"] << ...` addition (a distinct, pre-existing
# Rails-wiring gap, out of scope here). So a maintainer whose bundle loads
# cleanly still gets the 851-failure wall with no warning.
#
# scripts/check-extension-bundle-migrations.sh asks the question directly: does
# schema_migrations actually contain every migration version this extension
# ships, rather than trusting that the bundle loading means the schema is
# current. This test exercises it both via its SELFTEST seam (deterministic,
# no DB/bundle needed) and — for the STALE branch — for REAL against this
# checkout's actual business extension migrate dir, which is genuinely
# unmigrated right now (confirmed above), so that branch is exercised
# end-to-end, not just simulated.
#
# The OK/present branch is exercised only via the SELFTEST seam here:
# reaching it for real would mean running scripts/prepare-extension-test-db.sh,
# which drops and rebuilds the test database — unsafe against the Postgres
# test DB this session shares with other concurrent dev-loop agents.
#
# Usage: bash scripts/checks/tests/extension_bundle_migrations_check_test.sh
# Exits 0 if all assertions pass, 1 otherwise.

set -u

cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1

CHECK="scripts/check-extension-bundle-migrations.sh"
fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $desc ($actual)"
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    fail=1
  fi
}

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    echo "PASS: $desc (exit $actual)"
  else
    echo "FAIL: $desc (expected exit $expected, got $actual)"
    fail=1
  fi
}

echo "=== check-extension-bundle-migrations.sh precondition check ==="

# 1. SELFTEST seam: OK branch is deterministic and DB-free (green precondition;
#    the "present and migrated" case we cannot safely reach for real here).
out_ok="$(CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=ok bash "$CHECK" /nonexistent 2>&1)"
exit_ok=$?
assert_eq "SELFTEST ok prints OK" "OK" "$out_ok"
assert_exit "SELFTEST ok exits 0" 0 "$exit_ok"

# 2. SELFTEST seam: STALE branch is deterministic and DB-free.
out_stale="$(CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=stale bash "$CHECK" /nonexistent 2>&1)"
exit_stale=$?
assert_eq "SELFTEST stale prints STALE:*" "STALE:2/5" "$out_stale"
assert_exit "SELFTEST stale exits 1" 1 "$exit_stale"

# 3. No migrate dir at all (extension ships no migrations, e.g. a docs-only
#    private extension) — must never block on something that doesn't exist.
out_nodir="$(bash "$CHECK" /this/path/does/not/exist 2>&1)"
exit_nodir=$?
assert_eq "missing migrate dir is OK (nothing to check)" "OK" "$out_nodir"
assert_exit "missing migrate dir exits 0" 0 "$exit_nodir"

# 4. Empty migrate dir (dir exists, ships zero *.rb migrations) — also OK.
empty_dir="$(mktemp -d)"
out_empty="$(bash "$CHECK" "$empty_dir" 2>&1)"
exit_empty=$?
assert_eq "empty migrate dir is OK (nothing to check)" "OK" "$out_empty"
assert_exit "empty migrate dir exits 0" 0 "$exit_empty"
rmdir "$empty_dir"

# 5. REAL invocation against this checkout's actual business extension migrate
#    dir. Requires server/Gemfile.private (maintainer checkout); skip cleanly
#    on a public clone where extensions/private/* doesn't exist at all.
BIZ_MIGRATE_DIR="extensions/private/business/server/db/migrate"
if [[ -f "server/Gemfile.private" && -d "$BIZ_MIGRATE_DIR" ]]; then
  out_real="$(bash "$CHECK" "$BIZ_MIGRATE_DIR" 2>&1)"
  exit_real=$?
  echo "  (real check output: $out_real, exit $exit_real)"
  if [[ "$out_real" == STALE:* && "$exit_real" -eq 1 ]]; then
    echo "PASS: real business-extension check reports STALE (test DB not prepared via prepare-extension-test-db.sh — matches the finding this task fixes)"
  else
    echo "FAIL: real business-extension check expected STALE:n/m + exit 1, got '$out_real' exit $exit_real"
    fail=1
  fi
else
  echo "SKIP: no server/Gemfile.private / no $BIZ_MIGRATE_DIR — not a maintainer checkout, nothing to verify for real"
fi

echo ""
if [[ $fail -eq 0 ]]; then
  echo "ALL ASSERTIONS PASSED"
else
  echo "ASSERTIONS FAILED"
fi
exit $fail
