#!/bin/bash
# Regenerates the grandfathered-console-site ledgers for IMP-1f4b84af602c.
#
# The console guards (the console-log-check.sh edit hook and the frontend-console
# check in scripts/pattern-validation.sh) matched only console.log/debug/info, so
# warn and error accumulated unchecked for the life of the tree. Widening them
# surfaces every legacy call site at once; these ledgers record the ones that
# already existed so the guards fail on NEW sites only.
#
# Two files, mirroring the core-purity baselines:
#   .claude/hooks/console-log-baseline.txt        tracked     core + public extensions
#   .claude/hooks/console-log-baseline.local.txt  gitignored  private extensions
# Private-extension paths must never reach the public mirror, so they are split
# out rather than filtered at read time.
#
# Entries are `path|trimmed source line`, ONE LINE PER OCCURRENCE and sorted, so
# the consumers can compare multisets: a file that legitimately holds two
# identical console.error calls gets two entries, and adding a third is a new
# site rather than a free ride on the first two's membership. Line numbers are
# deliberately absent — they churn on every edit above the call.
#
# Shrink these files as code migrates to @/shared/utils/logger; never add to
# them by hand.
#
# Run from the repository root.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PUBLIC=".claude/hooks/console-log-baseline.txt"
LOCAL=".claude/hooks/console-log-baseline.local.txt"

# The lister exits 3 when grep -P is unusable. Let that abort us rather than
# writing an empty ledger, which would silently grandfather nothing and then
# fail the gate on the whole tree.
all="$(bash scripts/list-console-sites.sh)"

# `path|lineno|text` -> `path|text`
identities() { printf '%s\n' "$all" | cut -d'|' -f1,3- | sed '/^$/d'; }

header() {
  echo "# Grandfathered console call sites (IMP-1f4b84af602c)."
  echo "# $1"
  echo "# Format: <path>|<trimmed source line>, one line per occurrence, sorted."
  echo "# Regenerate: bash scripts/generate-console-log-baseline.sh"
  echo "# Do not add entries by hand — new sites must use @/shared/utils/logger."
}

# `|| true` on both filters is load-bearing: grep exits 1 on no match, and under
# `set -e` that aborts the redirection group AFTER it has truncated the ledger.
# The no-match case is not exotic — it is the goal state once core finishes
# migrating, and it is every public clone with no private extensions.
{
  header "Core + public extensions. Tracked; publishes to the public mirror."
  identities | grep -v '^extensions/private/' | sort || true
} > "$PUBLIC"

{
  header "Private extensions only. GITIGNORED — never publish these paths."
  identities | grep '^extensions/private/' | sort || true
} > "$LOCAL"

pub_n=$(identities | grep -cv '^extensions/private/' || true)
loc_n=$(identities | grep -c '^extensions/private/' || true)
echo "Wrote $PUBLIC (${pub_n:-0} entries) and $LOCAL (${loc_n:-0} entries)"
