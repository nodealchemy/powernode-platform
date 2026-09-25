#!/bin/bash
# Regenerates the local-UI-primitive ledgers (plan §3, fc-48) from
# scripts/list-local-primitive-sites.sh.
#
# Two files, mirroring the console-log ledgers:
#   .claude/hooks/local-primitive-baseline.txt        tracked     core + public extensions
#   .claude/hooks/local-primitive-baseline.local.txt  gitignored  private extensions
# Private-extension paths must never reach the public mirror, so they are split
# out rather than filtered at read time.
#
# Entries are the lister's lines, one per occurrence, sorted: the gate compares
# MULTISETS in both directions (scripts/checks/local-primitives-ratchet.sh), so
# a new local copy fails and so does an entry whose copy was removed. Run this
# in the diff that migrates a copy to the shared primitive; never to admit a
# new one.
#
# Run from the repository root.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PUBLIC=".claude/hooks/local-primitive-baseline.txt"
LOCAL=".claude/hooks/local-primitive-baseline.local.txt"

# The lister exits 3 when it cannot look; let that abort us rather than write
# an empty ledger.
all="$(bash scripts/list-local-primitive-sites.sh)"

header() {
  echo "# Local copies of shared UI primitives awaiting their sweep (plan §3, fc-48)."
  echo "# $1"
  echo "# Format: <path>|<rule>[|<name>], one line per occurrence, sorted."
  echo "# Regenerate: bash scripts/generate-local-primitive-baseline.sh — only to record a removal."
}

# `|| true`: grep exits 1 on no match, which is the goal state (and every
# public clone for the private ledger).
{
  header "Core + public extensions. Tracked; publishes to the public mirror."
  printf '%s\n' "$all" | sed '/^$/d' | grep -v '^extensions/private/' | LC_ALL=C sort || true
} > "$PUBLIC"

{
  header "Private extensions only. GITIGNORED — never publish these paths."
  printf '%s\n' "$all" | sed '/^$/d' | grep '^extensions/private/' | LC_ALL=C sort || true
} > "$LOCAL"

echo "Wrote $(grep -cv '^#' "$PUBLIC" || true) entries to $PUBLIC and $(grep -cv '^#' "$LOCAL" || true) to $LOCAL"
