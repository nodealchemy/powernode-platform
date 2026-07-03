#!/bin/bash
# Red/green test for scripts/pattern-validation.sh's exit-code policy.
#
# Bug: the script derived its exit code purely from compliance percentage
# (passed_checks / total_checks), ignoring failed_checks entirely. A single
# hard FAIL — even a security-critical one (cross-tenant IDOR, zero-authz
# controller, kill-switch compliance, private-schema/core-purity leak) —
# gets diluted across ~30 checks to ~92-97% compliance, which read as exit
# 0/1 (non-blocking). scripts/validate.sh then mapped exit 1 to a WARN that
# never sets OVERALL_EXIT.
#
# This test drives scripts/pattern-validation.sh via the PATTERN_VALIDATION_SELFTEST
# seam (fabricates counters/failure list, skips the real audit) so the exit-code
# policy can be exercised in isolation without needing to break real repo code
# to trigger a real check failure.
#
# Usage: bash scripts/checks/tests/pattern_validation_exit_test.sh
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

assert_exit_at_least() {
    local desc="$1" min="$2" actual="$3"
    if [[ "$actual" -ge "$min" ]]; then
        echo "PASS: $desc (exit $actual >= $min)"
    else
        echo "FAIL: $desc (expected exit >= $min, got $actual)"
        fail=1
    fi
}

echo "=== pattern-validation.sh exit-code policy ==="

# 1. A security-critical FAIL must hard-block with exit 2, regardless of how
#    many other checks pass (i.e. regardless of the diluted compliance rate).
PATTERN_VALIDATION_SELFTEST=security_critical_fail bash scripts/pattern-validation.sh >/tmp/pv_selftest_security.log 2>&1
sec_exit=$?
assert_exit "security-critical FAIL hard-blocks" 2 "$sec_exit"
if ! grep -q "SECURITY-CRITICAL CHECK(S) FAILED" /tmp/pv_selftest_security.log; then
    echo "FAIL: security-critical summary banner missing from output"
    fail=1
else
    echo "PASS: security-critical summary banner present"
fi

# 2. A single non-security FAIL must never be reported as exit 0 (the old bug:
#    compliance-based-only math let a lone FAIL pass silently at high compliance).
PATTERN_VALIDATION_SELFTEST=nonsecurity_fail bash scripts/pattern-validation.sh >/tmp/pv_selftest_nonsecurity.log 2>&1
nonsec_exit=$?
assert_exit_at_least "non-security FAIL is never exit 0" 1 "$nonsec_exit"

echo ""
if [[ $fail -eq 0 ]]; then
    echo "ALL ASSERTIONS PASSED"
else
    echo "ASSERTIONS FAILED"
fi
exit $fail
