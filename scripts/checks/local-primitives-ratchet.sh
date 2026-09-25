#!/bin/bash
# Equality ratchet over local copies of shared UI primitives (plan §3, fc-48).
#
# Compares scripts/list-local-primitive-sites.sh against the ledgers as
# MULTISETS, in both directions:
#   - a site not in the ledger is a NEW local copy -> fail (use the shared one);
#   - a ledger entry with no site is STALE -> fail (the sweep that removed the
#     copy must shrink the ledger in the same diff:
#     bash scripts/generate-local-primitive-baseline.sh).
# And it FAILS LOUD when the lister finds nothing while the ledger holds
# entries: that is a broken matcher, not a clean tree.
#
# Ledgers default to the tracked .claude/hooks/local-primitive-baseline.txt and
# the gitignored .local.txt (private paths). Only ledger entries whose tree is
# checked out are compared, so a public clone (no private tree, no .local file)
# agrees with itself.
#
# Run from the repository root (or a fixture root; LOCAL_PRIMITIVES_LISTER and
# the LEDGER variables point elsewhere for tests). Exit 0 clean, 1 on
# new/stale sites or a broken lister.
set -uo pipefail

LISTER="${LOCAL_PRIMITIVES_LISTER:-scripts/list-local-primitive-sites.sh}"
LEDGER="${LOCAL_PRIMITIVES_LEDGER:-.claude/hooks/local-primitive-baseline.txt}"
LEDGER_LOCAL="${LOCAL_PRIMITIVES_LEDGER_LOCAL:-.claude/hooks/local-primitive-baseline.local.txt}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bash "$LISTER" > "$tmp/raw"
lister_rc=$?
if [ "$lister_rc" -ne 0 ]; then
  echo "local-primitives-ratchet: the lister could not look (exit $lister_rc)"
  exit 1
fi
sed '/^$/d' "$tmp/raw" | LC_ALL=C sort > "$tmp/found"

cat "$LEDGER" "$LEDGER_LOCAL" 2>/dev/null | grep -v '^#' | sed '/^$/d' > "$tmp/ledger_all" || true
# Keep only entries whose tree is present (a private tree may not be checked out).
: > "$tmp/ledger"
while IFS= read -r entry; do
  path="${entry%%|*}"
  case "$path" in
    extensions/private/*)
      tree=$(printf '%s' "$path" | cut -d/ -f1-3)
      [ -d "$tree" ] || continue ;;
  esac
  printf '%s\n' "$entry" >> "$tmp/ledger"
done < "$tmp/ledger_all"
LC_ALL=C sort -o "$tmp/ledger" "$tmp/ledger"

found_n=$(wc -l < "$tmp/found" | tr -d ' ')
ledger_n=$(wc -l < "$tmp/ledger" | tr -d ' ')
if [ "$found_n" -eq 0 ] && [ "$ledger_n" -gt 0 ]; then
  echo "local-primitives-ratchet: the lister found NOTHING while the ledger holds $ledger_n entries — broken matcher, not a clean tree"
  exit 1
fi

new=$(LC_ALL=C comm -23 "$tmp/found" "$tmp/ledger")
stale=$(LC_ALL=C comm -13 "$tmp/found" "$tmp/ledger")
status=0
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
