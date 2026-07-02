#!/usr/bin/env bash
# doctor-gem-preactivation.sh — detect the recurring gem pre-activation boot hazard
# BEFORE it crashes boot.
#
# THE HAZARD (see memory: "Incident: json gem pre-activation breaks boot"):
# RubyGems pre-activates the NEWEST installed version of boot-critical gems (json,
# rdoc, ...) before bundler runs. If a version NEWER than the Gemfile.lock pin is
# installed (an orphan left behind by `gem install`/`gem update`, a looser private
# bundle resolution, another app's bundle, etc.), boot crashes with
# "You have already activated <gem>-X, but your Gemfile requires <gem>-Y"
# (or, for rdoc, floods every gem invocation with duplicate-constant warnings).
#
# REMEDIATION (the only correct one): uninstall the orphan —
#     gem uninstall <gem> -v <orphan-version>
# NEVER bump the lock pin to match the orphan: that only moves the race to the next
# stray `gem install`. server/Gemfile.private pins these gems in lockstep with the
# public Gemfile.lock so private-mode `bundle install` cannot recreate the orphan.
#
# WHAT THIS CHECKS: for each boot-critical gem (default: json rdoc) and each app
# lockfile (server/Gemfile.lock, worker/Gemfile.lock, and server/Gemfile.private.lock
# when present), compares the pinned version against the locally installed versions
# and FAILS (exit 1) when any installed, non-default version is NEWER than the pin.
# Default (bundled-with-Ruby) gems are ignored — they cannot be uninstalled and
# bundler can shadow them. A gem with no pin in a given lockfile is skipped.
#
# Usage:
#   scripts/doctor-gem-preactivation.sh              # check the real gemset/locks
#   scripts/doctor-gem-preactivation.sh --self-test  # prove fire + pass paths with fakes
#
# Test/override seams (so the failure path is testable without mutating the gemset):
#   DOCTOR_GEMS           space-separated gem names to check (default: "json rdoc")
#   DOCTOR_GEM_LIST_CMD   command whose stdout mimics `gem list --local` for the
#                         checked gems — one line per gem, like:
#                           json (2.20.0, 2.19.9, default: 2.6.3)
#                           rdoc (8.0.0, 7.2.0, default: 6.5.1.1)
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

# Boot-critical gems RubyGems pre-activates before bundler runs. Override via
# DOCTOR_GEMS="json rdoc ..." (space-separated).
GEMS="${DOCTOR_GEMS:-json rdoc}"

# ---------- helpers ----------

# installed non-default versions of gem $1, one per line, from the
# `gem list --local` output line: <gem> (2.20.0, 2.19.9, default: 2.6.3)
installed_versions() {
  local gem_name="$1"
  local cmd="${DOCTOR_GEM_LIST_CMD:-gem list -e $gem_name --local}"
  # rvm/rdoc noise goes to stderr; only stdout is parsed
  local line
  line="$(eval "$cmd" 2>/dev/null | grep -E "^${gem_name} \(" | head -1 || true)"
  [ -n "$line" ] || return 0
  # strip "<gem> (" and ")", split on ", ", drop "default: X" entries
  echo "$line" | sed -E "s/^${gem_name} \((.*)\)$/\1/" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^default:' | grep -v '^$' || true
}

# pinned version of gem $2 from Gemfile.lock $1 (exact "    <gem> (X.Y.Z)" spec line)
locked_version() {
  local lockfile="$1" gem_name="$2"
  grep -E "^    ${gem_name} \([0-9][0-9.]*\)$" "$lockfile" | head -1 | sed -E "s/^    ${gem_name} \(([0-9.]+)\)$/\1/" || true
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

  local exit_code=0 checked=0 any_installed=0
  local orphan_cmds=""

  local g installed lf abs pin v newest_orphan
  for g in $GEMS; do
    installed="$(installed_versions "$g")"
    if [ -z "$installed" ]; then
      printf '  %s·%s no locally installed non-default '\''%s'\'' versions — nothing to compare\n' "$C_DIM" "$C_RST" "$g"
      continue
    fi
    any_installed=1

    for lf in "${lockfiles[@]}"; do
      case "$lf" in /*) abs="$lf" ;; *) abs="$PROJECT_ROOT/$lf" ;; esac
      [ -f "$abs" ] || { printf '  %s·%s %s (absent — skipped)\n' "$C_DIM" "$C_RST" "$lf"; continue; }
      pin="$(locked_version "$abs" "$g")"
      if [ -z "$pin" ]; then
        printf '  %s·%s %s: no '\''%s'\'' pin — skipped\n' "$C_DIM" "$C_RST" "$lf" "$g"
        continue
      fi
      checked=$((checked + 1))
      newest_orphan=""
      while IFS= read -r v; do
        [ -n "$v" ] || continue
        if version_gt "$v" "$pin"; then
          orphan_cmds="${orphan_cmds}    gem uninstall $g -v $v"$'\n'
          if [ -z "$newest_orphan" ] || version_gt "$v" "$newest_orphan"; then newest_orphan="$v"; fi
        fi
      done <<< "$installed"
      if [ -n "$newest_orphan" ]; then
        fail "$lf pins $g $pin but a NEWER $g $newest_orphan is installed — RubyGems will pre-activate it and CRASH boot (\"already activated $g-$newest_orphan\")"
        exit_code=1
      else
        ok "$lf: $g pin $pin is the newest installed version"
      fi
    done
  done

  if [ $any_installed -eq 0 ]; then
    warn "no locally installed versions found for any checked gem ($GEMS) — nothing to compare (is 'gem' on PATH?)"
    return 0
  fi

  if [ $exit_code -ne 0 ]; then
    echo ""
    echo -e "${C_ERR}REMEDIATION — remove the orphan gem version(s):${C_RST}"
    printf '%s' "$orphan_cmds" | sort -u
    echo ""
    echo -e "  ${C_WARN}Do NOT bump the Gemfile.lock pin to match — that only moves the race.${C_RST}"
    echo -e "  ${C_DIM}(memory: incident-json-gem-preactivation-boot)${C_RST}"
  elif [ $checked -eq 0 ]; then
    warn "no lockfiles with a pin for any checked gem ($GEMS) were found — nothing checked"
  fi

  return $exit_code
}

# ---------- self-test ----------

self_test() {
  local tmp rc
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064 # expand NOW: tmp is function-local, gone at EXIT time
  trap "rm -rf '$tmp'" EXIT

  # a minimal lockfile pinning json 2.19.9 and rdoc 7.2.0
  cat > "$tmp/Gemfile.lock" <<'EOF'
GEM
  remote: https://rubygems.org/
  specs:
    json (2.19.9)
    json-schema (6.2.0)
    rdoc (7.2.0)

PLATFORMS
  ruby

DEPENDENCIES
  json
  rdoc
EOF

  # a lockfile that pins only json (no rdoc) — a gem absent from a lock is skipped
  cat > "$tmp/json-only.lock" <<'EOF'
GEM
  remote: https://rubygems.org/
  specs:
    json (2.19.9)

PLATFORMS
  ruby

DEPENDENCIES
  json
EOF

  local failures=0

  echo "self-test 1: MULTI-GEM FIRE — json 2.20.0 AND rdoc 8.0.0 orphans must both fail with remediation"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="printf 'json (2.20.0, 2.19.9, default: 2.6.3)\nrdoc (8.0.0, 7.2.0, default: 6.5.1.1)\n'" \
         DOCTOR_LOCKFILES="$tmp/Gemfile.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 1 ] && echo "$out" | grep -q "gem uninstall json -v 2.20.0" \
                   && echo "$out" | grep -q "gem uninstall rdoc -v 8.0.0"; then
    ok "fired: exit 1 + remediation for BOTH json 2.20.0 and rdoc 8.0.0"
  else
    fail "expected exit 1 + both remediations, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  echo "self-test 2: SINGLE-GEM FIRE — only the rdoc orphan fires; json remediation must NOT appear"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="printf 'json (2.19.9, default: 2.6.3)\nrdoc (8.0.0, 7.2.0, default: 6.5.1.1)\n'" \
         DOCTOR_LOCKFILES="$tmp/Gemfile.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 1 ] && echo "$out" | grep -q "gem uninstall rdoc -v 8.0.0" \
                   && ! echo "$out" | grep -q "gem uninstall json"; then
    ok "fired: exit 1 + rdoc-only remediation"
  else
    fail "expected exit 1 + rdoc-only remediation, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  echo "self-test 3: PASS — every pin is the newest installed version, must exit 0"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="printf 'json (2.19.9, 2.18.0, default: 2.6.3)\nrdoc (7.2.0, 7.1.0, default: 6.5.1.1)\n'" \
         DOCTOR_LOCKFILES="$tmp/Gemfile.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    ok "passed: exit 0"
  else
    fail "expected exit 0, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  echo "self-test 4: default-gem only — old default gems must NOT fire"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="printf 'json (2.19.9, default: 2.6.3)\nrdoc (7.2.0, default: 6.5.1.1)\n'" \
         DOCTOR_LOCKFILES="$tmp/Gemfile.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    ok "passed: default gems ignored, exit 0"
  else
    fail "expected exit 0, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  echo "self-test 5: absent lockfile — must skip cleanly, exit 0"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="printf 'json (2.19.9)\nrdoc (7.2.0)\n'" \
         DOCTOR_LOCKFILES="$tmp/does-not-exist.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    ok "passed: absent lock skipped, exit 0"
  else
    fail "expected exit 0, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  echo "self-test 6: gem absent from lockfile — no rdoc pin means rdoc is skipped, not fired"
  set +e
  out="$(DOCTOR_GEM_LIST_CMD="printf 'json (2.19.9, default: 2.6.3)\nrdoc (8.0.0, 7.2.0, default: 6.5.1.1)\n'" \
         DOCTOR_LOCKFILES="$tmp/json-only.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    ok "passed: unpinned gem skipped, exit 0"
  else
    fail "expected exit 0, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  echo "self-test 7: DOCTOR_GEMS override — narrowing to json ignores the rdoc orphan"
  set +e
  out="$(DOCTOR_GEMS="json" \
         DOCTOR_GEM_LIST_CMD="printf 'json (2.19.9, default: 2.6.3)\nrdoc (8.0.0, 7.2.0, default: 6.5.1.1)\n'" \
         DOCTOR_LOCKFILES="$tmp/Gemfile.lock" "$0" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    ok "passed: DOCTOR_GEMS=json ignores rdoc, exit 0"
  else
    fail "expected exit 0, got exit $rc; output:"; echo "$out"
    failures=$((failures + 1))
  fi

  if [ $failures -eq 0 ]; then
    echo -e "${C_OK}self-test: all 7 cases passed${C_RST}"
    return 0
  fi
  echo -e "${C_ERR}self-test: $failures case(s) failed${C_RST}"
  return 2
}

# ---------- entrypoint ----------

case "${1:-}" in
  --self-test) self_test ;;
  -h|--help)
    sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  "")
    echo "Gem pre-activation doctor ($GEMS vs lockfile pins)"
    run_check
    ;;
  *)
    echo "unknown option: $1 (use --self-test or --help)" >&2
    exit 2
    ;;
esac
