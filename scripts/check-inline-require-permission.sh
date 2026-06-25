#!/bin/bash
#
# check-inline-require-permission.sh — inline-permission-check regression guard
# =============================================================================
# require_permission / require_any_permission / require_all_permissions now RAISE
# (Authentication::PermissionDenied) and therefore HALT even when called inline
# in an action body. But an inline check still runs AFTER any preceding statement
# in that body — so a side effect placed before it executes before the check.
# The correct, side-effect-free usage is a `before_action` gate (or a private
# helper invoked by one), which runs before any action code.
#
# This guard flags a require_permission* call that appears as a bare statement
# inside a PUBLIC method body — i.e. BEFORE the file's first top-level `private`
# — which for an api/v1 controller means inside an action. It EXCLUDES:
#   • `before_action -> { require_permission(...) }` lambda declarations,
#   • any line containing a `->` lambda,
#   • the `return require_permission(...) if ...` per-action dispatch pattern,
#   • everything below `private` (before_action helper methods live there).
#
# HEURISTIC (per-controller, low-noise): a require_permission* call is FLAGGED
# when it is a statement before the first `private`, not on a before_action /
# lambda / return line. Legitimate gates (before_action lambdas above private,
# helpers below private, return-dispatch) are all excluded.
#
# KNOWN LIMITATION (convention-dependent): a before_action helper defined ABOVE
# `private` (and wired by symbol, `before_action :gate`) would be treated as an
# action body and flagged. By convention helpers live below `private`, so this
# does not occur in the current tree; if it ever does, move the helper below
# `private` (the convention) rather than weakening the guard.
#
# SCOPE: server/app/controllers/api/v1/**/*.rb (where actions live).
#
# EXIT CODES
#   0  no inline-in-action-body permission checks
#   1  one or more inline checks (a regression — move it to a before_action)
# Advisory-friendly: pass --warn to always exit 0 (report-only mode).
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CONTROLLERS_DIR="server/app/controllers/api/v1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WARN_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --warn) WARN_ONLY=1 ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# Emit "relpath:line: <code>" for every inline-in-public-body permission check.
find_violations() {
    find "${CONTROLLERS_DIR}" -name '*.rb' -type f 2>/dev/null | sort | while IFS= read -r f; do
        awk '
            FNR == 1 { in_private = 0; ba_block = 0 }
            # First top-level `private` switches us into helper territory.
            /^[[:space:]]*private[[:space:]]*$/ { in_private = 1; next }
            in_private { next }
            # A `before_action do ... end` block is a valid gate; skip its body
            # (simple non-nested form — these blocks do not nest in practice).
            # Note: avoid \b (not portable in awk) — match a trailing `do`.
            /before_action[^#]*[[:space:]]do[[:space:]]*$/ { ba_block = 1; next }
            ba_block && /^[[:space:]]*end[[:space:]]*$/ { ba_block = 0; next }
            ba_block { next }
            /require_(permission|any_permission|all_permissions)[[:space:]]*\(/ {
                if ($0 ~ /before_action/) next      # lambda/symbol in a filter declaration
                if ($0 ~ /->/) next                 # any lambda line
                if ($0 ~ /(^|[^a-zA-Z_])return[[:space:]]/) next  # return-dispatch helper
                if ($0 ~ /[[:space:]]*def[[:space:]]/) next       # a method definition line
                gsub(/^[[:space:]]+/, "")
                print FILENAME ":" FNR ": " $0
            }
        ' "$f"
    done
}

echo -e "${BLUE}=== Inline require_permission guard ===${NC}"
echo "Scanning ${CONTROLLERS_DIR} for permission checks inline in action bodies"
echo ""

violations="$(find_violations)"
count=0
if [[ -n "$violations" ]]; then
    count=$(printf '%s\n' "$violations" | grep -c .)
fi

if [[ "$count" -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS — no inline-in-action-body permission checks.${NC}"
    exit 0
fi

printf '%s\n' "$violations" | while IFS= read -r line; do
    echo -e "${RED}✗ ${line}${NC}"
done
echo ""
echo -e "${RED}✗ FAIL — ${count} inline permission check(s) in a public action body.${NC}"
echo -e "${YELLOW}  Move the check to a before_action gate (or a private helper invoked by one)"
echo -e "  so it runs before any action code. require_permission raises and halts,"
echo -e "  but inline it still runs after preceding statements in the body.${NC}"
if [[ "$WARN_ONLY" -eq 1 ]]; then
    echo -e "${YELLOW}(--warn: reporting only, exiting 0)${NC}"
    exit 0
fi
exit 1
