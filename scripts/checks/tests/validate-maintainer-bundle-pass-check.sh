#!/bin/bash
# Red/green test for IMP-0bf0d8873023: scripts/validate.sh must exercise BOTH
# shipped extension configurations, not just the public one.
#
# NAMING, deliberately: this file is about the server/Gemfile.private second
# pass, but it must NOT have "private" in its own name — .gitignore:69 is a
# bare `*private*` security rule, so a file called
# validate-private-bundle-pass-check.sh is silently untracked and this test
# would never reach the repo. (server/Gemfile.private only survives because
# .gitignore:394 un-ignores it explicitly.) Verified with `git check-ignore -v`.
#
# The defect: validate.sh selects server/Gemfile.private only for spec dirs
# matching extensions/private/* (the `case` at ~:142). Every PUBLIC extension
# (system, marketing, supply-chain) is therefore run with an EXPLICIT
# BUNDLE_GEMFILE=$PROJECT_ROOT/server/Gemfile — which also overrides any
# inherited BUNDLE_GEMFILE — so POWERNODE_INCLUDE_PRIVATE_EXTENSIONS is never
# set and no private extension is on the load path. That is CORRECT for a
# public clone, which has no extensions/private/* at all. It is incomplete for
# a maintainer/production checkout, where a private extension's guards,
# decorators and registered providers load in front of public-extension code:
# that second configuration had NO gate coverage whatsoever. Existence proof:
# extensions/system's provisioning_service_spec.rb was 68 examples / 0 failures
# under the public bundle and 68 / 47 under the private one (IMP-4344d65ddf56),
# and the 47 included the RCP INV-2/INV-6 boot-path and storage-locality
# invariants.
#
# The fix is ADDITIVE: pass 1 is untouched, and a second pass re-runs the
# public extensions that pass 1 actually ran, under the private bundle, only
# when private extensions are present on disk. A public clone never takes it.
#
# The property that matters most is the LAST one asserted below: a divergence
# must FAIL the gate. A second pass whose failures are advisory reproduces
# exactly the invisibility it exists to remove.
#
# This test drives the REAL scripts/validate.sh (not a reimplementation) via
# test seams, so it stays fast and touches neither the shared test DB nor a
# real spec run (memory: "TARGETED specs only, never the full suite ... nor
# bare validate.sh"):
#   - VALIDATE_SELFTEST_SKIP_RSPEC=1 (pre-existing) stubs both passes'
#     `bundle exec rspec` invocations as SUCCESS while leaving every decision
#     and reporting branch around them real.
#   - VALIDATE_SELFTEST_PRIVATE_PASS_FAIL=1 (added with the fix) makes the
#     stubbed SECOND pass report failure instead — the divergence case.
#   - VALIDATE_SELFTEST_PRIVATE_EXT_ROOT=<dir> (added with the fix) points the
#     "are private extensions present?" probe at another directory, so the
#     public-clone shape can be exercised on a maintainer checkout without
#     moving anything on disk.
#
# Usage: bash scripts/checks/tests/validate-maintainer-bundle-pass-check.sh
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

if [[ ! -f server/Gemfile.private ]] || ! compgen -G "extensions/private/*/server" >/dev/null; then
  echo "SKIP: not a maintainer checkout (no server/Gemfile.private, or no extensions/private/*/server) — the second pass does not apply here, which is itself the intended public-clone behavior"
  exit 0
fi

# Common invocation: specs phase only. --skip-ts/--skip-patterns/--skip-secrets
# keep the run to the phase under test; VALIDATE_SELFTEST_SKIP_RSPEC keeps it
# off the shared test DB.
run_validate() {
  env "$@" VALIDATE_SELFTEST_SKIP_RSPEC=1 \
    bash scripts/validate.sh --skip-ts --skip-patterns --skip-secrets 2>&1
}

echo "=== validate.sh: public-extension specs must ALSO run under the private bundle ==="

# 1. Maintainer checkout, everything green. The second pass must actually
#    happen and must be visible: an extension whose specs ran in pass 1 has to
#    reappear in pass 2. This is the discriminating assertion — on the unfixed
#    script there is no second pass at all.
out_both="$(run_validate CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=ok)"
exit_both=$?
echo "$out_both" | sed 's/^/  /'
assert_exit "both passes green: exit is 0" 0 "$exit_both"
assert_contains "green run: system specs run a SECOND time under the private bundle" \
  "extensions/system specs (private bundle)" "$out_both"
assert_contains "green run: marketing too — the pass covers every public extension pass 1 ran" \
  "extensions/marketing specs (private bundle)" "$out_both"
# supply-chain is opted out of the spec phase entirely (scripts/rspec-check-optouts.txt).
# The second pass must inherit that decision rather than re-deriving the list:
# an opt-out honored in one pass and ignored in the other is not an opt-out.
assert_not_contains "green run: an opted-out extension is NOT resurrected by the second pass" \
  "extensions/supply-chain specs (private bundle)" "$out_both"
assert_contains "green run: still reports overall PASS when both configurations agree" \
  "All checks passed" "$out_both"
# Without this, the pass could be running the PUBLIC bundle twice and every
# assertion above would still be green — a second pass that is not a second
# configuration is pure cost.
#
# The needle is the WHOLE invocation, and validate.sh builds it once into an
# array that both the stubbed and the real branch consume. An earlier version
# had the stub echo a look-alike string assembled separately: mutating only the
# real branch's BUNDLE_GEMFILE to the public Gemfile left this assertion green,
# so it was matching a parallel string rather than observing the command.
#
# The env pin is asserted too: Gemfile.private sets the flag with `||=`, so an
# inherited POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 would survive bundle
# selection and load no private extensions at all (verified in ruby).
assert_contains "green run: the second pass really selects Gemfile.private AND pins the flag" \
  "env POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1 BUNDLE_GEMFILE=$PWD/server/Gemfile.private bundle exec rspec $PWD/extensions/system/server/spec --format progress" \
  "$out_both"

echo ""

# 2. THE POINT OF THE WHOLE EXERCISE: a suite that is green under the public
#    bundle and red under the private one must FAIL the gate — exit nonzero,
#    no "All checks passed", and a summary line naming which configuration
#    diverged. Reporting it while still exiting 0 would reproduce the
#    invisibility this feature exists to remove.
out_diverge="$(run_validate CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=ok VALIDATE_SELFTEST_PRIVATE_PASS_FAIL=1)"
exit_diverge=$?
echo "$out_diverge" | sed 's/^/  /'
assert_exit "divergence: exit is nonzero" 1 "$exit_diverge"
assert_not_contains "divergence: does NOT claim 'All checks passed'" "All checks passed" "$out_diverge"
assert_contains "divergence: summary names the FAIL explicitly" "FAIL" "$out_diverge"
# One contiguous needle on purpose. Asserted separately, "extensions/system"
# would pass vacuously — pass 1 prints that name on every run — so the
# extension name and the configuration have to be required in the same string
# for the assertion to have any discriminating power.
assert_contains "divergence: summary names the extension AND which configuration failed" \
  "extensions/system specs FAILED under the private bundle" "$out_diverge"

echo ""

# 2b. The second pass loads EVERY private extension on disk, so it inherits the
#     same precondition the private-extension branch of pass 1 has: a bundle
#     whose migrations are not in the test DB produces a wall of
#     PG::UndefinedTable failures indistinguishable from a real regression.
#     Like IMP-93291dfa635f that is a FAIL, not a SKIP — letting it pass would
#     hand back a green gate covering strictly less. The needle is specific to
#     pass 2: a stale bundle also fails pass 1, and asserting a shared string
#     would pass on pass 1's note alone.
out_stale="$(run_validate CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=stale)"
exit_stale=$?
echo "$out_stale" | sed 's/^/  /'
assert_exit "stale private bundle: exit is nonzero" 1 "$exit_stale"
assert_contains "stale private bundle: the SECOND pass reports it did not run, in its own words" \
  "private-bundle second pass NOT RUN" "$out_stale"
assert_not_contains "stale private bundle: no second pass is attempted anyway" \
  "(private bundle)" "$out_stale"

echo ""

# 3. Public-clone shape: no extensions/private/* on disk. The second pass must
#    not run at all and must not perturb the verdict — the public
#    configuration is the correct and only one there.
#
#    CONTROL, not a discriminating assertion: it is also green on the unfixed
#    script, which never runs a second pass under any conditions. It is here
#    to catch a fix that breaks the public clone, which the operator direction
#    calls out as the failure mode to avoid.
empty_root="$(mktemp -d)"
trap 'rm -rf "$empty_root"' EXIT
out_public="$(run_validate CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=ok "VALIDATE_SELFTEST_PRIVATE_EXT_ROOT=$empty_root")"
exit_public=$?
echo "$out_public" | sed 's/^/  /'
assert_exit "public clone: exit is 0" 0 "$exit_public"
assert_contains "public clone: reports overall PASS" "All checks passed" "$out_public"
assert_not_contains "public clone: no second pass is attempted" "(private bundle)" "$out_public"

assert_not_contains "public clone: and no skip note either — nothing was skipped" \
  "private-bundle second pass SKIPPED" "$out_public"

# 3b. Public clone AND the skip flag. The two guards are ordered so that
#     "there are no private extensions" wins: a public clone has no second
#     configuration, so it must not be told it skipped coverage it never had.
#     Checking the flag first produced exactly that false warning.
out_public_skipflag="$(env CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=ok VALIDATE_SELFTEST_SKIP_RSPEC=1 \
  "VALIDATE_SELFTEST_PRIVATE_EXT_ROOT=$empty_root" \
  bash scripts/validate.sh --skip-ts --skip-patterns --skip-secrets --skip-private-bundle-pass 2>&1)"
exit_public_skipflag=$?
assert_exit "public clone + --skip-private-bundle-pass: exit is 0" 0 "$exit_public_skipflag"
assert_not_contains "public clone + --skip-private-bundle-pass: no false coverage warning" \
  "private-bundle second pass SKIPPED" "$out_public_skipflag"

echo ""

# 4. Cost escape hatch. The second pass doubles the public extension suites
#    (system alone is ~8000 examples), so there is a flag to defer it — and,
#    like every other skip in this script, it must be LABELLED in the summary.
#    A skip nobody sees in the final tally stops being a decision and reads as
#    an accidental pass (IMP-d4583399ba5c).
out_skipflag="$(env CHECK_EXT_BUNDLE_MIGRATIONS_SELFTEST=ok VALIDATE_SELFTEST_SKIP_RSPEC=1 \
  bash scripts/validate.sh --skip-ts --skip-patterns --skip-secrets --skip-private-bundle-pass 2>&1)"
exit_skipflag=$?
echo "$out_skipflag" | sed 's/^/  /'
assert_exit "--skip-private-bundle-pass: exit is 0 (explicit consent honored)" 0 "$exit_skipflag"
assert_not_contains "--skip-private-bundle-pass: second pass really is skipped" \
  "(private bundle)" "$out_skipflag"
# Needle chosen to appear ONLY in the summary note, never in the inline echo:
# asserting the shared prefix "private-bundle second pass SKIPPED" was vacuous
# — the inline progress line carries it too, so a mutant that dropped the
# summary entry entirely still passed.
assert_contains "--skip-private-bundle-pass: summary LABELS the skip" \
  "public extensions were tested in the public configuration ONLY" "$out_skipflag"

echo ""
if [[ $fail -eq 0 ]]; then
  echo "ALL ASSERTIONS PASSED"
else
  echo "ASSERTIONS FAILED"
fi
exit $fail
