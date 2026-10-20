#!/usr/bin/env bash
#
# wt.sh — the worktree lifecycle for parallel dev-improve lanes: create, audit, remove.
#
# It is a thin layer over scripts/prepare-worktree.sh (which still does the submodule / config /
# node_modules / lane-file work) and adds what the driver otherwise types by hand: a lane taken from a
# real, locked ledger, the bundle symlinks and config copies, the test database, branches in core AND
# each extension, and a teardown that refuses to strand commits.
#
# Usage:
#   scripts/wt.sh create <key> [--base <ref>] [--path <dir>] [--no-db] [--no-fetch]
#   scripts/wt.sh remove <path> [--strand-ok] [--discard-dirty] [--busy-ok] [--no-fetch] [--dry-run]
#   scripts/wt.sh audit [--json] [--no-liveness] [--no-fetch]
#
# create <key>     worktree at <WT_ROOT>/<key> (default ~/worktrees/<key>) on a new branch <key>, off
#                  origin/<base> (default develop); server/ and worker/ vendor/bundle symlinked from the main
#                  checkout, .bundle/config and Gemfile.private.lock copied; one redis lane from the ledger;
#                  the isolated test database prepared (prepare-extension-test-db.sh; skip with --no-db);
#                  branch <key> switched to in every public extension worktree.
# remove <path>    REFUSES while any commit is not on origin/develop at PATCH level (git cherry) in the
#                  worktree or in any nested extension checkout it judges (see WORK PRESERVATION), and while
#                  another process has its working directory inside it (--busy-ok; the caller's own process
#                  chain is ignored), and while there is uncommitted or untracked work in core, a nested
#                  extension checkout, or a files-only copy under extensions/private/ that differs from main
#                  or that main does not have (--discard-dirty; it never overrides the commit check).
#                  --strand-ok removes anyway, pins each head under refs/keep/<worktree>/<time>-<pid> (a
#                  detached extension HEAD has no branch; pins are create-only, so a name collision stops the
#                  removal) and KEEPS the branches. Otherwise: drop the lane's test database (`dropdb
#                  --if-exists powernode_test<suffix>`, refused unless the name is an isolated lane name that no
#                  other worktree uses), remove the worktrees, release the lane, delete the now-merged branches.
#                  --dry-run runs the commit, uncommitted-work and process checks, prints the verdict and exits
#                  0 (would remove) or 1 (would refuse); it drops, pins and removes nothing (it does fetch
#                  origin/develop and copy a separate clone's objects into the main repository; the
#                  temporary refs are dropped).
#
# WORK PRESERVATION  A removal never discards a commit that is not on develop. Land it first
#   (scripts/land.sh), or pin it (--strand-ok). Judged: core; every public submodule checkout (the paths in
#   main's .gitmodules AND the worktree's own, plus any extensions/<name>/.git), whether a linked worktree of
#   <main>/<ext> or a SEPARATE CLONE (its own .git, or a submodule initialised in the worktree); and every
#   extensions/private/<name> that is a git repository. Each is judged in the main checkout's own repository
#   (<main>/<ext>, <main>/extensions/private/<name>) against that repository's origin/develop, freshly
#   fetched unless --no-fetch. A merge commit not on develop counts as ahead (git cherry skips merges).
#   A separate clone's commits exist nowhere else, so its HEAD and every ref but refs/remotes/* and
#   refs/prefetch/* (branches,
#   tags, notes, ...) and every stash entry are fetched into that repository first (temporary
#   refs/wt-import/). Branches and tags are judged by git cherry (a tag the main repository already has is
#   fine); a stash entry, a note or any other ref always counts as work. If there is no such repository, or
#   the copy fails, or the clone has worktrees of its own, remove refuses even with --strand-ok. Every judged
#   checkout is re-checked (HEAD, refs, stash) just before anything is dropped, and a change refuses. A refusal pins what it copied under
#   refs/keep/<worktree>/refused-<time>-<pid>[-<ref>] so gc cannot prune it; --strand-ok pins a stranded
#   clone's head and refs as refs/keep/<worktree>/<time>-<pid>[-<ref>] (heads/<b>, tags/<t>, stash/<n>).
#   refused-* refs accumulate, one set per refusal: list them with
#   `git -C <main>/<ext> for-each-ref 'refs/keep/<worktree>/refused-*'` and delete them (git update-ref -d)
#   once the work has landed.
#   OUT OF SCOPE (a removal deletes them unjudged): git repositories anywhere else in the worktree, and
#   submodules nested inside an extension. Reflogs (the reset/amend safety net) are not judged and go with
#   the worktree. "On develop" means the origin/develop last fetched: a force-push
#   that rewrote develop is not detected.
# audit            per worktree: branch, lane, ledger state, liveness (processes whose cwd is inside it), and
#                  the ahead-count of core and each extension against origin/develop. A separate clone or a
#                  private extension repository is shown as "separate clone: run remove --dry-run to verify"
#                  (judging it needs a copy into the main repository, which audit never makes).
#
# LANE LEDGER  <main checkout>/scripts/local/worktree-lanes (gitignored; override with WT_LANE_LEDGER).
#   One line per held lane: lane<TAB>worktree path<TAB>key<TAB>epoch. Every read-modify-write runs under
#   flock on <ledger>.lock. A lane is HELD when its ledger line points at a live registered worktree, or a
#   live worktree's server/.env.test.local declares it (that file's lane line keeps working, and is what
#   prepare-worktree.sh alone would use). Lines whose worktree has vanished are dropped on the next write
#   (a line younger than WT_RESERVATION_TTL, default 900s, is a create in progress and is kept).
#
# Environment: WT_ROOT (default ~/worktrees), WT_LANE_LEDGER, WT_MAX_LANE (default 5, matches
# prepare-worktree.sh), WT_DROPDB_CMD (command that drops the lane database; receives TEST_DB_NAME and
# TEST_ENV_NUMBER; default: `dropdb --if-exists` over the application's own connection: PGHOST/PGUSER/PGPORT/
# PGPASSWORD, else DATABASE_HOST/DATABASE_USER, POWERNODE_DATABASE_PASSWORD, else localhost / powernode / the
# development default in database.yml), WT_PROTECTED_DBS
# (space-separated database names never to drop). Deployment facts are not needed.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/landing-common.sh
. "$SELF_DIR/lib/landing-common.sh"

# Every exit says why. lc_die prints its own message and marks WT_REPORT_FILE (exported, so a child such as
# prepare-worktree.sh, or lc_die inside a subshell, marks it too); any other non-zero exit (a command failing
# under set -e) gets one line from the exit trap, naming the command. The trap also drops the temporary
# refs/wt-import/ refs a remove fetched into the main repositories.
WT_CMD="${1:-}"; WT_IMPORT_NS=""; WT_IMPORT_STORES=()
WT_REPORT_FILE="$(mktemp "${TMPDIR:-/tmp}/wt-report.XXXXXX")" || { printf 'error: wt.sh: could not create a temporary file\n' >&2; exit 1; }
export WT_REPORT_FILE
lc_die() {
  printf 1 >"$WT_REPORT_FILE" 2>/dev/null || true
  printf '%serror:%s %s\n' "$LC_ERR" "$LC_RST" "$*" >&2
  exit "${LC_DIE_CODE:-1}"
}
wt_import_cleanup() {
  local s
  [ -n "$WT_IMPORT_NS" ] || return 0
  for s in "${WT_IMPORT_STORES[@]}"; do
    git -C "$s" for-each-ref --format='delete %(refname)' "refs/wt-import/$WT_IMPORT_NS/" 2>/dev/null | git -C "$s" update-ref --stdin 2>/dev/null || true
  done
}
wt_on_exit() {
  local rc=$? cmd="$BASH_COMMAND"
  wt_import_cleanup
  if [ "$rc" -ne 0 ] && [ ! -s "$WT_REPORT_FILE" ]; then
    printf '%serror:%s wt.sh %s stopped unexpectedly (exit %s) at: %s\n' "$LC_ERR" "$LC_RST" "$WT_CMD" "$rc" "$cmd" >&2
  fi
  rm -f -- "$WT_REPORT_FILE"
  return 0  # the shell still exits with rc; a non-zero return would abort a chained trap under set -e
}
trap wt_on_exit EXIT

case "${1:-}" in -h|--help|"") sed -n '2,/^set -euo/{/^set -euo/!p}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

MAIN="$(lc_main_root "$SELF_DIR")" || lc_die "not inside a git repository"
[ -d "$MAIN/extensions" ] || lc_die "main checkout not found at: $MAIN"
LEDGER="${WT_LANE_LEDGER:-$MAIN/scripts/local/worktree-lanes}"
WT_MAX_LANE="${WT_MAX_LANE:-5}"
BASE_BRANCH="develop"
mkdir -p "$(dirname "$LEDGER")"

mapfile -t SUBPATHS < <(git -C "$MAIN" config -f "$MAIN/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')

# ---- ledger ----------------------------------------------------------------------------------------
live_worktrees() { git -C "$MAIN" worktree list --porcelain | sed -n 's/^worktree //p'; }

# Runs "$@" holding the ledger lock.
with_ledger_lock() {
  ( flock -w 60 9 || lc_die "could not lock the lane ledger ($LEDGER.lock)"; "$@" ) 9>"$LEDGER.lock"
}

# Drops ledger lines whose worktree is gone. A line younger than WT_RESERVATION_TTL seconds (default
# 900) is kept even when its worktree is not registered yet: that is a create still in progress, and
# pruning it would hand its lane to a concurrent create. Caller holds the lock.
ledger_prune() {
  [ -f "$LEDGER" ] || return 0
  local live tmp now lane path key epoch; live="$(live_worktrees)"; tmp="$(mktemp "$LEDGER.XXXXXX")"; now="$(date +%s)"
  while IFS=$'\t' read -r lane path key epoch; do
    [ -n "${lane:-}" ] || continue
    if printf '%s\n' "$live" | command grep -qxF -- "$path" || [ $((now - ${epoch:-0})) -lt "${WT_RESERVATION_TTL:-900}" ]; then
      printf '%s\t%s\t%s\t%s\n' "$lane" "$path" "$key" "$epoch" >>"$tmp"
    fi
  done <"$LEDGER"
  mv "$tmp" "$LEDGER"
}

env_file_lane() { sed -n 's/^TEST_REDIS_LANE=\([0-9][0-9]*\).*/\1/p' "$1/server/.env.test.local" 2>/dev/null | head -1 || true; }

# Lanes held right now: ledger (live worktrees) plus the lane lines of live worktrees.
held_lanes() {
  local wt l
  [ -f "$LEDGER" ] && cut -f1 "$LEDGER"
  for wt in $(live_worktrees); do l="$(env_file_lane "$wt")"; [ -z "$l" ] || printf '%s\n' "$l"; done
}

# Reserve the lowest free lane for <path>. Caller holds the lock. Prints the lane.
reserve_lane() {
  local path="$1" key="$2" used lane
  ledger_prune
  used="$(held_lanes | sort -un | tr '\n' ' ')"
  for lane in $(seq 1 "$WT_MAX_LANE"); do
    case " $used " in *" $lane "*) continue ;; esac
    printf '%s\t%s\t%s\t%s\n' "$lane" "$path" "$key" "$(date +%s)" >>"$LEDGER"
    printf '%s\n' "$lane"; return 0
  done
  lc_info "lanes 1-$WT_MAX_LANE are all held:"; ledger_show >&2
  return 1
}
release_lane() { # path; caller holds the lock
  [ -f "$LEDGER" ] || return 0
  local tmp; tmp="$(mktemp "$LEDGER.XXXXXX")"
  awk -F'\t' -v p="$1" '$2 != p' "$LEDGER" >"$tmp"; mv "$tmp" "$LEDGER"
}
ledger_show() { [ -f "$LEDGER" ] && awk -F'\t' '{printf "  lane %s  %s\n", $1, $2}' "$LEDGER" || true; }

# ---- helpers ---------------------------------------------------------------------------------------
# Commits on <rev>s (default HEAD) in <repo> that are not on origin/<base> at patch level (git cherry
# marks them "+"), plus merge commits not on it, counted once each. Prints the count, or "?" when origin/<base> is unknown there.
ahead_count() {
  local repo="$1" out all="" rev; shift
  [ $# -gt 0 ] || set -- HEAD
  git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$BASE_BRANCH" >/dev/null || { echo "?"; return 0; }
  for rev in "$@"; do
    # A cherry that FAILS (unborn HEAD, missing objects) must not read as "0 ahead".
    out="$(git -C "$repo" cherry "origin/$BASE_BRANCH" "$rev" 2>/dev/null)" || { echo "?"; return 0; }
    all="$all$out"$'\n'
    # git cherry skips merge commits; a merge not on origin/<base> may carry its own work (a resolution).
    out="$(git -C "$repo" rev-list --merges "origin/$BASE_BRANCH..$rev" 2>/dev/null)" || { echo "?"; return 0; }
    [ -z "$out" ] || all="$all$(printf '%s\n' "$out" | sed 's/^/+ /')"$'\n'
  done
  printf '%s' "$all" | command grep '^+' | sort -u | command grep -c . || true
}

# True when <a> and <b> are checkouts of one object store (a linked worktree and its repository).
same_store() {
  local a b
  a="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  b="$(git -C "$2" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$a" ] && [ "$a" = "$b" ]
}

# Fetch a separate clone's HEAD, every ref but refs/remotes/* (branches, tags, notes, ...) and every stash
# entry into <store> under refs/wt-import/<ns>/ (dropped by the exit trap), so they can be judged and pinned
# there. A stash entry is fetched by id: upload-pack is told to allow that.
wt_import() { # store clone
  local ns="refs/wt-import/$WT_IMPORT_NS" refs stashes ref sha n=0
  local -a specs=("+HEAD:$ns/HEAD")
  refs="$(git -C "$2" for-each-ref --format='%(refname)')" || return 1
  stashes="$(git -C "$2" stash list --format=%H)" || return 1
  while IFS= read -r ref; do
    case "$ref" in ""|refs/remotes/*|refs/prefetch/*|refs/stash|refs/wt-import/*) ;; *) specs+=("+$ref:$ns/$ref") ;; esac
  done <<<"$refs"
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    specs+=("+$sha:$ns/stash/$n"); n=$((n + 1))
  done <<<"$stashes"
  WT_IMPORT_STORES+=("$1")
  git -C "$1" fetch --quiet --no-tags --no-write-fetch-head \
    --upload-pack='git -c uploadpack.allowAnySHA1InWant=true upload-pack' "$2" "${specs[@]}" >&2
}

# Judge one nested checkout <dir> of worktree <path> in the main checkout's repository for it. Sets
# J_REL, J_STORE, J_HEAD, J_IMPORT (1: a separate clone, copied in), J_N (commits not on origin/develop, or
# "?"), J_EXTRA (refs that always count as work: stash entries, notes, ...), J_EXTRA_NAMES, and J_ITEMS
# ("<ref suffix>|<object>" for every copied ref that holds work). Refuses outright (even with --strand-ok)
# when the commits cannot be copied anywhere.
judge_checkout() { # path dir
  local path="$1" dir="$2" ns ref sha name peeled
  local -a revs=()
  J_REL="${dir#"$path"/}"; J_STORE="$MAIN/$J_REL"; J_IMPORT=0; J_EXTRA=0; J_EXTRA_NAMES=""; J_ITEMS=()
  J_HEAD="$(git -C "$dir" rev-parse --verify --quiet 'HEAD^{commit}' || true)"
  [ -n "$J_HEAD" ] || LC_DIE_CODE=1 lc_die "refusing to remove $path: $J_REL has no commit checked out (git rev-parse HEAD failed); nothing was removed"
  [ -e "$J_STORE/.git" ] || LC_DIE_CODE=1 lc_die "refusing to remove $path: there is no submodule store or repository at $J_STORE to judge (or keep) $J_REL's commits in, so a removal would delete them; nothing was removed"
  fetch_base "$J_STORE"
  revs=("$J_HEAD")
  if same_store "$dir" "$J_STORE"; then
    J_N="$(ahead_count "$J_STORE" "$J_HEAD")"; return 0
  fi
  J_IMPORT=1
  [ "$(git -C "$dir" worktree list --porcelain 2>/dev/null | command grep -c '^worktree ' || true)" -le 1 ] ||
    LC_DIE_CODE=1 lc_die "refusing to remove $path: $J_REL is a separate clone with worktrees of its own ($(git -C "$dir" worktree list 2>/dev/null | sed 1d | awk '{print $1}' | tr '\n' ' ')); their work (a detached HEAD) would be lost with it. Remove them first; nothing was removed"
  { wt_import "$J_STORE" "$dir" && git -C "$J_STORE" cat-file -e "$J_HEAD^{commit}" 2>/dev/null; } ||
    LC_DIE_CODE=1 lc_die "refusing to remove $path: could not copy $J_REL's commits into $J_STORE ($J_REL is a separate clone, so a removal would delete them); nothing was removed"
  lc_info "  $J_REL is a separate clone: copied its HEAD, refs and stash into $J_STORE"
  ns="refs/wt-import/$WT_IMPORT_NS/"
  while read -r ref sha; do
    name="${ref#"$ns"}"
    case "$name" in
      HEAD) ;;
      refs/heads/*|refs/tags/*)
        # A tag the main repository already has, at the same object, is not this clone's work.
        case "$name" in refs/tags/*) [ "$(git -C "$J_STORE" rev-parse --verify --quiet "$name" || true)" != "$sha" ] || continue ;; esac
        peeled="$(git -C "$J_STORE" rev-parse --verify --quiet "$sha^{commit}" || true)"
        if [ -z "$peeled" ]; then
          J_EXTRA=$((J_EXTRA + 1)); J_EXTRA_NAMES="$J_EXTRA_NAMES ${name#refs/}"; J_ITEMS+=("${name#refs/}|$sha"); continue
        fi
        revs+=("$peeled")
        [ "$(ahead_count "$J_STORE" "$peeled")" = 0 ] || J_ITEMS+=("${name#refs/}|$sha") ;;
      *) # stash/<n>, notes, anything else: kept as it is
        J_EXTRA=$((J_EXTRA + 1)); J_EXTRA_NAMES="$J_EXTRA_NAMES ${name#refs/}"; J_ITEMS+=("${name#refs/}|$sha") ;;
    esac
  done < <(git -C "$J_STORE" for-each-ref --format='%(refname) %(objectname)' "$ns")
  J_N="$(ahead_count "$J_STORE" "${revs[@]}")"
}

# Pin the judged nested checkouts' heads (and a separate clone's work-holding refs as <base>-<ref>) in the
# main repositories. imports-only=1 (a refusal): only the stranded separate clones, whose copies would
# otherwise be unreferenced. imports-only=0 (--strand-ok): every linked checkout's head too.
pin_checkouts() { # base imports-only
  local i entry rest suf obj
  for i in "${!CK_REL[@]}"; do
    if [ "${CK_IMPORT[$i]}" -eq 1 ]; then [ "${CK_STRANDED[$i]}" -eq 1 ] || continue
    else [ "$2" -eq 0 ] || continue; fi
    pin_ref "${CK_STORE[$i]}" "$1" "${CK_HEAD[$i]}" "${CK_REL[$i]}'s head"
  done
  for entry in "${CK_ITEMS[@]}"; do
    i="${entry%%|*}"; rest="${entry#*|}"; suf="${rest%|*}"; obj="${rest##*|}"
    pin_ref "${CK_STORE[$i]}" "$1-$suf" "$obj" "${CK_REL[$i]} $suf"
  done
}

# What a nested checkout holds, for the re-check just before removal: HEAD, every ref, every stash entry.
# Remote-tracking refs and wt.sh's own pins and imports (a linked checkout shares the store) are not work.
checkout_digest() { # dir
  { git -C "$1" rev-parse HEAD
    git -C "$1" for-each-ref --format='%(objectname) %(refname)' | command grep -vE ' refs/(keep|wt-import|remotes|prefetch)/' || true
    git -C "$1" stash list --format=%H; } 2>&1 | sha256sum | cut -d' ' -f1
}

# Create-only pin: an existing ref of that name stops the removal instead of being overwritten.
pin_ref() { # repo ref object what
  git -C "$1" update-ref "$2" "$3" "" 2>/dev/null ||
    LC_DIE_CODE=1 lc_die "could not pin $4 under $2 (it may already exist); nothing was removed"
  lc_info "  kept $4 under $2"
}

# Uncommitted or untracked work in <repo> (a worktree or a nested extension worktree): the porcelain
# status lines, ignoring gitignored files and gitlinks. wt.sh's own generated worker/vendor/bundle
# symlink dir is not work.
dirty_lines() {
  local repo="$1" lines
  lines="$(git -C "$repo" status --porcelain --untracked-files=normal --ignore-submodules=all 2>/dev/null)" || { echo "?? (git status failed)"; return 0; }
  if [ -d "$repo/worker/vendor" ] && [ -z "$(find "$repo/worker/vendor" -mindepth 1 -maxdepth 1 ! -name bundle 2>/dev/null)" ]; then
    lines="$(printf '%s\n' "$lines" | command grep -vxF '?? worker/vendor/' || true)"
  fi
  printf '%s\n' "$lines" | command grep -v '^$' || true
}
# The files-only copies under extensions/private/* that differ from the main checkout's, or that main does
# not have. One that is a git repository is judged by its commits and its git status instead.
private_copy_diffs() {
  local wt="$1" d n
  [ -d "$wt/extensions/private" ] || return 0
  for d in "$wt"/extensions/private/*/; do
    [ -d "$d" ] || continue
    [ ! -e "${d}.git" ] || continue
    n="$(basename "$d")"
    [ -d "$MAIN/extensions/private/$n" ] || { printf 'extensions/private/%s (not in main)\n' "$n"; continue; }
    diff -rq --exclude=.git --exclude=tmp --exclude=log --exclude=node_modules "$MAIN/extensions/private/$n" "${d%/}" >/dev/null 2>&1 || printf 'extensions/private/%s\n' "$n"
  done
  return 0
}
ext_dirs() { # worktree path -> nested extension checkouts present in it
  local p
  for p in "${SUBPATHS[@]}"; do
    [ -e "$1/$p/.git" ] && printf '%s\n' "$1/$p"
  done
  return 0
}
# Every nested checkout remove judges, once each: the submodule paths of main's .gitmodules AND the
# worktree's own (develop may have added one main's checkout does not have yet), any other
# extensions/<name>/.git, and each private extension that is a git repository.
judged_dirs() { # worktree path
  {
    local d p
    ext_dirs "$1"
    if [ -f "$1/.gitmodules" ]; then
      while read -r _ p; do [ -n "$p" ] && [ -e "$1/$p/.git" ] && printf '%s\n' "$1/$p"; done \
        < <(git config -f "$1/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
    fi
    for d in "$1"/extensions/*/ "$1"/extensions/private/*/; do
      [ "${d%/}" != "$1/extensions/private" ] || continue
      [ -e "${d}.git" ] && printf '%s\n' "${d%/}"
    done
  } | sort -u
  return 0
}
fetch_base() { # repo
  [ "${NO_FETCH:-0}" -eq 1 ] || git -C "$1" fetch --quiet origin "$BASE_BRANCH" 2>/dev/null || lc_info "  could not fetch origin/$BASE_BRANCH in $1 (using the ref as it is)"
}
registered_worktree() { live_worktrees | command grep -qxF -- "$1"; }

# PIDs, other than this script and its ancestors, whose working directory is inside <path>.
busy_pids() {
  local path="$1" pid cwd p anc=""
  p=$$
  while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
    anc="$anc $p"; p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  done
  for pid in $(ls /proc 2>/dev/null | command grep -E '^[0-9]+$'); do
    case " $anc " in *" $pid "*) continue ;; esac
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)" || continue
    case "$cwd" in "$path"|"$path"/*) printf '%s\n' "$pid" ;; esac
  done
}

# ---- create ----------------------------------------------------------------------------------------
cmd_create() {
  local key="${1:-}"; shift || true
  local base="$BASE_BRANCH" path="" want_db=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) base="${2:-}"; shift 2 ;;
      --path) path="${2:-}"; shift 2 ;;
      --no-db) want_db=0; shift ;;
      --no-fetch) NO_FETCH=1; shift ;;
      *) LC_DIE_CODE=2 lc_die "unknown option: $1" ;;
    esac
  done
  [[ "$key" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || LC_DIE_CODE=2 lc_die "create needs a <key> of letters, digits, . _ -"
  path="${path:-${WT_ROOT:-$HOME/worktrees}/$key}"
  [ ! -e "$path" ] || lc_die "path already exists: $path"
  [[ "$path" = /* ]] || path="$PWD/$path"
  git -C "$MAIN" show-ref --verify --quiet "refs/heads/$key" && lc_die "a branch named '$key' already exists in the core repository"
  # The same for every public extension: create never touches (and its failure cleanup never deletes) a branch it did not make.
  local sub
  for sub in "${SUBPATHS[@]}"; do
    [ -e "$MAIN/$sub/.git" ] || continue
    ! git -C "$MAIN/$sub" show-ref --verify --quiet "refs/heads/$key" || lc_die "a branch named '$key' already exists in $sub; land or delete it (it may hold work), or pick another key"
  done

  local lane
  lane="$(with_ledger_lock reserve_lane "$path" "$key")" || lc_die "no free redis lane; remove a finished worktree first (scripts/wt.sh audit)"
  lc_info "lane $lane reserved for $path"
  # ANY failed create (an error, or one of the explicit lc_die exits, which an ERR trap would miss)
  # releases its lane and leaves no half-made worktree or <key> branch behind.
  # (Globals, not locals: an EXIT trap runs after the function's locals are gone.)
  CREATE_OK=0; CREATE_PATH="$path"; CREATE_KEY="$key"; CREATED_EXT_BRANCHES=()
  cleanup_failed_create() {
    [ "$CREATE_OK" -eq 1 ] && return 0
    with_ledger_lock release_lane "$CREATE_PATH" || true
    if [ -d "$CREATE_PATH" ]; then "$SELF_DIR/prepare-worktree.sh" "$CREATE_PATH" --remove >/dev/null 2>&1 || true; fi
    git -C "$MAIN" branch -q -D "$CREATE_KEY" 2>/dev/null || true
    # Only the extension branches THIS run created (the pre-check guarantees the core one is ours too).
    local p; for p in "${CREATED_EXT_BRANCHES[@]}"; do git -C "$MAIN/$p" branch -q -D "$CREATE_KEY" 2>/dev/null || true; done
  }
  trap 'wt_on_exit; cleanup_failed_create' EXIT

  lc_info "creating the worktree off origin/$base"
  WT_FORCE_LANE="$lane" "$SELF_DIR/prepare-worktree.sh" "$path" --create "$base" >&2

  local app
  for app in server worker; do
    if [ -d "$MAIN/$app/vendor/bundle" ] && [ ! -e "$path/$app/vendor/bundle" ]; then
      mkdir -p "$path/$app/vendor"; ln -s "$MAIN/$app/vendor/bundle" "$path/$app/vendor/bundle"
      lc_info "  $app/vendor/bundle linked"
    fi
    if [ -f "$MAIN/$app/.bundle/config" ] && [ ! -e "$path/$app/.bundle/config" ]; then
      mkdir -p "$path/$app/.bundle"; cp "$MAIN/$app/.bundle/config" "$path/$app/.bundle/config"
      lc_info "  $app/.bundle/config copied"
    fi
  done
  if [ -f "$MAIN/server/Gemfile.private.lock" ] && [ ! -e "$path/server/Gemfile.private.lock" ]; then
    cp "$MAIN/server/Gemfile.private.lock" "$path/server/Gemfile.private.lock"; lc_info "  server/Gemfile.private.lock copied"
  fi

  [ "$(env_file_lane "$path")" = "$lane" ] || lc_die "server/.env.test.local did not receive lane $lane"
  local suffix; suffix="$(sed -n 's/^TEST_ENV_NUMBER=//p' "$path/server/.env.test.local" | head -1)"
  [ -n "$suffix" ] || lc_die "server/.env.test.local carries no TEST_ENV_NUMBER; refusing to continue (a shared test database would be used)"

  local ext
  while IFS= read -r ext; do
    [ -n "$ext" ] || continue
    git -C "$ext" switch --quiet -c "$key" && { CREATED_EXT_BRANCHES+=("${ext#"$path"/}"); lc_info "  branch $key in ${ext#"$path"/}"; }
  done < <(ext_dirs "$path")

  if [ "$want_db" -eq 1 ]; then
    lc_info "preparing the isolated test database powernode_test$suffix"
    (cd "$path" && TEST_ENV_NUMBER="$suffix" "$path/scripts/prepare-extension-test-db.sh") >&2
  else
    lc_info "test database NOT prepared (--no-db): run (cd $path && scripts/prepare-extension-test-db.sh)"
  fi
  CREATE_OK=1
  jq -cn --arg path "$path" --arg branch "$key" --argjson lane "$lane" --arg db "powernode_test$suffix" \
    '{path:$path, branch:$branch, redis_lane:$lane, test_database:$db}'
}

# ---- remove ----------------------------------------------------------------------------------------
# The lane database is dropped by NAME, never by asking Rails what it would drop (a DATABASE_URL in the
# environment or a .env would redirect that). The connection is the one the application uses: host and user
# from PGHOST / PGUSER, else DATABASE_HOST / DATABASE_USER, else localhost / powernode; the password from
# PGPASSWORD, else POWERNODE_DATABASE_PASSWORD, else the development default database.yml itself declares
# (read from it, so no password is written into this script). It goes through the environment, never argv.
drop_lane_database() { # db-name
  local pw="${PGPASSWORD:-${POWERNODE_DATABASE_PASSWORD:-}}"
  if [ -z "$pw" ] && [ -f "$MAIN/server/config/database.yml" ]; then
    pw="$(sed -n 's/.*POWERNODE_DATABASE_PASSWORD") *{ *"\([^"]*\)" *}.*/\1/p' "$MAIN/server/config/database.yml" | head -n 1)"
  fi
  local -a envv=("PGHOST=${PGHOST:-${DATABASE_HOST:-localhost}}" "PGUSER=${PGUSER:-${DATABASE_USER:-powernode}}")
  [ -z "${PGPORT:-${DATABASE_PORT:-}}" ] || envv+=("PGPORT=${PGPORT:-$DATABASE_PORT}")
  [ -z "$pw" ] || envv+=("PGPASSWORD=$pw")
  env -u DATABASE_URL "${envv[@]}" dropdb --if-exists "$1" >&2
}

# Refuse unless <name> is an isolated lane database that nobody else uses.
lane_database_guard() { # path suffix
  local path="$1" suffix="$2" name="powernode_test$2" wt other
  [[ "$name" =~ ^powernode_test_[a-z0-9_]+$ ]] || { lc_info "  $name is not an isolated lane database name"; return 1; }
  for wt in $(live_worktrees); do
    [ "$wt" != "$path" ] || continue
    other="$(sed -n 's/^TEST_ENV_NUMBER=//p' "$wt/server/.env.test.local" 2>/dev/null | head -1 || true)"
    if [ "$other" = "$suffix" ]; then lc_info "  worktree $wt uses the same test database ($name)"; return 1; fi
  done
  case " ${WT_PROTECTED_DBS:-} " in *" $name "*) lc_info "  $name is listed in WT_PROTECTED_DBS"; return 1 ;; esac
  return 0
}

cmd_remove() {
  local target="${1:-}"; shift || true
  local strand_ok=0 busy_ok=0 discard_dirty=0 dry_run=0 pre=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --strand-ok) strand_ok=1; shift ;;
      --dry-run) dry_run=1; pre="dry run: "; shift ;;
      --discard-dirty) discard_dirty=1; shift ;;
      --busy-ok) busy_ok=1; shift ;;
      --no-fetch) NO_FETCH=1; shift ;;
      *) LC_DIE_CODE=2 lc_die "unknown option: $1" ;;
    esac
  done
  [ -d "$target" ] || LC_DIE_CODE=2 lc_die "nothing to remove at: $target"
  local path; path="$(cd "$target" && pwd -P)"
  [ "$path" != "$(cd "$MAIN" && pwd -P)" ] || lc_die "refusing to remove the main checkout"
  registered_worktree "$path" || lc_die "$path is not a worktree of $MAIN"

  # 1. Stranded commits: core, then every nested checkout remove judges (judge_checkout): each is judged in
  # the main checkout's repository for it, against ITS origin/develop; a separate clone is copied in first.
  local stranded=0 report="" n dir i entry br stamp keep
  local -a CK_REL=() CK_STORE=() CK_HEAD=() CK_IMPORT=() CK_STRANDED=() CK_ITEMS=() CK_DIGEST=()
  local judged core_head
  stamp="$(date +%Y%m%dT%H%M%S)-$$"; keep="refs/keep/$(basename "$path")"
  WT_IMPORT_NS="$(basename "$path")-$$"
  fetch_base "$path"
  n="$(ahead_count "$path")"; [ "$n" = 0 ] || { stranded=1; report="$report core: $n commit(s) not on origin/$BASE_BRANCH;"; }
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    judge_checkout "$path" "$dir"
    i="${#CK_REL[@]}"
    CK_REL+=("$J_REL"); CK_STORE+=("$J_STORE"); CK_HEAD+=("$J_HEAD"); CK_IMPORT+=("$J_IMPORT"); CK_STRANDED+=(0)
    CK_DIGEST+=("$(checkout_digest "$dir")")
    for entry in "${J_ITEMS[@]}"; do CK_ITEMS+=("$i|$entry"); done
    if [ "$J_N" != 0 ] || [ "$J_EXTRA" -gt 0 ]; then
      stranded=1; CK_STRANDED[i]=1
      report="$report $J_REL: $J_N commit(s) not on origin/$BASE_BRANCH"
      [ "$J_EXTRA" -eq 0 ] || report="$report, plus$J_EXTRA_NAMES (stash entries and refs outside branches always count)"
      [ "$J_IMPORT" -eq 0 ] || report="$report (a separate clone: they exist nowhere else)"
      report="$report;"
    fi
  done < <(judged_dirs "$path")
  judged="$(judged_dirs "$path")"; core_head="$(git -C "$path" rev-parse HEAD)"
  if [ "$stranded" -eq 1 ] && [ "$strand_ok" -eq 0 ]; then
    lc_info "${pre}STRANDED:$report"
    # Keep what was copied in from separate clones, so gc cannot prune it while the clone is being dealt with.
    [ "$dry_run" -eq 1 ] || pin_checkouts "$keep/refused-$stamp" 1
    LC_DIE_CODE=1 lc_die "${pre}refusing to remove $path: it holds commits that are nowhere else. Land them first (scripts/land.sh), or pin them (--strand-ok)."
  fi
  [ "$stranded" -eq 0 ] || lc_info "${pre}--strand-ok: removing anyway;$report each head is kept under refs/keep/ and the branches are KEPT"

  # 1b. Uncommitted or untracked work (core, every judged nested checkout, the private copies).
  local dirty="" d
  d="$(dirty_lines "$path")"; [ -z "$d" ] || dirty="$dirty core: $(printf '%s\n' "$d" | wc -l | tr -d ' ') path(s) (e.g. $(printf '%s\n' "$d" | head -n 3 | sed 's/^...//' | tr '\n' ' '));"
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    d="$(dirty_lines "$dir")"; [ -z "$d" ] || dirty="$dirty ${dir#"$path"/}: $(printf '%s\n' "$d" | wc -l | tr -d ' ') path(s);"
  done < <(judged_dirs "$path")
  d="$(private_copy_diffs "$path" | tr '\n' ' ')"; [ -z "$d" ] || dirty="$dirty private copies differ from main: $d;"
  if [ -n "$dirty" ] && [ "$discard_dirty" -eq 0 ]; then
    lc_info "${pre}UNCOMMITTED:$dirty"
    LC_DIE_CODE=1 lc_die "${pre}refusing to remove $path: it holds uncommitted or untracked work that a removal would delete. Commit or move it first."
  fi
  [ -z "$dirty" ] || lc_info "${pre}--discard-dirty: discarding uncommitted work;$dirty"

  # 2. Live processes.
  if [ "$busy_ok" -eq 0 ]; then
    local busy; busy="$(busy_pids "$path" | tr '\n' ' ')"
    [ -z "${busy// /}" ] || LC_DIE_CODE=1 lc_die "${pre}process(es) ${busy}have their working directory inside $path; stop them, or pass --busy-ok"
  fi
  if [ "$dry_run" -eq 1 ]; then
    lc_info "dry run: remove would proceed for $path; nothing was dropped, pinned or removed"
    return 0
  fi

  # 3. Branches to delete afterwards (only when nothing is stranded).
  local core_branch; core_branch="$(git -C "$path" symbolic-ref --quiet --short HEAD || true)"
  local -a ext_branches=()
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    ext_branches+=("${dir#"$path"/}|$(git -C "$dir" symbolic-ref --quiet --short HEAD || true)")
  done < <(ext_dirs "$path")

  # 4. --strand-ok: pin every head under refs/keep/ before anything is dropped or deleted. A detached
  # extension HEAD has no branch, and its commits are unreachable the moment the worktree (and its
  # reflog) goes; a separate clone's commits were copied in above, so they can be pinned there. A fully
  # merged separate clone is not pinned.
  if [ "$stranded" -eq 1 ]; then
    pin_ref "$MAIN" "$keep/$stamp" "$(git -C "$path" rev-parse HEAD)" "the core head"
    pin_checkouts "$keep/$stamp" 0
  fi

  # 4a. Nothing judged may have changed since (a commit, a new ref or stash entry, a new checkout).
  # Test seam: WT_TEST_HOOK_AFTER_JUDGE runs here, so the throwaway-repo test can change a checkout.
  [ -z "${WT_TEST_HOOK_AFTER_JUDGE:-}" ] || bash -c "$WT_TEST_HOOK_AFTER_JUDGE" >&2 || true
  [ "$(judged_dirs "$path")" = "$judged" ] && [ "$(git -C "$path" rev-parse HEAD)" = "$core_head" ] ||
    LC_DIE_CODE=1 lc_die "refusing to remove $path: its checkouts changed while it was being judged; nothing was dropped or removed (run remove again)"
  for i in "${!CK_REL[@]}"; do
    [ "$(checkout_digest "$path/${CK_REL[$i]}")" = "${CK_DIGEST[$i]}" ] ||
      LC_DIE_CODE=1 lc_die "refusing to remove $path: ${CK_REL[$i]} changed while it was being judged; nothing was dropped or removed (run remove again)"
  done

  # 4b. The lane's test database. A missing server/.env.test.local is not an error: there is nothing to drop.
  local suffix=""
  if [ -f "$path/server/.env.test.local" ]; then
    suffix="$(sed -n 's/^TEST_ENV_NUMBER=//p' "$path/server/.env.test.local" | head -1 || true)"
  else
    lc_info "server/.env.test.local is missing"
  fi
  if [ -n "$suffix" ] && [[ "$suffix" =~ ^_[a-z0-9_]+$ ]]; then
    lane_database_guard "$path" "$suffix" || LC_DIE_CODE=1 lc_die "not dropping powernode_test$suffix; nothing was removed"
    lc_info "dropping the lane database powernode_test$suffix"
    if [ -n "${WT_DROPDB_CMD:-}" ]; then
      TEST_DB_NAME="powernode_test$suffix" TEST_ENV_NUMBER="$suffix" bash -c "$WT_DROPDB_CMD" >&2 ||
        LC_DIE_CODE=1 lc_die "dropping powernode_test$suffix failed; nothing was removed"
    else
      drop_lane_database "powernode_test$suffix" || LC_DIE_CODE=1 lc_die "dropping powernode_test$suffix failed; nothing was removed (set WT_DROPDB_CMD to drop it another way)"
    fi
  else
    lc_info "no isolated test database recorded for this worktree (TEST_ENV_NUMBER absent or unusual); not dropping anything"
  fi

  # 5. Remove, release, delete merged branches.
  "$SELF_DIR/prepare-worktree.sh" "$path" --remove >&2
  with_ledger_lock release_lane "$path"
  lc_info "lane released"
  if [ "$stranded" -eq 0 ]; then
    if [ -n "$core_branch" ] && git -C "$MAIN" show-ref --verify --quiet "refs/heads/$core_branch"; then
      git -C "$MAIN" branch -q -D "$core_branch" && lc_info "deleted branch $core_branch"
    fi
    local entry sub
    for entry in "${ext_branches[@]}"; do
      sub="${entry%%|*}"; br="${entry#*|}"
      [ -n "$br" ] && git -C "$MAIN/$sub" show-ref --verify --quiet "refs/heads/$br" || continue
      # The store's branch of that name is the worktree's own for a linked worktree; for a separate clone it
      # is another branch, never judged above, so it is deleted only when it is merged too.
      if [ "$(ahead_count "$MAIN/$sub" "refs/heads/$br")" = 0 ]; then
        git -C "$MAIN/$sub" branch -q -D "$br" && lc_info "deleted branch $br in $sub"
      else
        lc_info "kept branch $br in $sub: it holds commits not on origin/$BASE_BRANCH"
      fi
    done
  fi
  lc_info "removed $path"
}

# ---- audit -----------------------------------------------------------------------------------------
cmd_audit() {
  local json=0 liveness=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      --no-liveness) liveness=0; shift ;;
      --no-fetch) NO_FETCH=1; shift ;;
      *) LC_DIE_CODE=2 lc_die "unknown option: $1" ;;
    esac
  done
  local rows="[]" wt branch lane inledger live ahead exts ext n
  local -a lanes_seen=()
  for wt in $(live_worktrees); do
    fetch_base "$wt"
    branch="$(git -C "$wt" symbolic-ref --quiet --short HEAD || echo "(detached)")"
    lane="$(env_file_lane "$wt")"
    inledger="no"; [ -f "$LEDGER" ] && awk -F'\t' -v p="$wt" '$2 == p {f=1} END{exit !f}' "$LEDGER" && inledger="yes"
    live="unchecked"
    if [ "$liveness" -eq 1 ]; then
      local nbusy; nbusy="$(busy_pids "$wt" | wc -l | tr -d ' ')"
      if [ "$nbusy" -eq 0 ]; then live="idle"; else live="busy($nbusy)"; fi
    fi
    ahead="$(ahead_count "$wt")"
    exts="{}"
    while IFS= read -r ext; do
      [ -n "$ext" ] || continue
      # A separate clone (or a private extension repository) can only be judged after a copy into the main
      # repository; audit never makes one, and its own origin may not be the main repository's.
      if same_store "$ext" "$MAIN/${ext#"$wt"/}"; then n="$(ahead_count "$ext")"; else n="separate clone: run remove --dry-run to verify"; fi
      exts="$(jq -c --arg k "${ext#"$wt"/}" --arg v "$n" '. + {($k): $v}' <<<"$exts")"
    done < <(judged_dirs "$wt")
    rows="$(jq -c --arg path "$wt" --arg branch "$branch" --arg lane "${lane:-}" --arg inl "$inledger" --arg live "$live" \
      --arg ahead "$ahead" --argjson exts "$exts" \
      '. + [{path:$path, branch:$branch, lane:(if $lane == "" then null else ($lane|tonumber) end), in_ledger:$inl, liveness:$live, core_ahead:$ahead, ext_ahead:$exts}]' <<<"$rows")"
    [ -z "$lane" ] || lanes_seen+=("$lane")
  done
  local dups; dups="$(printf '%s\n' "${lanes_seen[@]:-}" | sort | uniq -d | tr '\n' ' ')"
  if [ "$json" -eq 1 ]; then
    jq -c --arg dups "$dups" '{worktrees:., duplicate_lanes:($dups | split(" ") | map(select(. != "")))}' <<<"$rows"
  else
    {
      printf 'PATH\tBRANCH\tLANE\tLEDGER\tLIVENESS\tAHEAD\n'
      jq -r '.[] | [.path, .branch, (.lane // "-"), .in_ledger, .liveness, ("core " + .core_ahead + (if (.ext_ahead|length) > 0 then " | " + ([.ext_ahead|to_entries[]|"\(.key|split("/")|last) \(.value)"]|join(", ")) else "" end))] | @tsv' <<<"$rows"
    } | column -t -c 2000 -s "$(printf '\t')"
    [ -z "${dups// /}" ] || printf 'WARNING: redis lane(s) %sheld by more than one worktree (their suites flush each other)\n' "$dups"
    printf 'AHEAD counts commits not on origin/%s at patch level; "?" = that ref is unknown there. A worktree ahead of %s is one `remove` will refuse.\n' "$BASE_BRANCH" "$BASE_BRANCH"
  fi
}

NO_FETCH=0
cmd="$1"; shift
case "$cmd" in
  create) cmd_create "$@" ;;
  remove) cmd_remove "$@" ;;
  audit)  cmd_audit "$@" ;;
  *) LC_DIE_CODE=2 lc_die "unknown command: $cmd (create | remove | audit)" ;;
esac
