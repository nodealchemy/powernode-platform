#!/bin/bash
# Advisory hook: warns when console output is introduced in frontend TS/TSX
# files, and points at the centralized logger instead.
#
# It used to grep for console.(log|debug|info) only, while the frontend-debug
# check in scripts/pattern-validation.sh carried its own copy of that same
# narrow pattern. Two independent copies, both level-blind: console.warn and
# console.error accumulated for the life of the tree and neither guard ever
# said a word (IMP-1f4b84af602c). Both now call scripts/list-console-sites.sh,
# so there is one definition of what counts and it cannot drift again.
#
# Pre-existing sites are grandfathered in the same ledgers the gate uses, so
# this advises only on NEW output. Regenerate them with
# scripts/generate-console-log-baseline.sh.
#
# Advisory only: it always exits 0 and never blocks an edit.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ "$FILE_PATH" != *.ts && "$FILE_PATH" != *.tsx ]] && exit 0
[[ "$FILE_PATH" != *frontend/src* ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
[[ -z "$REPO_ROOT" ]] && exit 0

LISTER="$REPO_ROOT/scripts/list-console-sites.sh"
# In a submodule checkout the shared lister lives in the parent repo.
[[ ! -r "$LISTER" ]] && LISTER="$REPO_ROOT/../../scripts/list-console-sites.sh"
[[ ! -r "$LISTER" ]] && exit 0

# The lister emits `path|line`, where path is relative to the repo root it was
# run from. Run it from that root on the single edited file so the paths it
# prints match the ledger entries.
LISTER_ROOT=$(cd "$(dirname "$LISTER")/.." && pwd)
REL_PATH=${FILE_PATH#"$LISTER_ROOT"/}

SITES=$(cd "$LISTER_ROOT" && bash scripts/list-console-sites.sh "$REL_PATH" 2>/dev/null)
[[ -z "$SITES" ]] && exit 0

# The ledgers hold `path|line` with no line number, one entry per occurrence.
# Consume an entry per match so a THIRD copy of an already-baselined line is
# still reported, rather than riding on the first two's membership.
BASELINE=$(cat "$LISTER_ROOT/.claude/hooks/console-log-baseline.txt" \
                "$LISTER_ROOT/.claude/hooks/console-log-baseline.local.txt" 2>/dev/null \
             | grep -v '^#')

NEW=""
while IFS= read -r site; do
  [[ -n "$site" ]] || continue
  path=${site%%|*}
  rest=${site#*|}
  lineno=${rest%%|*}
  text=${rest#*|}
  identity="${path}|${text}"
  if printf '%s\n' "$BASELINE" | grep -Fxq "$identity"; then
    # Consume exactly ONE occurrence, so N ledger entries cover N copies and no
    # more. `grep -vFx -m1` cannot do this — on an inverted match -m1 stops at
    # the first NON-matching line, which truncates the ledger instead.
    BASELINE=$(printf '%s\n' "$BASELINE" \
      | awk -v k="$identity" 'BEGIN { dropped = 0 }
                              { if (!dropped && $0 == k) { dropped = 1; next } print }')
    continue
  fi
  NEW+="  ${lineno}: ${text}"$'\n'
done <<< "$SITES"

if [[ -n "${NEW//[$'\n' ]/}" ]]; then
  echo "Advisory: new console output in $REL_PATH" >&2
  printf '%s' "$NEW" | grep -v '^$' >&2
  echo "Use: import { logger } from '@/shared/utils/logger'" >&2
fi
exit 0
