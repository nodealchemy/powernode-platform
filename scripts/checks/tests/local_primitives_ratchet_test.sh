#!/bin/bash
# Red/green test for scripts/checks/local-primitives-ratchet.sh (plan §3, fc-48):
# the equality ratchet over local copies of shared UI primitives.
#
# Each arm runs the checker against a throwaway fixture tree with fixture
# ledgers, and asserts BOTH the exit code and the reason it printed, so an arm
# cannot pass by failing for a different cause.
#
#   clean    ledger == sites                         -> exit 0
#   new      a getStatusColor not in the ledger      -> exit 1, "New local copies"
#   stale    a ledger entry whose copy is gone       -> exit 1, "Stale ledger entries"
#   empty    lister finds nothing, ledger non-empty  -> exit 1, "found NOTHING"
#   blind    lister cannot look (exit 3)             -> exit 1, "could not look (exit 3)"
#   absent   entry under a private tree not checked out is not compared -> exit 0
#   public   entry under an absent PUBLIC path is still compared -> exit 1, stale
#   multi    a second identical site with one ledger entry -> exit 1, new (multiset)
#   rule     a non-status rule (formatBytes) through the real lister -> exit 1, new
#
# LOCAL_PRIMITIVES_CHECKER overrides the checker under test (for red-first runs
# against a mutant).
#
# Usage: bash scripts/checks/tests/local_primitives_ratchet_test.sh
# Exits 0 if all assertions pass, 1 otherwise.
set -u

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1
CHECKER="${LOCAL_PRIMITIVES_CHECKER:-$REPO/scripts/checks/local-primitives-ratchet.sh}"
LISTER="$REPO/scripts/list-local-primitive-sites.sh"

fail=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A fixture tree with one local status-colour function, and a ledger naming it.
fixture() {
  local dir="$work/$1"
  mkdir -p "$dir/frontend/src/features/widgets"
  cat > "$dir/frontend/src/features/widgets/WidgetList.tsx" <<'TSX'
const getStatusColor = (status: string) => (status === 'active' ? 'green' : 'gray');
export const WidgetList = () => getStatusColor('active');
TSX
  printf '# ledger\nfrontend/src/features/widgets/WidgetList.tsx|status-fn|getStatusColor\n' > "$dir/ledger.txt"
  : > "$dir/ledger.local.txt"
  echo "$dir"
}

run() { # dir [lister] -> sets out, code
  local dir="$1" lister="${2:-$LISTER}"
  out=$(cd "$dir" && LOCAL_PRIMITIVES_LISTER="$lister" \
        LOCAL_PRIMITIVES_LEDGER="$dir/ledger.txt" LOCAL_PRIMITIVES_LEDGER_LOCAL="$dir/ledger.local.txt" \
        bash "$CHECKER" 2>&1)
  code=$?
}

assert() { # desc expected_code expected_text
  local desc="$1" want="$2" text="$3"
  if [ "$code" -eq "$want" ] && { [ -z "$text" ] || printf '%s' "$out" | command grep -qF -- "$text"; }; then
    echo "PASS: $desc (exit $code)"
  else
    echo "FAIL: $desc (expected exit $want${text:+ with \"$text\"}, got exit $code)"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  fi
}

dir=$(fixture clean)
run "$dir"
assert "clean: ledger equals sites" 0 ""

dir=$(fixture new)
cat > "$dir/frontend/src/features/widgets/WidgetCard.tsx" <<'TSX'
function getStatusColor(status: string) { return status; }
export const WidgetCard = () => getStatusColor('x');
TSX
run "$dir"
assert "new: an unledgered local status fn fails" 1 "frontend/src/features/widgets/WidgetCard.tsx|status-fn|getStatusColor"
assert "new: reported as a new copy" 1 "New local copies"

dir=$(fixture stale)
echo "frontend/src/features/widgets/Gone.tsx|format-bytes|formatBytes" >> "$dir/ledger.txt"
run "$dir"
assert "stale: a ledger entry with no site fails" 1 "frontend/src/features/widgets/Gone.tsx|format-bytes|formatBytes"
assert "stale: reported as stale" 1 "Stale ledger entries"

dir=$(fixture empty)
printf '#!/bin/bash\nexit 0\n' > "$work/empty-lister.sh"
run "$dir" "$work/empty-lister.sh"
assert "empty: a silent lister with a non-empty ledger fails loud" 1 "found NOTHING"

dir=$(fixture blind)
printf '#!/bin/bash\nexit 3\n' > "$work/blind-lister.sh"
run "$dir" "$work/blind-lister.sh"
assert "blind: a lister that cannot look fails, reporting its exit code" 1 "could not look (exit 3)"

dir=$(fixture absent)
echo "extensions/private/nothere/frontend/src/X.tsx|stat-card|StatCard" >> "$dir/ledger.local.txt"
run "$dir"
assert "absent: entries under a tree not checked out are not compared" 0 ""

dir=$(fixture public)
echo "extensions/ghost/frontend/src/Y.tsx|empty-state" >> "$dir/ledger.txt"
run "$dir"
assert "public: an entry under an absent public path is still compared (stale)" 1 "extensions/ghost/frontend/src/Y.tsx|empty-state"

dir=$(fixture multi)
cat >> "$dir/frontend/src/features/widgets/WidgetList.tsx" <<'TSX'
function getStatusColor(s: string) { return s; }
TSX
run "$dir"
assert "multi: a second identical site beyond the ledger's one entry is new" 1 "New local copies"

dir=$(fixture rule)
cat > "$dir/frontend/src/features/widgets/Size.tsx" <<'TSX'
export const formatBytes = (n: number) => `${n} B`;
TSX
run "$dir"
assert "rule: a local formatBytes is caught through the real lister" 1 "frontend/src/features/widgets/Size.tsx|format-bytes|formatBytes"

exit $fail
