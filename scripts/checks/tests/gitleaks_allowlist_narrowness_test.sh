#!/bin/bash
# Red/green test for the secret scan's false-positive handling (IMP-35fee69707e9):
# the files that used to trip it must scan clean, and the rules must still fire
# everywhere else -- including inside those same files, and in the stretch of
# text a legitimate match swallows (a match absorbs everything up to its end,
# so a credential starting inside that window is never matched on its own).
#
# Each arm scans a throwaway fixture tree with the config under test, the way
# scripts/validate.sh step 4 does (--no-git, absolute --source, --redact), or
# with a relative --source where an arm says "rel" (the path shape a git-mode
# scan reports, as the pre-critic gate's gitleaks steps run it). Each asserts
# BOTH the exit code and exactly which rule fired in which file, so an arm
# cannot pass by failing for a different cause.
#
#   real         verbatim copies of the files that used to trip  -> exit 0
#   real-rel     the same, relative source                        -> exit 0
#   extroot-rel  the rails-exec copy rooted at the extension
#                checkout, relative source                        -> exit 0
#   outside      credentialed redis URL, database URL and curl
#                auth header in a file no allowlist names         -> exit 1, one of each rule
#   redis-new    a credentialed redis URL appended to
#                system_settings.rb                               -> exit 1, redis-url there
#   redis-line   one on the same line as its password-shape examples -> exit 1, redis-url there
#   redis-after  one on a code line just after those examples     -> exit 1, redis-url there
#   db-pass      a password added to the allowlisted DATABASE_URL -> exit 1, database-url there
#   db-between   a credentialed URL between that URL and the
#                shell "$@" its match runs to                     -> exit 1, database-url there
#   db-window    a credentialed URL between that "$@" and the
#                match's end (/usr/local/bin/bundle)              -> exit 1, database-url there
#   db-extroot   db-pass, rooted at the extension checkout, rel   -> exit 1, database-url there
#   db-suffix    the verbatim rails-exec under another extension
#                (a path that merely ENDS like the allowlisted one) -> exit 1, database-url there
#
# The fixture tree is created INSIDE the repo: gitleaks reports absolute paths
# for an absolute --source, so a tree under /tmp matches the tmp/ path
# allowlist and every arm would report clean. Credentialed strings are built
# at run time so this file is not itself a finding.
# For red-first runs, GITLEAKS_NARROWNESS_CONFIG overrides the config under
# test and GITLEAKS_NARROWNESS_SOURCE_ROOT where the verbatim files come from.
#
# Run by scripts/validate.sh step 4 after the scan itself.
# Usage: bash scripts/checks/tests/gitleaks_allowlist_narrowness_test.sh
# Exits 0 if all assertions pass, 1 otherwise (2 if gitleaks or jq is missing).
set -u

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1
CONFIG="${GITLEAKS_NARROWNESS_CONFIG:-$REPO/.gitleaks.toml}"
SRC="${GITLEAKS_NARROWNESS_SOURCE_ROOT:-$REPO}"
command -v gitleaks >/dev/null 2>&1 || { echo "gitleaks is not installed; nothing was tested"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is not installed"; exit 2; }

RUBY_REL="server/app/services/admin/system_settings.rb"
EXEC_EXT_REL="modules/powernode-hub-backend/rootfs/usr/local/bin/powernode-rails-exec"
EXEC_REL="extensions/system/$EXEC_EXT_REL"
for f in "$RUBY_REL" "$EXEC_REL"; do
  [ -f "$SRC/$f" ] || { echo "missing $f (extension checkout not initialised?)"; exit 1; }
done

fail=0
work="$(mktemp -d "$REPO/.gitleaks-selftest.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT

# Credentialed shapes, assembled so no literal in this file matches a rule.
colon=":"
redis_url="redis${colon}//${colon}Zq7vK2pLw9@cache-01:6379/0"
plain_db_url="postgres${colon}//powernode@localhost:5432/powernode_production"
db_url_with_pass="postgres${colon}//powernode${colon}Hq8vT2nKw@localhost:5432/powernode_production"
other_db_url="mysql${colon}//app${colon}Rt4mN8xQ2v@db-01:3306/app"

# fixture <arm> <rel> [source-file] -> path of a fresh copy (or empty file) under the arm's root
fixture() {
  local dst="$work/$1/$2"
  mkdir -p "$(dirname "$dst")"
  if [ -n "${3:-}" ]; then cp "$3" "$dst"; else : >"$dst"; fi
  printf '%s' "$dst"
}

# scan <arm> <want-exit> <want: sorted "rule<TAB>rel" lines, or ""> [rel]
scan() {
  local arm="$1" want_rc="$2" want="$3" root="$work/$1" rc=0 got src
  src="$root"; [ "${4:-}" = rel ] && src="."
  (cd "$root" && gitleaks detect --source="$src" --config="$CONFIG" --no-git --redact --no-banner \
    --report-format json --report-path "$work/$arm.json" >/dev/null 2>&1) || rc=$?
  got="$(jq -r --arg root "$root/" '.[] | "\(.RuleID)\t\(.File | ltrimstr($root))"' "$work/$arm.json" 2>/dev/null | sort)"
  if [ "$rc" -eq "$want_rc" ] && [ "$got" = "$want" ]; then
    echo "PASS  $arm"
  else
    echo "FAIL  $arm: exit $rc (want $want_rc)"
    echo "      got:  ${got:-<none>}" | sed '2,$s/^/            /'
    echo "      want: ${want:-<none>}" | sed '2,$s/^/            /'
    fail=1
  fi
}
one() { printf '%s\t%s' "$1" "$2"; }

# real / real-rel / extroot-rel: the files as they are scan clean in every path shape.
for arm in real real-rel; do
  fixture "$arm" "$RUBY_REL" "$SRC/$RUBY_REL" >/dev/null
  fixture "$arm" "$EXEC_REL" "$SRC/$EXEC_REL" >/dev/null
done
scan real 0 ""
scan real-rel 0 "" rel
fixture extroot-rel "$EXEC_EXT_REL" "$SRC/$EXEC_REL" >/dev/null
scan extroot-rel 0 "" rel

# outside: all three rules still fire where no allowlist applies.
f="$(fixture outside app/leak_probe.rb)"
{
  printf 'CACHE = "%s"\n' "$redis_url"
  printf 'DB = "%s"\n' "$other_db_url"
  printf '# curl https://api.internal/v1/things -H "X-API-Key: %s"\n' k9Qz7LmT2vR8wXa3
} >"$f"
scan outside 1 "$(printf 'curl-auth-header\tapp/leak_probe.rb\ndatabase-url\tapp/leak_probe.rb\nredis-url\tapp/leak_probe.rb')"

# redis-*: a credential anywhere in system_settings.rb fires, including right
# next to the password-shape examples its comments document.
f="$(fixture redis-new "$RUBY_REL" "$SRC/$RUBY_REL")"
printf '# %s\n' "$redis_url" >>"$f"
scan redis-new 1 "$(one redis-url "$RUBY_REL")"
f="$(fixture redis-line "$RUBY_REL" "$SRC/$RUBY_REL")"
sed -i "0,/p#w/s|p#w.*\$|&, \"$redis_url\"|" "$f"
scan redis-line 1 "$(one redis-url "$RUBY_REL")"
f="$(fixture redis-after "$RUBY_REL" "$SRC/$RUBY_REL")"
sed -i "0,/every one of those is a shape/{/every one of those is a shape/a\\
      FALLBACK_REDIS = \"$redis_url\"
}" "$f"
scan redis-after 1 "$(one redis-url "$RUBY_REL")"

# db-*: the rails-exec allowlist is its passwordless URL's exact match, not the file.
f="$(fixture db-pass "$EXEC_REL" "$SRC/$EXEC_REL")"
sed -i "s|$plain_db_url|$db_url_with_pass|" "$f"
scan db-pass 1 "$(one database-url "$EXEC_REL")"
f="$(fixture db-between "$EXEC_REL" "$SRC/$EXEC_REL")"
sed -i "/^export DATABASE_URL=/a export OTHER_DATABASE_URL=\"$other_db_url\"" "$f"
scan db-between 1 "$(one database-url "$EXEC_REL")"
f="$(fixture db-window "$EXEC_REL" "$SRC/$EXEC_REL")"
sed -i "0,/^    set +a\$/{/^    set +a\$/a\\
    export CACHE_DATABASE_URL=\"$other_db_url\"
}" "$f"
scan db-window 1 "$(one database-url "$EXEC_REL")"
f="$(fixture db-extroot "$EXEC_EXT_REL" "$SRC/$EXEC_REL")"
sed -i "s|$plain_db_url|$db_url_with_pass|" "$f"
scan db-extroot 1 "$(one database-url "$EXEC_EXT_REL")" rel
suffix_rel="extensions/other/$EXEC_EXT_REL"
fixture db-suffix "$suffix_rel" "$SRC/$EXEC_REL" >/dev/null
scan db-suffix 1 "$(one database-url "$suffix_rel")"

exit "$fail"
