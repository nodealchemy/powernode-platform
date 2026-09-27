#!/bin/bash
# Measure the Claude Code context this repository puts in front of a session:
# the four CLAUDE.md files, the `description:` and `tools:` frontmatter of every
# .claude/agents/powernode/*.md (the Agent tool lists both for every subagent),
# and each .claude/skills/*/SKILL.md. Prints bytes and approximate tokens
# (bytes / 4) per item, a subtotal per group and a total.
#
# Read-only; no network, no model calls. Run it before and after a change to the
# prompt surface to size the change.
#
# --check compares every measured surface against scripts/claude-context-budget.txt
# (override with CLAUDE_CONTEXT_BUDGET_FILE) and exits 1 when a surface is over
# its budget, when a measured surface has no budget line (a new skill must be
# budgeted on purpose, not slip in unmeasured), or when a budget line names a
# surface that no longer exists (a dead line is a budget nobody is checking).
# Raising a budget is a deliberate edit to that file, reviewed like any other.
#
# Usage: scripts/measure-claude-context.sh [--check]
set -euo pipefail

PROJECT_DIR="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$PROJECT_DIR"

CHECK=false
case "${1:-}" in
  "") ;;
  --check) CHECK=true ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac
BUDGET_FILE="${CLAUDE_CONTEXT_BUDGET_FILE:-$PROJECT_DIR/scripts/claude-context-budget.txt}"

total=0
# Stable surface key -> measured bytes, for --check. Keys are the file path, or
# `.claude/agents/powernode:<field>` for the aggregated agent frontmatter (the
# printed label carries a file count, which is not stable).
declare -A MEASURED=()

row() { # label bytes
  $CHECK || printf '%-58s %10d %9d\n' "$1" "$2" "$(( $2 / 4 ))"
}

surface() { # key label bytes
  MEASURED["$1"]=$3
  row "$2" "$3"
}

subtotal() { # label bytes
  if ! $CHECK; then
    printf '%-58s %10d %9d\n' "  subtotal: $1" "$2" "$(( $2 / 4 ))"
    echo
  fi
  total=$(( total + $2 ))
}

# Bytes of one frontmatter field (the key line plus any indented continuation
# lines) in the leading --- block of a markdown file.
field_bytes() { # file key
  awk -v key="$2" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      if ($0 ~ "^" key ":") { grab = 1; print; next }
      if (grab && $0 ~ /^[ \t]/) { print; next }
      grab = 0
    }
  ' "$1" | wc -c
}

if ! $CHECK; then
  printf '%-58s %10s %9s\n' "item" "bytes" "~tokens"
  printf '%-58s %10s %9s\n' "----" "-----" "-------"
fi

sum=0
for f in CLAUDE.md server/CLAUDE.md frontend/CLAUDE.md worker/CLAUDE.md; do
  if [ -f "$f" ]; then
    b=$(wc -c < "$f")
    surface "$f" "$f" "$b"
    sum=$(( sum + b ))
  else
    row "$f (missing)" 0
  fi
done
subtotal "CLAUDE.md" "$sum"

desc_sum=0
tools_sum=0
count=0
for f in .claude/agents/powernode/*.md; do
  [ -f "$f" ] || continue
  desc_sum=$(( desc_sum + $(field_bytes "$f" description) ))
  tools_sum=$(( tools_sum + $(field_bytes "$f" tools) ))
  count=$(( count + 1 ))
done
surface ".claude/agents/powernode:description" ".claude/agents/powernode: description: ($count files)" "$desc_sum"
surface ".claude/agents/powernode:tools" ".claude/agents/powernode: tools: ($count files)" "$tools_sum"
subtotal "agent frontmatter" "$(( desc_sum + tools_sum ))"

sum=0
while IFS= read -r f; do
  b=$(wc -c < "$f")
  surface "$f" "$f" "$b"
  sum=$(( sum + b ))
done < <(find .claude/skills -name SKILL.md -type f | sort)
subtotal "SKILL.md" "$sum"

if ! $CHECK; then
  row "TOTAL" "$total"
  exit 0
fi

# --check ------------------------------------------------------------------
[ -f "$BUDGET_FILE" ] || { echo "FAIL: budget file not found: $BUDGET_FILE" >&2; exit 1; }

declare -A BUDGET=()
while read -r key max _rest; do
  [[ -z "${key:-}" || "$key" == \#* ]] && continue
  if ! [[ "${max:-}" =~ ^[0-9]+$ ]]; then
    echo "FAIL: malformed budget line for '$key' in $BUDGET_FILE (want: <surface> <max_bytes>)"
    exit 1
  fi
  BUDGET["$key"]=$max
done < "$BUDGET_FILE"

fail=0
while IFS= read -r key; do
  bytes=${MEASURED[$key]}
  max=${BUDGET[$key]:-}
  if [ -z "$max" ]; then
    echo "FAIL: $key ($bytes bytes) has no budget line in ${BUDGET_FILE#"$PROJECT_DIR"/}"
    fail=1
  elif [ "$bytes" -gt "$max" ]; then
    echo "FAIL: $key is $bytes bytes, over its budget of $max (+$(( bytes - max )))"
    fail=1
  fi
done < <(printf '%s\n' "${!MEASURED[@]}" | sort)

while IFS= read -r key; do
  if [ -z "${MEASURED[$key]+set}" ]; then
    echo "FAIL: budget line '$key' names a surface that was not measured — remove it"
    fail=1
  fi
done < <(printf '%s\n' "${!BUDGET[@]}" | sort)

if [ "$fail" -ne 0 ]; then
  echo "Claude context budget exceeded. Shrink the surface, or raise its line in ${BUDGET_FILE#"$PROJECT_DIR"/} as a reviewed decision."
  exit 1
fi
echo "PASS: ${#MEASURED[@]} Claude context surfaces within budget ($total bytes, ~$(( total / 4 )) tokens)"
