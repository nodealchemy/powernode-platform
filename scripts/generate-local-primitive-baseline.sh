#!/bin/bash
# Regenerates the local-UI-primitive ledgers (plan §3, fc-48) from
# scripts/list-local-primitive-sites.sh.
#
# Each tree owns its ledger (see scripts/checks/local-primitives-ratchet.sh):
#   core                   .claude/hooks/local-primitive-baseline.txt
#   every extension tree   <tree>/frontend/src/__tests__/conventions/local-primitive-baseline.txt
# so a private extension's paths live, and are committed, only in that
# extension's own tree. Extension trees are found by directory walk; only
# checked-out trees are written.
#
# Entries are the lister's lines, one per occurrence, sorted: the gate compares
# MULTISETS in both directions, so a new local copy fails and so does an entry
# whose copy was removed. Run this in the diff that migrates a copy to the
# shared primitive; never to admit a new one.
#
# Run from the repository root.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

EXT_LEDGER_REL="frontend/src/__tests__/conventions/local-primitive-baseline.txt"

# The lister exits 3 when it cannot look; let that abort us rather than write
# empty ledgers.
all="$(bash scripts/list-local-primitive-sites.sh | sed '/^$/d' | LC_ALL=C sort)"

# write <file> <owner> <prefix>: the lister lines under <prefix>, with a header.
write() {
  mkdir -p "$(dirname "$1")"
  {
    echo "# Local copies of shared UI primitives awaiting their sweep (plan §3, fc-48)."
    echo "# $2's ledger: only paths inside its own tree."
    echo "# Format: <path>|<rule>[|<name>], one line per occurrence, sorted."
    echo "# Regenerate: bash scripts/generate-local-primitive-baseline.sh — only to record a removal."
    printf '%s\n' "$all" | awk -v p="$3" 'NF && index($0, p) == 1'
  } > "$1"
  echo "Wrote $(command grep -cv '^#' "$1" || true) entries to $1"
}

write ".claude/hooks/local-primitive-baseline.txt" "core" "frontend/"
for tree in extensions/* extensions/private/*; do
  [ -d "$tree/frontend/src" ] || continue
  write "$tree/$EXT_LEDGER_REL" "$tree" "$tree/"
done
