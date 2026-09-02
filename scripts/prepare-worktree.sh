#!/usr/bin/env bash
#
# prepare-worktree.sh — make a git worktree a faithful, runnable peer of the main checkout.
#
# A fresh `git worktree add` does NOT populate the extension submodules, does NOT
# include the remote-only private extensions, does NOT bring the maintainer's
# gitignored runtime configs, and does NOT install JS deps. The result: the bundle
# can't resolve (the public extension path-gems silently vanish from the lockfile)
# and Rails can't boot, AND tsc/jest/vite can't run (no node_modules).
# This script fixes all of that, OFFLINE and idempotently:
#
#   1. PUBLIC extensions (tracked submodules): checked out from the main checkout's
#      LOCAL object store via `git worktree add` at the exact pinned commit — no
#      network, parent `git status` stays clean, and each is a real git checkout.
#   2. PRIVATE extensions (gitignored, extensions/private/*): COPIED from the main
#      checkout (files-only, excluding .git) — isolated and invisible to git.
#   3. CONFIGS: the gitignored runtime files (database.yml / master.key /
#      credentials.yml.enc / .env) are symlinked from the main checkout. The TEST
#      database is ALWAYS isolated per worktree (server/.env.test.local sets a unique
#      TEST_ENV_NUMBER → powernode_test_<worktree>) so concurrent worktrees never
#      clobber each other's test schema; dev/prod stay shared (use --isolated-db to
#      isolate those too).
#   4. JS DEPS: node_modules is symlinked from main for each JS package (gitignored,
#      so a fresh worktree has none) when its package.json matches main's; a diverged
#      manifest is left for `npm install` instead. Lets tsc/jest/vite run.
#   5. Verifies `bundle` resolves for server/ and worker/ (and the private bundle).
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

# set KEY=VALUE in an env file (replace existing line, else append)
env_upsert() {
  local file="$1" key="$2" val="$3"
  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    sed -E -i "s|^${key}=.*|${key}=${val}|" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

# symlink one gitignored config from main (shared key material); skip if already present
link_one() {
  local rel="$1" src="$MAIN/$1" dst="$TARGET/$1"
  [ -e "$src" ] || return 0
  [ -L "$dst" ] && { skip "$rel (already linked)"; return 0; }
  [ -e "$dst" ] && { warn "$rel exists as a real file — leaving as-is"; return 0; }
  mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; ok "$rel (linked)"
}

# ---------- args ----------
TARGET_ARG="$1"; shift
MODE="prepare"; BASE=""; ISO_DB=""; ISO_PORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --create) MODE="create"; shift
              case "${1:-}" in ""|--*) ;; *) BASE="$1"; shift ;; esac ;;
    --remove) MODE="remove"; shift ;;
    --isolated-db) ISO_DB="${2:-}"; [ -n "$ISO_DB" ] || die "--isolated-db requires a name (e.g. powernode_dev)"; shift 2
                   case "${1:-}" in ""|--*) ;; *) ISO_PORT="$1"; shift ;; esac ;;
    *) die "unknown option: $1" ;;
  esac
done

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

  # Concurrency guard (DB-contention backstop). Every worktree is an isolated test DB on the ONE
  # shared Postgres instance; fanning out too many at once causes severe prep contention — a prep
  # that normally takes under a minute took 15+ minutes with several concurrent worktrees (see
  # docs/contributing/conventions/autonomous-campaigns.md, "Multi-agent worktree ownership
  # protocol"). This is the mechanical backstop to the "stagger DB-heavy setup" discipline: cap the
  # active-worktree count. Collapse finished worktrees (--remove) rather than raising it; override
  # for a deliberate large fan-out with WORKTREE_MAX=N.
  WORKTREE_MAX="${WORKTREE_MAX:-4}"
  active_wts=$(( $(git -C "$MAIN" worktree list --porcelain | grep -c '^worktree ') - 1 ))  # minus main
  if [ "$active_wts" -ge "$WORKTREE_MAX" ]; then
    warn "already $active_wts active worktree(s) — cap is WORKTREE_MAX=$WORKTREE_MAX:"
    git -C "$MAIN" worktree list | sed 's|^|      |' >&2
    die "refusing to create another worktree (DB-contention backstop). Collapse finished ones first
       (scripts/prepare-worktree.sh <path> --remove), or raise the cap deliberately:
       WORKTREE_MAX=$((active_wts + 1)) $0 $TARGET_ARG --create ${BASE:-}"
  fi

  base_ref="${BASE:-$(git -C "$MAIN" symbolic-ref --short HEAD)}"
  # Stale-base guard: a worktree created off a LOCAL branch that lags origin
  # silently bases new work on old code (bit the ops-hub campaign twice).
  # Best-effort fetch, then prefer origin/<base> when it exists; offline use
  # keeps working — fetch failure is a warning, never fatal.
  if git -C "$MAIN" fetch --quiet origin "$base_ref" 2>/dev/null \
      && git -C "$MAIN" rev-parse --verify --quiet "origin/$base_ref" >/dev/null; then
    if [ "$(git -C "$MAIN" rev-parse "$base_ref")" != "$(git -C "$MAIN" rev-parse "origin/$base_ref")" ]; then
      warn "local '$base_ref' differs from origin/$base_ref — basing the worktree on origin/$base_ref"
    fi
    base_ref="origin/$base_ref"
  elif [ -n "${BASE:-}" ] && git -C "$MAIN" rev-parse --verify --quiet "$base_ref" >/dev/null; then
    warn "could not fetch origin/$base_ref (offline? sha/tag base?) — using local '$base_ref'"
  fi
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

# ---------- 3. gitignored runtime configs ----------
# Secrets (master.key, *.yml.enc, per-env credential keys) are always SYMLINKED — shared key
# material. Deployment-targeting config (database.yml, .env) is SYMLINKED by default (the worktree
# shares main's DB); with --isolated-db <name> [port] it is COPIED and rewritten so the worktree
# targets its OWN database(s) (powernode_* → <name>_*) and never main's live DB.
if [ -n "$ISO_DB" ]; then
  info "runtime configs (isolated DB ${ISO_DB}_*${ISO_PORT:+ on port $ISO_PORT})"
else
  info "runtime configs (symlinked — shares main's DEV DB; TEST DB isolated per worktree)"
fi

for rel in server/config/master.key server/config/credentials.yml.enc; do link_one "$rel"; done

for rel in server/config/database.yml server/.env worker/.env; do
  src="$MAIN/$rel"; dst="$TARGET/$rel"
  [ -e "$src" ] || continue
  if [ -L "$dst" ] || [ -e "$dst" ]; then skip "$rel (already present)"; continue; fi
  if [ -z "$ISO_DB" ]; then link_one "$rel"; continue; fi
  mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"
  case "$rel" in
    *database.yml)
      sed -E -i "s/powernode_(development|test|production)/${ISO_DB}_\1/g" "$dst"
      ok "$rel (copied → ${ISO_DB}_*)" ;;
    server/.env)
      # NEVER write an env var that the Gemfile reads (POWERNODE_INCLUDE_PRIVATE_EXTENSIONS,
      # POWERNODE_DEPLOYED) into .env — Bundler evaluates server/Gemfile (which calls
      # discover_extension_gems) BEFORE any Ruby of the app runs, while dotenv-rails only loads
      # .env at Rails' before_configuration hook. The Gemfile would see the var UNSET (private
      # path-gems never declared, models never loaded) while post-boot readers like
      # server/spec/rails_helper.rb see it SET and load those extensions' factories anyway.
      # Private extensions are selected by BUNDLE_GEMFILE=Gemfile.private, whose `||=`
      # (server/Gemfile.private:12) sets the flag at Gemfile-evaluation time UNLESS one is
      # already inherited — an inherited 0 selects the private bundle and still loads ZERO
      # private extensions, so pin it explicitly, as scripts/validate.sh:353 does. Step 5
      # below only `bundle check`s that bundle; it does not exercise the flag.
      # Guarded by server/spec/scripts/prepare_worktree_env_split_spec.rb.
      env_upsert "$dst" DATABASE_NAME "${ISO_DB}_development"
      [ -n "$ISO_PORT" ] && env_upsert "$dst" PORT "$ISO_PORT"
      ok "$rel (copied; DATABASE_NAME=${ISO_DB}_development${ISO_PORT:+, PORT=$ISO_PORT})" ;;
    *)
      ok "$rel (copied)" ;;
  esac
done

# ---------- 3b. per-worktree TEST database isolation (always) ----------
# The worktree shares main's DEV DB (above — intentional, to read live data), but it
# MUST have its OWN test DB. Concurrent worktree sessions otherwise migrate/clobber the
# same powernode_test, drifting each other's schema and breaking each other's specs.
# dotenv-rails loads server/.env.test.local in the test env, so a worktree-unique
# TEST_ENV_NUMBER there routes specs to powernode_test<suffix> (database.yml uses
# `database: powernode_test<%= ENV['TEST_ENV_NUMBER'] %>`). Dev/prod stay shared.
WT_SLUG="$(basename "$TARGET" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '_' | sed 's/^_//;s/_$//')"
TEST_SUFFIX="_${WT_SLUG}"
ENV_TEST_LOCAL="$TARGET/server/.env.test.local"
if [ -e "$ENV_TEST_LOCAL" ]; then
  skip "server/.env.test.local (already present)"
else
  printf '%s\n' \
    "# Auto-generated by prepare-worktree.sh — isolates this worktree's TEST database." \
    "# Test DB = powernode_test${TEST_SUFFIX}; dev/prod stay shared with main." \
    "TEST_ENV_NUMBER=${TEST_SUFFIX}" > "$ENV_TEST_LOCAL"
  ok "server/.env.test.local (TEST_ENV_NUMBER=${TEST_SUFFIX} → powernode_test${TEST_SUFFIX})"
fi
# The isolated test DB is created on first use, NOT here: schema:load on the full
# schema is slow (minutes), and prepare-worktree is meant to stay fast/offline. The
# naming isolation above is automatic; creating the DB is a one-time command. Specs
# auto-target powernode_test${TEST_SUFFIX} via .env.test.local (no env var needed at
# run time). Create it once with the command below.
#
# IMPORTANT: when private extensions are present, use scripts/prepare-extension-test-db.sh, NOT a
# plain `db:prepare`. The committed schema.rb is core-only, and the private engine migrations are
# timestamped below the core schema version, so `db:prepare`/`db:schema:load` assume-migrates them
# WITHOUT creating their tables — leaving every private (business_*/trading_*/…) table silently
# absent. prepare-extension-test-db.sh loads the core schema, un-assumes the private migrations, and
# runs them for real (then restores the core-only schema.rb). It degrades to plain db:prepare in
# core mode.
if [ -d "$MAIN/extensions/private" ] && [ -n "$(ls -A "$MAIN/extensions/private" 2>/dev/null)" ]; then
  info "isolated test DB: create once with → (cd $TARGET && TEST_ENV_NUMBER=${TEST_SUFFIX} scripts/prepare-extension-test-db.sh)"
else
  info "isolated test DB: create once with → (cd $TARGET/server && RAILS_ENV=test bin/rails db:prepare)"
fi

# FIX 1: per-environment Rails credential keys. The <env>.yml.enc is tracked (checked out), but its
# matching <env>.key is a gitignored secret, so without linking it a fresh worktree can't decrypt.
if [ -d "$MAIN/server/config/credentials" ]; then
  for key in "$MAIN"/server/config/credentials/*.key; do
    [ -e "$key" ] || continue
    link_one "server/config/credentials/$(basename "$key")"
  done
fi

# FIX 3: extension posture (gitignored runtime state) — COPY, never symlink (a symlink would make a
# worktree's enable/disable toggle mutate main's LIVE deployment posture).
if [ -f "$MAIN/config/extensions_state.json" ]; then
  dst="$TARGET/config/extensions_state.json"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    skip "config/extensions_state.json (already present)"
  else
    mkdir -p "$(dirname "$dst")"; cp "$MAIN/config/extensions_state.json" "$dst"
    ok "config/extensions_state.json (copied)"
  fi
fi

# ---------- 4. gitignored JS deps (node_modules symlinked from main) ----------
# A fresh worktree checks out package.json but NOT node_modules (gitignored), so
# tsc / jest / vite can't run. node_modules is a content-addressed dependency cache
# keyed by the lockfile, not source — so when the worktree's package.json matches
# main's we symlink main's tree (OFFLINE, no install). A DIVERGED manifest means the
# deps may differ, so we DON'T link it (a stale link would be wrong) and tell the
# operator to `npm install`, which creates a real node_modules in the worktree.
# Package dirs are discovered dynamically (repo root + each immediate subdir with a
# package.json) — nothing is hardcoded.
info "JS dependencies (node_modules symlinked from main)"
js_any=0
js_pkgs=()
[ -f "$MAIN/package.json" ] && js_pkgs+=("$MAIN/package.json")
for d in "$MAIN"/*/; do [ -f "${d}package.json" ] && js_pkgs+=("${d}package.json"); done
for pkg in "${js_pkgs[@]}"; do
  dir="$(dirname "$pkg")"
  rel="${dir#"$MAIN"/}"; [ "$dir" = "$MAIN" ] && rel="."
  [ -d "$dir/node_modules" ] || { skip "$rel (no node_modules in main — run 'npm install')"; continue; }
  js_any=1
  dst="$TARGET/$rel/node_modules"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    skip "$rel/node_modules (already present)"
  elif [ -f "$TARGET/$rel/package.json" ] && ! cmp -s "$dir/package.json" "$TARGET/$rel/package.json"; then
    warn "$rel/package.json differs from main — run 'cd $rel && npm install' (not symlinking; deps may differ)"
  else
    ln -s "$dir/node_modules" "$dst"; ok "$rel/node_modules"
  fi
done
[ "$js_any" -eq 1 ] || skip "no JS packages with installed deps in main"

# ---------- 5. verify bundles resolve ----------
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

# ---------- 6. gem pre-activation doctor (warn-only) ----------
# A boot-critical gem (json, rdoc, ...) newer than the lock pin crashes boot
# ("already activated <gem>-X"). Warn here so the orphan is caught at worktree
# setup, not first boot.
info "gem pre-activation doctor"
if [ ! -x "$SELF_DIR/doctor-gem-preactivation.sh" ]; then
  skip "doctor-gem-preactivation.sh not found next to this script — skipped"
elif "$SELF_DIR/doctor-gem-preactivation.sh" >/dev/null 2>&1; then
  ok "no newer-than-locked boot-critical gem orphan installed"
else
  warn "gem pre-activation hazard detected — run scripts/doctor-gem-preactivation.sh for the 'gem uninstall' remediation (do NOT bump the lock pin)"
fi

info "${C_OK}worktree ready${C_RST}  ${C_DIM}$TARGET${C_RST}"
