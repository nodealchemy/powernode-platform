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
# Usage: scripts/measure-claude-context.sh
set -euo pipefail

PROJECT_DIR="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$PROJECT_DIR"

total=0

row() { # label bytes
  printf '%-58s %10d %9d\n' "$1" "$2" "$(( $2 / 4 ))"
}

subtotal() { # label bytes
  printf '%-58s %10d %9d\n' "  subtotal: $1" "$2" "$(( $2 / 4 ))"
  echo
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

printf '%-58s %10s %9s\n' "item" "bytes" "~tokens"
printf '%-58s %10s %9s\n' "----" "-----" "-------"

sum=0
for f in CLAUDE.md server/CLAUDE.md frontend/CLAUDE.md worker/CLAUDE.md; do
  if [ -f "$f" ]; then
    b=$(wc -c < "$f")
    row "$f" "$b"
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
row ".claude/agents/powernode: description: ($count files)" "$desc_sum"
row ".claude/agents/powernode: tools: ($count files)" "$tools_sum"
subtotal "agent frontmatter" "$(( desc_sum + tools_sum ))"

sum=0
while IFS= read -r f; do
  b=$(wc -c < "$f")
  row "$f" "$b"
  sum=$(( sum + b ))
done < <(find .claude/skills -name SKILL.md -type f | sort)
subtotal "SKILL.md" "$sum"

row "TOTAL" "$total"
