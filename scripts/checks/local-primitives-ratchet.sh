#!/bin/bash
# Equality ratchet over local copies of shared UI primitives (plan §3, fc-48).
#
# Compares scripts/list-local-primitive-sites.sh against the ledgers as
# MULTISETS, in both directions:
#   - a site not in a ledger is a NEW local copy -> fail (use the shared one);
#   - a ledger entry with no site is STALE -> fail (the sweep that removed the
#     copy must shrink the ledger in the same diff:
#     bash scripts/generate-local-primitive-baseline.sh).
# And it FAILS LOUD when the lister finds nothing while the ledgers hold
# entries: that is a broken matcher, not a clean tree.
#
# EACH TREE OWNS ITS LEDGER, exactly as with the export-orphan allowlists:
#   core                   .claude/hooks/local-primitive-baseline.txt
#   every extension tree   <tree>/frontend/src/__tests__/conventions/local-primitive-baseline.txt
# Extension trees (extensions/<x>, extensions/private/<x>) are found by
# directory walk, never by name, and a ledger may list only paths inside its
# own tree (the core ledger: frontend/ only) — an entry outside it fails
# loud. A tree that is not checked out contributes neither sites nor a
# ledger, so every checkout, public or not, agrees with itself.
#
# Run from the repository root (or a fixture root; LOCAL_PRIMITIVES_LISTER and
# LOCAL_PRIMITIVES_LEDGER point elsewhere for tests). Exit 0 clean, 1 on
# new/stale sites, a misplaced entry or a broken lister.
set -uo pipefail

LISTER="${LOCAL_PRIMITIVES_LISTER:-scripts/list-local-primitive-sites.sh}"
LEDGER="${LOCAL_PRIMITIVES_LEDGER:-.claude/hooks/local-primitive-baseline.txt}"
EXT_LEDGER_REL="frontend/src/__tests__/conventions/local-primitive-baseline.txt"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bash "$LISTER" > "$tmp/raw"
lister_rc=$?
if [ "$lister_rc" -ne 0 ]; then
  echo "local-primitives-ratchet: the lister could not look (exit $lister_rc)"
  exit 1
fi
sed '/^$/d' "$tmp/raw" | LC_ALL=C sort > "$tmp/found"

misplaced=0
: > "$tmp/ledger"
# ledger_of <file> <owner-label> <required-prefix>
ledger_of() {
  [ -f "$1" ] || return 0
  while IFS= read -r entry; do
    case "$entry" in ''|'#'*) continue ;; esac
    case "$entry" in
      "$3"*) printf '%s\n' "$entry" >> "$tmp/ledger" ;;
      *) echo "$2: ledger entry outside its own tree: $entry"; misplaced=1 ;;
    esac
  done < "$1"
}

ledger_of "$LEDGER" "core" "frontend/"
for tree in extensions/* extensions/private/*; do
  [ -d "$tree" ] || continue
  [ "$tree" = "extensions/private" ] && continue
  ledger_of "$tree/$EXT_LEDGER_REL" "$tree" "$tree/"
done
LC_ALL=C sort -o "$tmp/ledger" "$tmp/ledger"

found_n=$(wc -l < "$tmp/found" | tr -d ' ')
ledger_n=$(wc -l < "$tmp/ledger" | tr -d ' ')
if [ "$found_n" -eq 0 ] && [ "$ledger_n" -gt 0 ]; then
  echo "local-primitives-ratchet: the lister found NOTHING while the ledgers hold $ledger_n entries — broken matcher, not a clean tree"
  exit 1
fi

new=$(LC_ALL=C comm -23 "$tmp/found" "$tmp/ledger")
stale=$(LC_ALL=C comm -13 "$tmp/found" "$tmp/ledger")
status=$misplaced
if [ -n "$new" ]; then
  echo "New local copies of a shared primitive (use statusVariant/severityVariant, @/shared/utils/formatters, MetricCard or <EmptyState>):"
  printf '%s\n' "$new" | sed 's/^/    /'
  status=1
fi
if [ -n "$stale" ]; then
  echo "Stale ledger entries (their copy is gone; run bash scripts/generate-local-primitive-baseline.sh in this diff):"
  printf '%s\n' "$stale" | sed 's/^/    /'
  status=1
fi
exit $status
