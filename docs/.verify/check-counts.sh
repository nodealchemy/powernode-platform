#!/usr/bin/env bash
# Advisory count-drift scan: flags hardcoded counts likely to drift
# (e.g. "305 actions", "52 tools", "14 tables"). NON-FAILING — reviewer
# attention only. The auto-generated docs in docs/reference/auto/ are the
# canonical place for counts; everywhere else, prefer "see auto/MCP-tools"
# style links over inline numbers.
#
# Exit code:
#   0 — always (advisory). Use the output to decide whether to convert
#       a hardcoded number into a link to the auto-gen catalog.
#
# Run from platform root:
#   bash docs/.verify/check-counts.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PLATFORM_ROOT" || exit 2

echo "Advisory count-drift scan"
echo "------------------------------------------"
echo "(non-failing — review hits and convert inline counts to links if drift-prone)"
echo

# Things that drift: action/class/tool/table/provider/model/skill/node/edge counts
hits=$(rg --no-heading "\b[0-9]{2,4}\b (actions|classes|tools|tables|providers|models|skills|nodes|edges)" \
   docs/ README.md CLAUDE.md \
   --glob "!history/**" --glob "!reference/auto/**" --glob "!.verify/**" \
   --glob "!_consolidation*" --glob "!_redirects*" \
   2>/dev/null || true)

if [ -z "$hits" ]; then
  echo "  no count-shaped strings found outside history/ and auto/"
else
  echo "$hits"
fi

echo
echo "------------------------------------------"
echo "Done. Exit 0 (advisory)."

exit 0
