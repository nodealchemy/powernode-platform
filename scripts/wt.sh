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
#   scripts/wt.sh remove <path> [--strand-ok] [--discard-dirty] [--busy-ok] [--no-fetch]
#   scripts/wt.sh audit [--json] [--no-liveness] [--no-fetch]
#
# create <key>     worktree at <WT_ROOT>/<key> (default ~/worktrees/<key>) on a new branch <key>, off
#                  origin/<base> (default develop); server/ and worker/ vendor/bundle symlinked from the main
#                  checkout, .bundle/config and Gemfile.private.lock copied; one redis lane from the ledger;
#                  the isolated test database prepared (prepare-extension-test-db.sh; skip with --no-db);
#                  branch <key> switched to in every public extension worktree.
# remove <path>    REFUSES while any commit is not on origin/develop at PATCH level (git cherry) in the
#                  worktree or in any nested extension worktree, and while another process has its working
#                  directory inside it (--busy-ok; the caller's own process chain is ignored), and while
#                  there is uncommitted or untracked work in core, a nested extension worktree, or a files-only
#                  copy under extensions/private/ that differs from main (--discard-dirty).
#                  --strand-ok removes anyway, pins each head under refs/keep/<worktree>/<time> (a detached
#                  extension HEAD has no branch) and KEEPS the branches. Otherwise: drop the lane's test
#                  database (`dropdb --if-exists powernode_test<suffix>`, refused unless the name is an isolated
#                  lane name that no other worktree uses), remove the worktrees, release the lane, delete the
#                  now-merged branches.
# audit            per worktree: branch, lane, ledger state, liveness (processes whose cwd is inside it), and
#                  the ahead-count of core and each extension against origin/develop.
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
# TEST_ENV_NUMBER; default: `dropdb --if-exists` with the ambient PG* settings), WT_PROTECTED_DBS
# (space-separated database names never to drop). Deployment facts are not needed.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/landing-common.sh
. "$SELF_DIR/lib/landing-common.sh"

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
# Commits on <repo>'s HEAD that are not on origin/<base> at patch level (git cherry marks them "+").
# Prints the count, or "?" when origin/<base> is unknown there.
ahead_count() {
  local repo="$1" out
  git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$BASE_BRANCH" >/dev/null || { echo "?"; return 0; }
  # A cherry that FAILS (unborn HEAD, missing objects) must not read as "0 ahead".
  out="$(git -C "$repo" cherry "origin/$BASE_BRANCH" HEAD 2>/dev/null)" || { echo "?"; return 0; }
  printf '%s\n' "$out" | command grep -c '^+' || true
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
# The files-only copies under extensions/private/* that differ from the main checkout's.
private_copy_diffs() {
  local wt="$1" d n
  [ -d "$wt/extensions/private" ] || return 0
  for d in "$wt"/extensions/private/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    [ -d "$MAIN/extensions/private/$n" ] || continue
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

  local lane
  lane="$(with_ledger_lock reserve_lane "$path" "$key")" || lc_die "no free redis lane; remove a finished worktree first (scripts/wt.sh audit)"
  lc_info "lane $lane reserved for $path"
  # ANY failed create (an error, or one of the explicit lc_die exits, which an ERR trap would miss)
  # releases its lane and leaves no half-made worktree or <key> branch behind.
  # (Globals, not locals: an EXIT trap runs after the function's locals are gone.)
  CREATE_OK=0; CREATE_PATH="$path"; CREATE_KEY="$key"
  cleanup_failed_create() {
    [ "$CREATE_OK" -eq 1 ] && return 0
    with_ledger_lock release_lane "$CREATE_PATH" || true
    if [ -d "$CREATE_PATH" ]; then "$SELF_DIR/prepare-worktree.sh" "$CREATE_PATH" --remove >/dev/null 2>&1 || true; fi
    git -C "$MAIN" branch -q -D "$CREATE_KEY" 2>/dev/null || true
    local p; for p in "${SUBPATHS[@]}"; do git -C "$MAIN/$p" branch -q -D "$CREATE_KEY" 2>/dev/null || true; done
  }
  trap cleanup_failed_create EXIT

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
    git -C "$ext" switch --quiet -c "$key" && lc_info "  branch $key in ${ext#"$path"/}"
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
# environment or a .env would redirect that). Connection settings are the ambient PG* environment.
drop_lane_database() { # db-name
  env -u DATABASE_URL dropdb --if-exists "$1" >&2
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
  local strand_ok=0 busy_ok=0 discard_dirty=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --strand-ok) strand_ok=1; shift ;;
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

  # 1. Stranded commits: core, then every nested extension worktree.
  local stranded=0 report="" n dir
  fetch_base "$path"
  n="$(ahead_count "$path")"; [ "$n" = 0 ] || { stranded=1; report="$report core: $n commit(s) not on origin/$BASE_BRANCH;"; }
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    fetch_base "$dir"
    n="$(ahead_count "$dir")"; [ "$n" = 0 ] || { stranded=1; report="$report ${dir#"$path"/}: $n commit(s) not on origin/$BASE_BRANCH;"; }
  done < <(ext_dirs "$path")
  if [ "$stranded" -eq 1 ] && [ "$strand_ok" -eq 0 ]; then
    lc_info "STRANDED:$report"
    LC_DIE_CODE=1 lc_die "refusing to remove $path: it holds commits that are nowhere else. Land them first (scripts/land.sh)."
  fi
  [ "$stranded" -eq 0 ] || lc_info "--strand-ok: removing anyway;$report each head is kept under refs/keep/ and the branches are KEPT"

  # 1b. Uncommitted or untracked work (core, every nested extension worktree, the private copies).
  local dirty="" d
  d="$(dirty_lines "$path")"; [ -z "$d" ] || dirty="$dirty core: $(printf '%s\n' "$d" | wc -l | tr -d ' ') path(s) (e.g. $(printf '%s\n' "$d" | head -n 3 | sed 's/^...//' | tr '\n' ' '));"
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    d="$(dirty_lines "$dir")"; [ -z "$d" ] || dirty="$dirty ${dir#"$path"/}: $(printf '%s\n' "$d" | wc -l | tr -d ' ') path(s);"
  done < <(ext_dirs "$path")
  d="$(private_copy_diffs "$path" | tr '\n' ' ')"; [ -z "$d" ] || dirty="$dirty private copies differ from main: $d;"
  if [ -n "$dirty" ] && [ "$discard_dirty" -eq 0 ]; then
    lc_info "UNCOMMITTED:$dirty"
    LC_DIE_CODE=1 lc_die "refusing to remove $path: it holds uncommitted or untracked work that a removal would delete. Commit or move it first."
  fi
  [ -z "$dirty" ] || lc_info "--discard-dirty: discarding uncommitted work;$dirty"

  # 2. Live processes.
  if [ "$busy_ok" -eq 0 ]; then
    local busy; busy="$(busy_pids "$path" | tr '\n' ' ')"
    [ -z "${busy// /}" ] || LC_DIE_CODE=1 lc_die "process(es) ${busy}have their working directory inside $path; stop them, or pass --busy-ok"
  fi

  # 3. Branches to delete afterwards (only when nothing is stranded).
  local core_branch; core_branch="$(git -C "$path" symbolic-ref --quiet --short HEAD || true)"
  local -a ext_branches=()
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    ext_branches+=("${dir#"$path"/}|$(git -C "$dir" symbolic-ref --quiet --short HEAD || true)")
  done < <(ext_dirs "$path")

  # 4. The lane's test database.
  local suffix; suffix="$(sed -n 's/^TEST_ENV_NUMBER=//p' "$path/server/.env.test.local" 2>/dev/null | head -1)"
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

  # 4b. --strand-ok: pin every head under refs/keep/ first. A detached extension HEAD has no branch, and
  # its commits are unreachable the moment the worktree (and its reflog) goes.
  if [ "$stranded" -eq 1 ]; then
    local stamp; stamp="$(date +%Y%m%dT%H%M%S)"
    git -C "$MAIN" update-ref "refs/keep/$(basename "$path")/$stamp" "$(git -C "$path" rev-parse HEAD)"
    lc_info "  kept core head under refs/keep/$(basename "$path")/$stamp"
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      git -C "$MAIN/${dir#"$path"/}" update-ref "refs/keep/$(basename "$path")/$stamp" "$(git -C "$dir" rev-parse HEAD)"
      lc_info "  kept ${dir#"$path"/} head under refs/keep/$(basename "$path")/$stamp"
    done < <(ext_dirs "$path")
  fi

  # 5. Remove, release, delete merged branches.
  "$SELF_DIR/prepare-worktree.sh" "$path" --remove >&2
  with_ledger_lock release_lane "$path"
  lc_info "lane released"
  if [ "$stranded" -eq 0 ]; then
    if [ -n "$core_branch" ] && git -C "$MAIN" show-ref --verify --quiet "refs/heads/$core_branch"; then
      git -C "$MAIN" branch -q -D "$core_branch" && lc_info "deleted branch $core_branch"
    fi
    local entry sub br
    for entry in "${ext_branches[@]}"; do
      sub="${entry%%|*}"; br="${entry#*|}"
      [ -n "$br" ] && git -C "$MAIN/$sub" show-ref --verify --quiet "refs/heads/$br" &&
        git -C "$MAIN/$sub" branch -q -D "$br" && lc_info "deleted branch $br in $sub"
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
      n="$(ahead_count "$ext")"
      exts="$(jq -c --arg k "${ext#"$wt"/}" --arg v "$n" '. + {($k): $v}' <<<"$exts")"
    done < <(ext_dirs "$wt")
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
