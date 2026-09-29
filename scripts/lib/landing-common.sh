#!/usr/bin/env bash
# landing-common.sh — shared helpers for the dev-improve landing scripts
# (verify-hub-deploy.sh, land.sh, wt.sh, pre-critic-gate.sh). Source it; do not run it.
#
# Deployment-local facts (hosts, unit names, access commands, endpoints) NEVER live in a
# tracked file. They come from the environment or from a gitignored local config, found in
# this order:
#   1. $POWERNODE_LOCAL_CONFIG                      (explicit path)
#   2. <this worktree>/scripts/local/landing.env
#   3. <main checkout>/scripts/local/landing.env    (a worktree has no gitignored files of its own)
# The documented, placeholder-only template is scripts/landing.env.example.

if [ -t 2 ]; then LC_ERR=$'\033[31m'; LC_INFO=$'\033[36m'; LC_RST=$'\033[0m'; else LC_ERR=; LC_INFO=; LC_RST=; fi
lc_info() { printf '%s==>%s %s\n' "$LC_INFO" "$LC_RST" "$*" >&2; }
lc_die()  { printf '%serror:%s %s\n' "$LC_ERR" "$LC_RST" "$*" >&2; exit "${LC_DIE_CODE:-1}"; }

# Absolute path of the repo this script lives in (worktree or main).
lc_repo_root() {
  local here; here="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
  git -C "$here" rev-parse --show-toplevel
}

# Absolute path of the MAIN checkout (owner of the shared object store and gitignored config).
lc_main_root() {
  local root="$1" common
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)" || return 1
  dirname "$common"
}

# Source the local config if one exists. Returns 0 either way; the caller decides which
# variables it requires (lc_require). A variable already set in the environment WINS over the
# file (so a one-off `HUB_EXEC_CMD=... scripts/x.sh` works). POWERNODE_LOCAL_CONFIG=none loads nothing.
lc_load_config() {
  local root="$1" main cfg name saved=() names=()
  LC_CONFIG_FILE=""
  [ "${POWERNODE_LOCAL_CONFIG:-}" = "none" ] && return 0
  main="$(lc_main_root "$root")" || main="$root"
  for cfg in "${POWERNODE_LOCAL_CONFIG:-}" "$root/scripts/local/landing.env" "$main/scripts/local/landing.env"; do
    [ -n "$cfg" ] && [ -f "$cfg" ] || continue
    while IFS= read -r name; do
      if [ "${!name+set}" = set ]; then names+=("$name"); saved+=("${!name}"); fi
    done < <(command grep -oE '^(export +)?[A-Za-z_][A-Za-z0-9_]*=' "$cfg" | sed -E 's/^export +//; s/=$//')
    # shellcheck disable=SC1090
    set -a; . "$cfg"; set +a
    local i
    for i in "${!names[@]}"; do printf -v "${names[$i]}" '%s' "${saved[$i]}"; export "${names[$i]}"; done
    LC_CONFIG_FILE="$cfg"
    return 0
  done
  return 0
}

# Fail (exit 2 = configuration problem) naming every missing variable at once.
lc_require() {
  local missing=() v
  for v in "$@"; do [ -n "${!v:-}" ] || missing+=("$v"); done
  [ "${#missing[@]}" -eq 0 ] && return 0
  LC_DIE_CODE=2 lc_die "missing local configuration: ${missing[*]} (set in the environment or in ${LC_CONFIG_FILE:-scripts/local/landing.env}; see scripts/landing.env.example)"
}

# A git sha as typed by a human: 7-40 hex.
lc_valid_sha() { [[ "${1:-}" =~ ^[0-9a-fA-F]{7,40}$ ]]; }
