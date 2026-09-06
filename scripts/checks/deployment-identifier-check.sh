#!/usr/bin/env bash
# deployment-identifier-check.sh — deployment-local identifiers must not ship in git.
# =============================================================================
# WHAT THIS EXISTS FOR
#
# Powernode is a platform other people deploy. THIS deployment's hostnames,
# internal IP ranges, VM ids, operator mailboxes and similar facts are irrelevant
# to every other deployment and are a gratuitous disclosure on the public mirror.
# Their home is the deployment's OWN platform knowledge store (tag
# `deployment-*`, recalled MCP-first — see
# docs/contributing/conventions/deployment-knowledge.md), never a tracked file.
#
# This script is the model-agnostic scan (non-Claude executors run the scan,
# not the hook). .claude/hooks/deployment-identifier-check.sh applies the
# identical rule to ONE file at edit time by calling this script with --file.
#
# THE RULE
#
#   No git-TRACKED file in core or in any PUBLIC extension submodule may match
#   any identifier pattern listed in the deployment's identifier list.
#
# THE LIST — AND WHY THE GUARD DOES NOT CONTAIN IT
#
#   .claude/hooks/deployment-identifiers.local.txt   (gitignored, per deployment)
#
# One POSIX extended regex per line; blank lines and `#` comments are ignored.
# A guard against name-leakage must not itself contain the names: a committed
# denylist in a public repo would BE the leak it guards against (platform
# learning 019fdf18). So the list is deployment-local, and when it is absent the
# check is a no-op PASS — a public clone has no deployment to protect yet.
# Whoever operates the deployment writes the list; it is the ONLY place the
# private identifiers appear in the working tree, and git never sees it.
#
# SCOPE
#
#   * core: `git ls-files` at the repo root (tracked files only — a gitignored
#     file such as CLAUDE.local.md or docs/operations/local/ is exactly where
#     such facts are allowed to live locally, so it is never a hit).
#   * every PUBLIC extension: `git -C extensions/<slug> ls-files` — each
#     extension is its own repo and is published on its own.
#   * extensions/private/* is skipped: not published, not this guard's concern.
#   * Binary files are skipped (grep -I).
#
# Usage: bash scripts/checks/deployment-identifier-check.sh [--list | --file <path>]
#   (no flag) prints the COUNT of offending tracked files (0 == clean / no list)
#   --list    prints "<repo-relative-path>:<line>:<matched text>" per hit
#   --file    checks ONE file (any path); prints its "<line>:<text>" hits and
#             exits 2 when there are any, 0 otherwise. Fails OPEN (exit 0) when
#             the list is absent or the file is gitignored in its own repo.
#
# Environment: DEPLOYMENT_ID_ROOT overrides the repo root (specs point it at a
# fixture tree); DEPLOYMENT_ID_LIST overrides the list path (default
# $ROOT/.claude/hooks/deployment-identifiers.local.txt).
#
# Always exits 0 in count/list mode so a caller under `set -e` never dies here;
# the COUNT is the verdict.
# =============================================================================
set -u

MODE="${1:-}"
FILE_ARG="${2:-}"
ROOT="${DEPLOYMENT_ID_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LIST="${DEPLOYMENT_ID_LIST:-$ROOT/.claude/hooks/deployment-identifiers.local.txt}"

finish_clean() {
  case "$MODE" in
    --list|--file) ;;
    *) echo 0 ;;
  esac
  exit 0
}

# Load patterns: strip comments/blank lines, join with `|`. Each line is one
# extended regex; a line is wrapped in a group so alternation cannot bleed.
load_patterns() {
  local line combined=""
  [ -r "$LIST" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$line" ] || continue
    combined+="${combined:+|}(${line})"
  done < "$LIST"
  [ -n "$combined" ] || return 1
  printf '%s' "$combined"
}

PATTERN="$(load_patterns)" || finish_clean

# --- single-file mode (edit-time hook) --------------------------------------
if [ "$MODE" = "--file" ]; then
  [ -n "$FILE_ARG" ] && [ -f "$FILE_ARG" ] || exit 0
  # Never flag the list itself, and never flag a file git will not track: the
  # ignore status is resolved in the file's OWN toplevel so a submodule path is
  # judged by the submodule's .gitignore, not the parent's.
  [ "$(cd "$(dirname "$FILE_ARG")" && pwd)/$(basename "$FILE_ARG")" = "$LIST" ] && exit 0
  top="$(git -C "$(dirname "$FILE_ARG")" rev-parse --show-toplevel 2>/dev/null)" || exit 0
  git -C "$top" check-ignore -q "$FILE_ARG" 2>/dev/null && exit 0
  hits="$(grep -nIE "$PATTERN" "$FILE_ARG" 2>/dev/null || true)"
  [ -z "$hits" ] && exit 0
  printf '%s\n' "$hits"
  exit 2
fi

# --- tree mode (scan) ---------------------------------------------------------
cd "$ROOT" 2>/dev/null || finish_clean
git rev-parse --show-toplevel >/dev/null 2>&1 || finish_clean

# Emits "<repo-relative-path>:<line>:<text>" for every hit in ONE repo.
# $1 = directory of the repo, $2 = prefix to prepend to paths ("" for core).
scan_repo() {
  local dir="$1" prefix="$2"
  ( cd "$dir" 2>/dev/null || exit 0
    git ls-files -z 2>/dev/null \
      | xargs -0 -r grep -nIHE "$PATTERN" -- 2>/dev/null \
      | sed -E "s#^#${prefix}#" ) || true
}

hits="$(scan_repo "$ROOT" "")"
shopt -s nullglob
for d in "$ROOT"/extensions/*/; do
  slug="$(basename "$d")"
  [ "$slug" = "private" ] && continue
  # Only a checked-out git repo (submodule or plain clone) can be published.
  git -C "$d" rev-parse --show-toplevel >/dev/null 2>&1 || continue
  more="$(scan_repo "$d" "extensions/${slug}/")"
  [ -n "$more" ] && hits+="${hits:+$'\n'}${more}"
done
shopt -u nullglob

if [ "$MODE" = "--list" ]; then
  [ -n "$hits" ] && printf '%s\n' "$hits"
  exit 0
fi

if [ -z "$hits" ]; then
  echo 0
else
  printf '%s\n' "$hits" | cut -d: -f1 | sort -u | grep -c .
fi
exit 0
