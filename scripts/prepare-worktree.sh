#!/usr/bin/env bash
#
# prepare-worktree.sh — make a git worktree a faithful, runnable peer of the main checkout.
#
# A fresh `git worktree add` does NOT populate the extension submodules, does NOT
# include the remote-only private extensions, and does NOT bring the maintainer's
# gitignored runtime configs. The result: the bundle can't resolve (the public
# extension path-gems silently vanish from the lockfile) and Rails can't boot.
# This script fixes all of that, OFFLINE and idempotently:
#
#   1. PUBLIC extensions (tracked submodules): checked out from the main checkout's
#      LOCAL object store via `git worktree add` at the exact pinned commit — no
#      network, parent `git status` stays clean, and each is a real git checkout.
#   2. PRIVATE extensions (gitignored, extensions/private/*): COPIED from the main
#      checkout (files-only, excluding .git) — isolated and invisible to git.
#   3. CONFIGS: the gitignored runtime files (database.yml / master.key /
#      credentials.yml.enc / .env) are symlinked from the main checkout.
#   4. Verifies `bundle` resolves for server/ and worker/ (and the private bundle).
#
# It NEVER runs `git submodule sync`/`update` against the submodules — `sync`
# rewrites their remotes (dropping the private upstream; see CLAUDE.md), and
# `update` re-clones from the configured (possibly unreachable) remote instead of
# reusing what main already has. Private extensions are discovered dynamically
# from extensions/private/* — no extension is named here (stays public-safe).
#
# Usage:
#   scripts/prepare-worktree.sh <worktree-path>                  # prepare an EXISTING worktree
#   scripts/prepare-worktree.sh <worktree-path> --create [base]  # create it first, then prepare
#                                                                #   branch = basename(path), off <base> (default: main's current branch)
#   scripts/prepare-worktree.sh <worktree-path> --remove         # tear down (nested ext worktrees + the worktree)
#
# Examples:
#   scripts/prepare-worktree.sh ~/worktrees/my-feature --create develop
#   scripts/prepare-worktree.sh ~/worktrees/my-feature           # re-sync an existing one
#   scripts/prepare-worktree.sh ~/worktrees/my-feature --remove  # clean teardown
#
# Safe to re-run. Run it from anywhere inside the repo (main checkout or a worktree).
# Extensions land DETACHED at the pinned commit (faithful + clean status). To work
# on a public extension, branch it: `git -C <worktree>/extensions/<name> switch -c <branch>`.

set -euo pipefail

# ---------- pretty output ----------
if [ -t 1 ]; then C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_INFO=$'\033[36m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'; else C_OK=; C_WARN=; C_ERR=; C_INFO=; C_DIM=; C_RST=; fi
info() { printf '%s==>%s %s\n' "$C_INFO" "$C_RST" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_RST" "$*"; }
skip() { printf '  %s·%s %s\n' "$C_DIM" "$C_RST" "$*"; }
die()  { printf '%serror:%s %s\n' "$C_ERR" "$C_RST" "$*" >&2; exit 1; }

case "${1:-}" in
  -h|--help|"") sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# ---------- args ----------
TARGET_ARG="$1"; shift
MODE="prepare"; BASE=""
case "${1:-}" in
  --create) MODE="create"; BASE="${2:-}" ;;
  --remove) MODE="remove" ;;
  "") ;;
  *) die "unknown option: $1" ;;
esac

# ---------- locate the MAIN checkout (source of truth for private exts + secrets) ----------
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_GIT="$(git -C "$SELF_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die "not inside a git repository"
MAIN="$(dirname "$COMMON_GIT")"
[ -d "$MAIN/extensions" ] || die "main checkout not found at: $MAIN"

# submodule paths declared in the tracked .gitmodules (public extensions)
mapfile -t SUBPATHS < <(git -C "$MAIN" config -f "$MAIN/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')

# ---------- teardown ----------
if [ "$MODE" = "remove" ]; then
  [ -d "$TARGET_ARG" ] || die "nothing to remove at: $TARGET_ARG"
  TARGET="$(cd "$TARGET_ARG" && pwd)"
  info "removing worktree ${C_DIM}$TARGET${C_RST}"
  for p in "${SUBPATHS[@]}"; do
    if [ -e "$TARGET/$p" ] && git -C "$TARGET/$p" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git -C "$MAIN/$p" worktree remove --force "$TARGET/$p" 2>/dev/null && ok "removed extension worktree $p" || warn "could not remove $p"
    fi
  done
  git -C "$MAIN" worktree remove --force "$TARGET" 2>/dev/null && ok "removed $TARGET" || { rm -rf "$TARGET"; warn "force-removed dir (was not a registered worktree)"; }
  git -C "$MAIN" worktree prune
  for p in "${SUBPATHS[@]}"; do git -C "$MAIN/$p" worktree prune 2>/dev/null || true; done
  info "${C_OK}done${C_RST}"
  exit 0
fi

info "main checkout: ${C_DIM}$MAIN${C_RST}"

# ---------- create the worktree if asked ----------
if [ "$MODE" = "create" ]; then
  [ -e "$TARGET_ARG" ] && die "path already exists: $TARGET_ARG"
  base_ref="${BASE:-$(git -C "$MAIN" symbolic-ref --short HEAD)}"
  branch="$(basename "$TARGET_ARG")"
  info "creating worktree '$branch' off '$base_ref'"
  git -C "$MAIN" worktree add -b "$branch" "$TARGET_ARG" "$base_ref"
fi

[ -d "$TARGET_ARG" ] || die "worktree path does not exist: $TARGET_ARG (use --create to make it)"
TARGET="$(cd "$TARGET_ARG" && pwd)"
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git worktree: $TARGET"
[ "$TARGET" = "$MAIN" ] && die "refusing to run against the main checkout itself"
info "preparing worktree: ${C_DIM}$TARGET${C_RST}"

# ---------- 1. public extensions: offline `git worktree add` at the pinned commit ----------
info "public extension submodules (offline, from main's object store)"
if [ "${#SUBPATHS[@]}" -eq 0 ]; then
  skip "no submodules declared in .gitmodules"
else
  for path in "${SUBPATHS[@]}"; do
    src="$MAIN/$path"; tgt="$TARGET/$path"
    [ -d "$src" ] || { warn "$path: not present in main checkout — skipping"; continue; }
    pinned="$(git -C "$TARGET" ls-tree -d HEAD "$path" 2>/dev/null | awk '{print $3}')"
    [ -n "$pinned" ] || { warn "$path: no gitlink recorded in HEAD — skipping"; continue; }
    if [ -n "$(ls -A "$tgt" 2>/dev/null)" ]; then
      if git -C "$tgt" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$tgt" checkout --quiet --detach "$pinned" 2>/dev/null || true
        ok "$path (present @ $(git -C "$tgt" rev-parse --short HEAD))"
      else
        warn "$path: non-empty and not a git checkout — leaving as-is"
      fi
      continue
    fi
    rmdir "$tgt" 2>/dev/null || true
    if git -C "$src" worktree add --detach --force "$tgt" "$pinned" >/dev/null 2>&1; then
      ok "$path @ ${pinned:0:7}"
    else
      warn "$path: worktree add failed (is $pinned in main's module object store?)"
    fi
  done
fi

# ---------- 2. private extensions: files-only copy (isolated; gitignored) ----------
info "private extensions (copied from main)"
if [ -d "$MAIN/extensions/private" ] && [ -n "$(ls -A "$MAIN/extensions/private" 2>/dev/null)" ]; then
  mkdir -p "$TARGET/extensions/private"
  for d in "$MAIN"/extensions/private/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"; dst="$TARGET/extensions/private/$name"
    if [ -e "$dst" ] || [ -L "$dst" ]; then skip "extensions/private/$name (already present)"; continue; fi
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --exclude='.git' --exclude='tmp/' --exclude='log/' --exclude='node_modules/' "${d%/}/" "$dst/"
    else
      cp -a "${d%/}" "$dst"; rm -rf "$dst/.git"
    fi
    ok "extensions/private/$name (copied, files-only)"
  done
else
  skip "no private extensions in main checkout (core mode)"
fi

# ---------- 3. gitignored runtime configs (symlinked from main) ----------
info "runtime configs (symlinked from main)"
CONFIGS=(
  server/config/database.yml
  server/config/master.key
  server/config/credentials.yml.enc
  server/.env
  worker/.env
)
for rel in "${CONFIGS[@]}"; do
  src="$MAIN/$rel"; dst="$TARGET/$rel"
  [ -e "$src" ] || continue
  if [ -L "$dst" ]; then skip "$rel (already linked)"; continue; fi
  if [ -e "$dst" ]; then warn "$rel exists as a real file — leaving as-is"; continue; fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"; ok "$rel"
done

# ---------- 4. verify bundles resolve ----------
info "bundle resolution"
for app in server worker; do
  [ -f "$TARGET/$app/Gemfile" ] || continue
  if (cd "$TARGET/$app" && bundle check >/dev/null 2>&1); then
    ok "$app: bundle satisfied"
  else
    warn "$app: not satisfied — run 'cd $app && bundle install'"
  fi
done
if [ -f "$TARGET/server/Gemfile.private" ]; then
  if (cd "$TARGET/server" && BUNDLE_GEMFILE=Gemfile.private bundle check >/dev/null 2>&1); then
    ok "server private bundle: satisfied"
  else
    warn "server private bundle: run 'cd server && BUNDLE_GEMFILE=Gemfile.private bundle install' (its lock is gitignored; a fresh worktree has none)"
  fi
fi

info "${C_OK}worktree ready${C_RST}  ${C_DIM}$TARGET${C_RST}"
