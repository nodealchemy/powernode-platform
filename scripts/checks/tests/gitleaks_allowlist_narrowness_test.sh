#!/bin/bash
# Red/green test for the per-rule allowlists in .gitleaks.toml (IMP-35fee69707e9):
# the scan the gate runs must be clean on the files those allowlists cover, and
# the rules must still fire everywhere else -- including inside those same files.
#
# Each arm scans a throwaway fixture tree with the config under test, the way
# scripts/validate.sh step 4 does (--no-git, absolute --source, --redact), and
# asserts BOTH the exit code and exactly which rule fired in which file, so an
# arm cannot pass by failing for a different cause.
#
#   real        verbatim copies of the allowlisted files       -> exit 0
#   extroot     the same, rooted at the extension checkout the
#               pre-critic gate's ext-gitleaks scan uses        -> exit 0
#   outside     credentialed redis URL, database URL and curl
#               auth header in a file no allowlist names        -> exit 1, one of each rule
#   redis-new   a different credentialed redis URL appended to
#               the allowlisted Ruby file                        -> exit 1, redis-url there
#   redis-host  an allowlisted password shape on another host   -> exit 1, redis-url there
#   db-pass     a password added to the allowlisted DATABASE_URL -> exit 1, database-url there
#   db-between  a credentialed URL inserted between that URL and
#               the shell "$@" its match used to run to          -> exit 1, database-url there
#   db-extroot  db-pass, rooted at the extension checkout        -> exit 1, database-url there
#
# The fixture tree is created INSIDE the repo: gitleaks reports absolute paths
# for an absolute --source, so a tree under /tmp matches the tmp/ path
# allowlist and every arm would report clean. Credentialed strings are built
# at run time so this file is not itself a finding.
# GITLEAKS_CONFIG overrides the config under test (for red-first runs).
#
# Usage: bash scripts/checks/tests/gitleaks_allowlist_narrowness_test.sh
# Exits 0 if all assertions pass, 1 otherwise (2 if gitleaks is not installed).
set -u

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1
CONFIG="${GITLEAKS_CONFIG:-$REPO/.gitleaks.toml}"
command -v gitleaks >/dev/null 2>&1 || { echo "gitleaks is not installed; nothing was tested"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is not installed"; exit 2; }

RUBY_REL="server/app/services/admin/system_settings.rb"
EXEC_EXT_REL="modules/powernode-hub-backend/rootfs/usr/local/bin/powernode-rails-exec"
EXEC_REL="extensions/system/$EXEC_EXT_REL"
for f in "$RUBY_REL" "$EXEC_REL"; do
  [ -f "$REPO/$f" ] || { echo "missing $f (extension checkout not initialised?)"; exit 1; }
done

fail=0
work="$(mktemp -d "$REPO/.gitleaks-selftest.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT

# Credentialed shapes, assembled so no literal in this file matches a rule.
redis_url() { printf '%s://:%s@%s' redis "$1" "$2"; }
colon=":"
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

# scan <arm> <want-exit> <want: sorted "rule<TAB>rel" lines, or "">
scan() {
  local arm="$1" want_rc="$2" want="$3" root="$work/$1" rc=0 got
  gitleaks detect --source="$root" --config="$CONFIG" --no-git --redact --no-banner \
    --report-format json --report-path "$work/$arm.json" >/dev/null 2>&1 || rc=$?
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

# real / extroot: the allowlists cover the files as they are.
fixture real "$RUBY_REL" "$REPO/$RUBY_REL" >/dev/null
fixture real "$EXEC_REL" "$REPO/$EXEC_REL" >/dev/null
scan real 0 ""
fixture extroot "$EXEC_EXT_REL" "$REPO/$EXEC_REL" >/dev/null
scan extroot 0 ""

# outside: all three rules still fire where no allowlist applies.
f="$(fixture outside app/leak_probe.rb)"
{
  printf 'CACHE = "%s:6379/0"\n' "$(redis_url Zq7vK2pLw9 cache-01)"
  printf 'DB = "%s"\n' "$other_db_url"
  printf '# curl https://api.internal/v1/things -H "X-API-Key: %s"\n' k9Qz7LmT2vR8wXa3
} >"$f"
scan outside 1 "$(printf 'curl-auth-header\tapp/leak_probe.rb\ndatabase-url\tapp/leak_probe.rb\nredis-url\tapp/leak_probe.rb')"

# redis-new / redis-host: the Ruby file's allowlist is its documented shapes, not the file.
f="$(fixture redis-new "$RUBY_REL" "$REPO/$RUBY_REL")"
printf '# %s:6379/0\n' "$(redis_url Zq7vK2pLw9 cache-01)" >>"$f"
scan redis-new 1 "$(printf 'redis-url\t%s' "$RUBY_REL")"
f="$(fixture redis-host "$RUBY_REL" "$REPO/$RUBY_REL")"
printf '# %s:6379/0\n' "$(redis_url my/pass hostile-01)" >>"$f"
scan redis-host 1 "$(printf 'redis-url\t%s' "$RUBY_REL")"

# db-pass / db-between / db-extroot: the script's allowlist is its passwordless URL, not the file.
f="$(fixture db-pass "$EXEC_REL" "$REPO/$EXEC_REL")"
sed -i "s|$plain_db_url|$db_url_with_pass|" "$f"
scan db-pass 1 "$(printf 'database-url\t%s' "$EXEC_REL")"
f="$(fixture db-between "$EXEC_REL" "$REPO/$EXEC_REL")"
sed -i "/^export DATABASE_URL=/a export OTHER_DATABASE_URL=\"$other_db_url\"" "$f"
scan db-between 1 "$(printf 'database-url\t%s' "$EXEC_REL")"
f="$(fixture db-extroot "$EXEC_EXT_REL" "$REPO/$EXEC_REL")"
sed -i "s|$plain_db_url|$db_url_with_pass|" "$f"
scan db-extroot 1 "$(printf 'database-url\t%s' "$EXEC_EXT_REL")"

exit "$fail"
