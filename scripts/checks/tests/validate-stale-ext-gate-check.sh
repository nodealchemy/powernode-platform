#!/bin/bash
# Red/green test for IMP-93291dfa635f: scripts/validate.sh must not report an
# unqualified PASS when it skipped a private extension's spec suite because
# its migration bundle reads STALE.
#
# Bug: adding a migration to a private extension without applying it to
# powernode_test made scripts/check-extension-bundle-migrations.sh report
# STALE. validate.sh's extension loop reacted by SKIPping that extension's
# specs — correctly — but never marked SPECS_OK false or set OVERALL_EXIT for
# it. The summary printed "PASS Backend specs" next to the SKIP note, and the
# final line read "All checks passed — safe to push." A gate that cannot
# distinguish "did not run" from "passed" is worse than no gate: its PASS is
# read as evidence, and the trigger (adding a migration) is the single most
# routine action there is.
#
# Investigation established the skip itself is legitimate (a stale bundle
# really can't run its specs safely — see scripts/check-extension-bundle-
# migrations.sh's header), but that state is INCIDENTAL, not a structural
# limitation like a missing Gemfile.private on a public checkout: it happens
# whenever anyone adds a routine migration and forgets to re-run
# prepare-extension-test-db.sh, and it's trivially fixable. So the fix makes
# it a hard gate failure (FAIL + nonzero exit), not just a differently-labeled
# skip — per the operator direction, do NOT relax the migration check itself
# to tolerate new migrations; that would remove a real signal.
#
# This test drives the REAL scripts/validate.sh (not a reimplementation) via
# two existing test seams so it stays fast and touches neither the shared
# test DB nor a full backend-spec run (memory: "TARGETED specs only, never
# the full suite ... nor bare validate.sh"):
#   - CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=stale|ok forces
#     check-extension-bundle-migrations.sh's real answer deterministically
#     (pre-existing seam, also used by extension_bundle_migrations_check_test.sh).
#   - VALIDATE_SELFTEST_SKIP_RSPEC=1 (added by this fix) skips the real
#     `bundle exec rspec` invocations while leaving every branch of the
#     reporting/exit-code logic this test asserts on fully real.
#
# Usage: bash scripts/checks/tests/validate-stale-ext-gate-check.sh
# Exits 0 if all assertions pass, 1 otherwise.

set -u

cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1

fail=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    echo "PASS: $desc (exit $actual)"
  else
    echo "FAIL: $desc (expected exit $expected, got $actual)"
    fail=1
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (did not find: $needle)"
    fail=1
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (unexpectedly found: $needle)"
    fail=1
  fi
}

if [[ ! -f server/Gemfile.private || ! -d extensions/private/business/server/spec ]]; then
  echo "SKIP: no server/Gemfile.private / no extensions/private/business — not a maintainer checkout, nothing to verify for real"
  exit 0
fi

echo "=== validate.sh: stale private-extension bundle must hard-fail, not silently PASS ==="

# 1. Deliberately-STALE bundle: the defect's exact repro. Both the exit
#    status AND the summary text must make the skip visible — asserting only
#    one reproduces the bug one level up (a log line next to a PASS headline).
out_stale="$(CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=stale VALIDATE_SELFTEST_SKIP_RSPEC=1 \
  bash scripts/validate.sh --skip-ts --skip-patterns --skip-secrets 2>&1)"
exit_stale=$?
echo "$out_stale" | sed 's/^/  /'
assert_exit "STALE bundle: exit is nonzero" 1 "$exit_stale"
assert_not_contains "STALE bundle: summary does NOT claim 'All checks passed'" "All checks passed" "$out_stale"
assert_contains "STALE bundle: summary names the FAIL explicitly" "FAIL" "$out_stale"
assert_contains "STALE bundle: summary says specs were NOT RUN and why" "specs NOT RUN" "$out_stale"
assert_contains "STALE bundle: summary names the remediation" "prepare-extension-test-db.sh" "$out_stale"

echo ""

# 2. Control: a clean (non-stale) bundle must behave exactly as before this
#    fix — PASS, exit 0. A fix for the STALE path that also breaks the happy
#    path would just trade one false signal for another.
out_ok="$(CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=ok VALIDATE_SELFTEST_SKIP_RSPEC=1 \
  bash scripts/validate.sh --skip-ts --skip-patterns --skip-secrets 2>&1)"
exit_ok=$?
echo "$out_ok" | sed 's/^/  /'
assert_exit "clean bundle: exit is 0 (no false positive introduced)" 0 "$exit_ok"
assert_contains "clean bundle: summary still reports PASS" "All checks passed" "$out_ok"
assert_not_contains "clean bundle: no NOT RUN note for a bundle that IS migrated" "specs NOT RUN" "$out_ok"

echo ""
if [[ $fail -eq 0 ]]; then
  echo "ALL ASSERTIONS PASSED"
else
  echo "ASSERTIONS FAILED"
fi
exit $fail
