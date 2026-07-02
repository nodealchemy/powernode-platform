#!/usr/bin/env bash
# doctor-gem-preactivation.sh — detect the recurring json-gem pre-activation boot hazard
# BEFORE it crashes boot.
#
# THE HAZARD (see memory: "Incident: json gem pre-activation breaks boot"):
# RubyGems pre-activates the NEWEST installed `json` gem before bundler runs. If a
# json version NEWER than the Gemfile.lock pin is installed (an orphan left behind by
# `gem install`/`gem update`, another app's bundle, etc.), boot crashes with
# "You have already activated json-X, but your Gemfile requires json-Y".
#
# REMEDIATION (the only correct one): uninstall the orphan —
#     gem uninstall json -v <orphan-version>
# NEVER bump the lock pin to match the orphan: that only moves the race to the next
# stray `gem install json`.
#
# WHAT THIS CHECKS: for each app lockfile (server/Gemfile.lock, worker/Gemfile.lock,
# and server/Gemfile.private.lock when present), compares the pinned json version
# against the locally installed json gem versions and FAILS (exit 1) when any
# installed, non-default version is NEWER than the pin. Default (bundled-with-Ruby)
# json is reported but not failed on — it cannot be uninstalled and bundler can
# shadow it.
#
# Usage:
#   scripts/doctor-gem-preactivation.sh              # check the real gemset/locks
#   scripts/doctor-gem-preactivation.sh --self-test  # prove fire + pass paths with fakes
#
# Test/override seams (so the failure path is testable without mutating the gemset):
#   DOCTOR_GEM_LIST_CMD   command whose stdout mimics `gem list -e json --local`
#                         (a line like: json (2.20.0, 2.19.9, default: 2.6.3))
#   DOCTOR_LOCKFILES      space-separated lockfile paths to check instead of the
#                         default set (relative paths resolve against the repo root)
#
# Exit codes: 0 = healthy (or nothing to check), 1 = orphan detected, 2 = usage/self-test failure.

set -euo pipefail

if [ -t 1 ]; then C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'; else C_OK=; C_WARN=; C_ERR=; C_DIM=; C_RST=; fi
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_RST" "$*"; }
fail() { printf '  %s✗%s %s\n' "$C_ERR" "$C_RST" "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

GEM_NAME="json"

# ---------- helpers ----------

# newest installed non-default version of $GEM_NAME, plus the full list, from the
# `gem list -e json --local` output line: json (2.20.0, 2.19.9, default: 2.6.3)
installed_versions() {
  local cmd="${DOCTOR_GEM_LIST_CMD:-gem list -e $GEM_NAME --local}"
  # rvm/rdoc noise goes to stderr; only stdout is parsed
  local line
  line="$(eval "$cmd" 2>/dev/null | grep -E "^${GEM_NAME} \(" | head -1 || true)"
  [ -n "$line" ] || return 0
  # strip "json (" and ")", split on ", ", drop "default: X" entries
  echo "$line" | sed -E "s/^${GEM_NAME} \((.*)\)$/\1/" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^default:' | grep -v '^$' || true
}

# pinned version of $GEM_NAME from a Gemfile.lock (exact "    json (X.Y.Z)" spec line)
locked_version() {
  local lockfile="$1"
  grep -E "^    ${GEM_NAME} \([0-9][0-9.]*\)$" "$lockfile" | head -1 | sed -E "s/^    ${GEM_NAME} \(([0-9.]+)\)$/\1/" || true
}

# version_gt A B → true if A > B (GNU sort -V)
version_gt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

# ---------- core check ----------

run_check() {
  local lockfiles=()
  if [ -n "${DOCTOR_LOCKFILES:-}" ]; then
    # shellcheck disable=SC2206 # intentional word-splitting of the override list
    lockfiles=(${DOCTOR_LOCKFILES})
  else
    lockfiles=(server/Gemfile.lock worker/Gemfile.lock server/Gemfile.private.lock)
  fi

  local exit_code=0 checked=0
  local installed
  installed="$(installed_versions)"

  if [ -z "$installed" ]; then
    warn "no locally installed '$GEM_NAME' gem versions found — nothing to compare (is 'gem' on PATH?)"
    return 0
  fi

  local lf abs pin v newest_orphan
  for lf in "${lockfiles[@]}"; do
    case "$lf" in /*) abs="$lf" ;; *) abs="$PROJECT_ROOT/$lf" ;; esac
    [ -f "$abs" ] || { printf '  %s·%s %s (absent — skipped)\n' "$C_DIM" "$C_RST" "$lf"; continue; }
    pin="$(locked_version "$abs")"
    if [ -z "$pin" ]; then
      warn "$lf: no '$GEM_NAME' pin found — skipped"
      continue
    fi
    checked=$((checked + 1))
    newest_orphan=""
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      if version_gt "$v" "$pin"; then
        if [ -z "$newest_orphan" ] || version_gt "$v" "$newest_orphan"; then newest_orphan="$v"; fi
      fi
    done <<< "$installed"
    if [ -n "$newest_orphan" ]; then
      fail "$lf pins $GEM_NAME $pin but a NEWER $GEM_NAME $newest_orphan is installed — RubyGems will pre-activate it and CRASH boot (\"already activated $GEM_NAME-$newest_orphan\")"
      exit_code=1
    else
      ok "$lf: $GEM_NAME pin $pin is the newest installed version"
    fi
  done

  if [ $exit_code -ne 0 ]; then
    echo ""
    echo -e "${C_ERR}REMEDIATION — remove the orphan gem version(s):${C_RST}"
    # every distinct installed version newer than ANY failing pin gets an uninstall line
    local orphan_cmds=""
    for lf in "${lockfiles[@]}"; do
      case "$lf" in /*) abs="$lf" ;; *) abs="$PROJECT_ROOT/$lf" ;; esac
      [ -f "$abs" ] || continue
      pin="$(locked_version "$abs")"
      [ -n "$pin" ] || continue
      while IFS= read -r v; do
        [ -n "$v" ] || continue
        if version_gt "$v" "$pin"; then
          orphan_cmds="${orphan_cmds}    gem uninstall $GEM_NAME -v $v"$'\n'
        fi
      done <<< "$installed"
    done
    printf '%s' "$orphan_cmds" | sort -u
    echo ""
    echo -e "  ${C_WARN}Do NOT bump the Gemfile.lock pin to match — that only moves the race.${C_RST}"
    echo -e "  ${C_DIM}(memory: incident-json-gem-preactivation-boot)${C_RST}"
  elif [ $checked -eq 0 ]; then
    warn "no lockfiles with a '$GEM_NAME' pin were found — nothing checked"
  fi

  return $exit_code
}

# ---------- self-test ----------

self_test() {
  local tmp rc
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064 # expand NOW: tmp is function-local, gone at EXIT time
  trap "rm -rf '$tmp'" EXIT

  # a minimal lockfile pinning json 2.19.9
  cat > "$tmp/Gemfile.lock" <<'EOF'
GEM
  remote: https://rubygems.org/
  specs:
    json (2.19.9)
    json-schema (6.2.0)

PLATFORMS
  ruby

DEPENDENCIES
  json
EOF

  local failures=0

  echo "self-test 1: FIRE — orphan 2.20.0 newer than pin 2.19.9 must fail with remediation"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="echo 'json (2.20.0, 2.19.9, default: 2.6.3)'" \
         DOCTOR_LOCKFILES="$tmp/Gemfile.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 1 ] && echo "$out" | grep -q "gem uninstall json -v 2.20.0"; then
    ok "fired: exit 1 + printed 'gem uninstall json -v 2.20.0'"
  else
    fail "expected exit 1 + remediation, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  echo "self-test 2: PASS — pin 2.19.9 is the newest installed, must exit 0"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="echo 'json (2.19.9, 2.18.0, default: 2.6.3)'" \
         DOCTOR_LOCKFILES="$tmp/Gemfile.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    ok "passed: exit 0"
  else
    fail "expected exit 0, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  echo "self-test 3: default-gem only — an old default gem must NOT fire"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="echo 'json (2.19.9, default: 2.6.3)'" \
         DOCTOR_LOCKFILES="$tmp/Gemfile.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    ok "passed: default gem ignored, exit 0"
  else
    fail "expected exit 0, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  echo "self-test 4: absent lockfile — must skip cleanly, exit 0"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="echo 'json (2.19.9)'" \
         DOCTOR_LOCKFILES="$tmp/does-not-exist.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    ok "passed: absent lock skipped, exit 0"
  else
    fail "expected exit 0, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  if [ $failures -eq 0 ]; then
    echo -e "${C_OK}self-test: all 4 cases passed${C_RST}"
    return 0
  fi
  echo -e "${C_ERR}self-test: $failures case(s) failed${C_RST}"
  return 2
}

# ---------- entrypoint ----------

case "${1:-}" in
  --self-test) self_test ;;
  -h|--help)
    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  "")
    echo "Gem pre-activation doctor ($GEM_NAME vs lockfile pins)"
    run_check
    ;;
  *)
    echo "unknown option: $1 (use --self-test or --help)" >&2
    exit 2
    ;;
esac
