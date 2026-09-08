#!/bin/bash
# Lists every console.<level> call site the console guards police, as
# `path|lineno|trimmed source line`.
#
# Shared by scripts/generate-console-log-baseline.sh, the frontend-console check
# in scripts/pattern-validation.sh, and the .claude/hooks/console-log-check.sh
# edit hook, so those three police exactly the same set. That sharing is the
# point: the four console.warn calls this was written for (IMP-1f4b84af602c)
# survived because each guard carried its OWN copy of the pattern and every copy
# stopped at log/debug/info.
#
# NOT the only console pattern in the tree — scripts/cleanup-all-console-logs.sh
# deliberately keeps a narrower one, because it REWRITES code and is meant to
# preserve error/warn. It is a codemod, not a guard.
#
# Scope: core frontend/src, every public extensions/*/frontend/src, and every
# private extensions/private/*/frontend/src. Private paths exist only on a
# maintainer checkout; a public clone finds no such directory.
#
# Exempt, by PATH only (never by source text — a message that merely mentions
# `logger.ts` must not exempt itself): the logger, the CodeSamples showcase, and
# specs.
#
# With an argument, restricts the scan to that single file — the form the edit
# hook uses. Output shape is identical in both modes.
#
# Run from the repository root. Exits 0 on a successful listing; exits 3 if the
# grep engine itself is unusable, so a caller can tell "nothing found" from
# "could not look".
set -uo pipefail

LEVELS='log|debug|info|warn|error|trace|table|assert|dir|group|groupEnd|count|time|timeEnd'
# `console?.warn(...)` is idiomatic TS and would otherwise be a one-character
# bypass. Aliasing (`const c = console`) is out of reach of a grep guard and is
# not chased here.
PATTERN="console\s*\??\s*\.\s*($LEVELS)\s*\("

# Fail loudly if grep cannot do PCRE at all, rather than reporting an empty
# tree. The guard this replaced reported a clean 0 on a tree holding 36 calls;
# an unusable matcher must not reproduce that.
if ! printf 'console.warn(' | grep -qP "$PATTERN" 2>/dev/null; then
  echo "list-console-sites.sh: grep -P is unavailable or the pattern is broken" >&2
  exit 3
fi

# Drops a match that sits inside a comment and keeps one that does not.
# Prefix-matching the trimmed line was not enough: `/** x */ console.warn(…)`
# starts with `/*` and would have been skipped entirely.
filter_and_emit() {
  LEVELS="$LEVELS" perl -ne '
    next unless /^([^:]+):(\d+):(.*)$/s;
    my ($path, $lineno, $src) = ($1, $2, $3);
    next if $path =~ m{(^|/)(logger\.ts|CodeSamples\.tsx)$};
    next if $path =~ m{\.(test|spec)\.tsx?$};
    my $trimmed = $src;
    $trimmed =~ s/^\s+//; $trimmed =~ s/\s+$//;
    next if $trimmed =~ m{^\*};
    my $levels = $ENV{LEVELS};
    next unless $trimmed =~ /^(.*?)console\s*\??\s*\.\s*(?:$levels)\s*\(/;
    my $before = $1;
    next if $before =~ m{//};
    my $opens = () = $before =~ m{/\*}g;
    my $closes = () = $before =~ m{\*/}g;
    next if $opens > $closes;
    print "$path|$lineno|$trimmed\n";
  '
}

if [ "$#" -gt 0 ]; then
  # `grep -H` keeps the path in the output when only one file is given.
  grep -HnP "$PATTERN" "$1" 2>/dev/null | filter_and_emit
  exit 0
fi

for root in frontend/src extensions/*/frontend/src extensions/private/*/frontend/src; do
  [ -d "$root" ] || continue
  grep -rnP "$PATTERN" "$root" --include='*.ts' --include='*.tsx' 2>/dev/null \
    | filter_and_emit
done

# Explicit success. Without this the script's status is that of the final
# `[ -d "$root" ]` test, which is FALSE whenever the last glob candidate (a
# private extension) is absent — so a caller running under `set -e` aborts on a
# perfectly good, complete listing. The core-purity gate carries the same
# warning about a guard that dies quietly.
exit 0
