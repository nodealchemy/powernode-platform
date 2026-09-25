#!/bin/bash
# Lists every LOCAL copy of a shared UI primitive (plan §3, fc-48), one line per
# occurrence:
#
#   <path>|status-fn|<name>             local get*Status*Color/Badge/Variant/... fn
#   <path>|severity-fn|<name>           local get*Severity/Priority/Risk/Level*Color/... fn
#                                       -> use statusVariant()/severityVariant()
#                                          (@/shared/utils/statusVariant)
#   <path>|format-currency|<name>       local formatCurrency/Cost/Money/Price/Amount
#   <path>|format-relative-time|<name>  local formatRelativeTime/timeAgo/...
#   <path>|format-bytes|<name>          local formatBytes/formatFileSize/formatSize/...
#                                       -> use @/shared/utils/formatters
#   <path>|local-variant|<name>         a local binding NAMED statusVariant/severityVariant
#                                       (fn, map or value) shadowing the shared helpers
#   <path>|stat-card|<name>             local StatCard/StatsCard/MetricCard/SummaryCard/...
#                                       -> use MetricCard (@/shared/components/ui/Card)
#   <path>|empty-state                  inline empty state: a className holding both
#                                       text-center and py-8/py-12 -> use <EmptyState>
#
# The single definition of what counts, shared by
# scripts/generate-local-primitive-baseline.sh and
# scripts/checks/local-primitives-ratchet.sh (run by pattern-validation.sh), so
# the ledger and the gate can never disagree about a match.
#
# Scope: frontend/src, every extensions/*/frontend/src and every
# extensions/private/*/frontend/src under the CURRENT directory (the repo root,
# or a test fixture). No extension is named; a private path exists only on a
# maintainer checkout. Test files and test support are out of scope, and so are
# the shared homes themselves.
#
# A DEFINITION is matched on its declaring line — `function NAME(`,
# `const NAME = (...) =>`, `const NAME = useCallback(`/`function` — never a
# call site. Comments are not stripped: a commented-out copy is still a copy.
#
# Exits 0 on a successful listing (possibly empty); 3 if perl is unusable, so a
# caller can tell "nothing found" from "could not look".
set -uo pipefail

command -v perl >/dev/null 2>&1 || { echo "list-local-primitive-sites.sh: perl is unavailable" >&2; exit 3; }

roots=()
for root in frontend/src extensions/*/frontend/src extensions/private/*/frontend/src; do
  [ -d "$root" ] && roots+=("$root")
done
[ "${#roots[@]}" -eq 0 ] && exit 0

find "${roots[@]}" -type f \( -name '*.ts' -o -name '*.tsx' \) \
  ! -name '*.d.ts' ! -name '*.test.ts' ! -name '*.test.tsx' ! -name '*.spec.ts' ! -name '*.spec.tsx' \
  ! -path '*/node_modules/*' ! -path '*/__tests__/*' ! -path '*/__mocks__/*' ! -path '*/tests/*' \
  ! -path '*/test-utils/*' ! -name 'test-utils.tsx' ! -name 'test-utils.ts' \
  ! -path 'frontend/src/shared/utils/formatters.ts' \
  ! -path 'frontend/src/shared/utils/statusVariant.ts' \
  ! -path 'frontend/src/shared/components/ui/Card.tsx' \
  ! -path 'frontend/src/shared/components/ui/EmptyState.tsx' \
  -print0 | sort -z | xargs -0 -r perl -ne '
    BEGIN {
      my $def = sub {
        my $name = shift;
        return qr/(?:\bfunction\s+($name)\s*[<(]|\b(?:const|let)\s+($name)\s*(?::[^=]+)?=\s*(?:(?:async\s+)?(?:\([^)]*\)|[\w\$]+)\s*(?::[^=]+)?=>|(?:React\.)?useCallback\s*\(|function\b))/;
      };
      @rules = (
        ["status-fn",            $def->(q{get\w*(?:Status|State)\w*(?:Color|Colour|Badge|Variant|Class|Classes|Style|Styles|Tone)\w*})],
        ["severity-fn",          $def->(q{get\w*(?:Severity|Priority|Risk|Level)\w*(?:Color|Colour|Badge|Variant|Class|Classes|Style|Styles|Tone)\w*})],
        ["format-currency",      $def->(q{format(?:Currency|Cost|Money|Price|Amount)})],
        ["format-relative-time", $def->(q{(?:formatRelativeTime|formatTimeAgo|timeAgo|getRelativeTime|formatRelative)})],
        ["format-bytes",         $def->(q{(?:formatBytes|formatFileSize|formatSize|humanFileSize)})],
        ["local-variant",        qr/\b(?:function|const|let)\s+((?:status|severity)Variant)\b/],
        ["stat-card",            qr/(?:\bfunction\s+|\b(?:const|let)\s+)(StatCard|StatsCard|MetricCard|SummaryCard|StatTile|MetricTile)\b/],
      );
      $empty = qr/className=\{?["\x27`][^"\x27`]*(?:\btext-center\b[^"\x27`]*\bpy-(?:8|12)\b|\bpy-(?:8|12)\b[^"\x27`]*\btext-center\b)[^"\x27`]*["\x27`]/;
    }
    for my $r (@rules) {
      my ($kind, $re) = @$r;
      while (/$re/g) { my $n = defined $1 ? $1 : $2; print "$ARGV|$kind|$n\n"; }
    }
    while (/$empty/g) { print "$ARGV|empty-state\n"; }
  '

# Explicit success: the status of the last command in a pipeline is not the
# listing's verdict (see list-console-sites.sh).
exit 0
