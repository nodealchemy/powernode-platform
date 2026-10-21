#!/usr/bin/env bash
# verify-submodule-pointers.sh — pre-push gate for parent-platform submodule integrity.
#
# Reads .gitmodules in the parent repo, then for each submodule:
#   1. Looks up the parent's pointer via `git ls-tree <pushed sha> <path>` for each ref the
#      pre-push hook feeds on stdin (HEAD if none; deletes ignored)
#   2. Resolves which submodule remote(s) correspond to the .gitmodules URL
#      AND the conventional dual-remote pair (origin = public, ipnode = private)
#   3. Verifies the pointer commit is reachable on the relevant remote
#
# Exits 0 on success. Exits 1 if any pointer is unreachable, with a clear
# message naming the submodule, the orphaned commit, and the fix
# (push from inside the submodule).
#
# This catches the "publish-before-pointer" failure mode that broke
# build-platform-modules CI on 2026-05-24: parent platform's
# extensions/supply-chain pointer advanced to da97052 before that
# commit was pushed to either remote, so every `git submodule update
# --init --recursive` from CI died with `not our ref`.
#
# Usage:
#   bash scripts/verify-submodule-pointers.sh             # check all .gitmodules submodules
#   bash scripts/verify-submodule-pointers.sh --remote origin   # check against a specific remote only
#   PUSH_REMOTE=origin bash scripts/verify-submodule-pointers.sh # equivalent (used by pre-push hook)
#
# Invoked from .git/hooks/pre-push with PUSH_REMOTE set to the
# remote being pushed to (passed by git as $1 to the hook).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"
# git exports GIT_DIR (and friends) to hooks. Left set, every `git -C <submodule>` below
# would query the PARENT repository and report each pointer as missing. From here on, git
# discovers the repository from the working directory, which is what every call expects.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_PREFIX

PUSH_REMOTE="${PUSH_REMOTE:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) PUSH_REMOTE="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# git passes the push URL (not a remote name) as the hook's $1 when pushing to a bare URL.
# A submodule has no remote named like a URL, so the check would silently SKIP. Resolve the
# URL to a matching remote of this repo; when none matches, drop the filter so the default
# remote pair is checked. That is broader than skipping, but a submodule that lacks those
# remotes is still skipped per submodule ("[skip] ... has no remote named"), so a URL push
# to a repo whose submodules have neither remote is not verified.
# A remote NAME may itself contain '/' (e.g. team/fork), so an existing remote name is never a URL.
if [[ -n "$PUSH_REMOTE" && "$PUSH_REMOTE" == *[:/]* ]] && ! git remote | grep -Fxq -- "$PUSH_REMOTE"; then
  _norm() { local u="${1%/}"; echo "${u%.git}"; }
  _want="$(_norm "$PUSH_REMOTE")"
  _resolved=""
  while IFS= read -r _r; do
    while IFS= read -r _u; do
      if [[ "$(_norm "$_u")" == "$_want" ]]; then _resolved="$_r"; break 2; fi
    done < <({ git remote get-url --all "$_r"; git remote get-url --all --push "$_r"; } 2>/dev/null)
  done < <(git remote)
  if [[ -n "$_resolved" ]]; then
    echo "ℹ️  push target URL resolved to remote '$_resolved'" >&2
    PUSH_REMOTE="$_resolved"
  else
    echo "⚠️  push target '$PUSH_REMOTE' matches no remote; checking the default remotes (origin, ipnode)" >&2
    PUSH_REMOTE=""
  fi
fi

# Common git dir: differs from `git rev-parse --git-dir` in a linked worktree. The
# main checkout (where submodules are normally initialised) is its parent.
COMMON_DIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
MAIN_ROOT="$(dirname "$COMMON_DIR")"

FAILURES=()

# Resolve the git dir of a submodule: the worktree's own checkout if initialised,
# else the shared modules dir, else the main checkout's copy (linked worktrees
# usually have the submodule uninitialised). Fails if none is usable.
resolve_submodule_gitdir() {
  local name="$1" path="$2" cand
  for cand in "$REPO_ROOT/$path" "$COMMON_DIR/modules/$name" "$MAIN_ROOT/$path"; do
    # Must be a repo of its own (checkout .git, or a bare/modules git dir with HEAD) —
    # an empty submodule dir in a worktree would otherwise resolve to the PARENT repo.
    if [[ -e "$cand/.git" || -f "$cand/HEAD" ]] && git -C "$cand" rev-parse --git-dir >/dev/null 2>&1; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

check_pointer_reachable() {
  local path="$1"
  local pointer="$2"
  local sm_remote="$3"
  local sm_dir="$4"

  # First confirm the remote exists in the submodule's clone. If not,
  # skip with a note — this is normal for fresh clones that haven't
  # added the private upstream yet.
  if ! git -C "$sm_dir" remote get-url "$sm_remote" >/dev/null 2>&1; then
    echo "  [skip] submodule $path has no remote named '$sm_remote' — skipping"
    return 0
  fi

  # Cheap check first: pointer already in local clone? If not, we can't
  # even ask the remote intelligently. (This is rare — usually the
  # pointer IS local because the operator just bumped it.)
  if ! git -C "$sm_dir" cat-file -e "${pointer}^{commit}" 2>/dev/null; then
    echo "  [warn] submodule $path: pointer $pointer not in local clone — fetching $sm_remote"
    git -C "$sm_dir" fetch --quiet "$sm_remote" 2>/dev/null || true
    if ! git -C "$sm_dir" cat-file -e "${pointer}^{commit}" 2>/dev/null; then
      FAILURES+=("$path: pointer $pointer not found anywhere (not local, not on $sm_remote)")
      return 1
    fi
  fi

  # Now the real check: is the pointer reachable from any ref on the
  # remote? We use `git branch --remotes --contains` after a refresh.
  # If the result is empty for $sm_remote, the commit isn't on any
  # branch on that remote — meaning a fresh clone of the parent would
  # fail to resolve this pointer.
  git -C "$sm_dir" fetch --quiet "$sm_remote" 2>/dev/null || true
  local containing
  containing=$(git -C "$sm_dir" branch --remotes --contains "$pointer" 2>/dev/null \
                 | grep -E "^[[:space:]]+${sm_remote}/" || true)
  if [[ -z "$containing" ]]; then
    FAILURES+=("$path: pointer $pointer not on any branch of remote '$sm_remote'")
    return 1
  fi
  echo "  ✓ $path: pointer $pointer reachable on $sm_remote ($(echo "$containing" | head -1 | xargs))"
  return 0
}

# Verify every submodule gitlink recorded in commit $1 (label $2).
check_commit() {
  local sha="$1" label="$2" sections name path pointer sm_dir remote

  # .gitmodules is read from the commit itself (the canonical list of submodules
  # as THAT commit sees them). Absent => nothing to check for this commit.
  if ! sections=$(git config --blob "${sha}:.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null); then
    echo "[verify-submodule-pointers] $label: no .gitmodules in ${sha:0:12} — nothing to check"
    return 0
  fi
  sections=$(echo "$sections" | awk '{print $1}' | sed 's/^submodule\.//; s/\.path$//')

  echo "[verify-submodule-pointers] $label (${sha:0:12}): checking $(echo "$sections" | wc -l | xargs) submodule(s)..."
  for name in $sections; do
    path=$(git config --blob "${sha}:.gitmodules" "submodule.${name}.path")

    # The pushed commit's pointer for this submodule (not the checkout's HEAD).
    pointer=$(git ls-tree "$sha" "$path" | awk '$2 == "commit" {print $3}')
    if [[ -z "$pointer" ]]; then
      echo "  [skip] $path not a gitlink in ${sha:0:12} — skipping"
      continue
    fi

    if ! sm_dir=$(resolve_submodule_gitdir "$name" "$path"); then
      echo "  [skip] $path not present in checkout (not initialized) — skipping"
      continue
    fi

    echo "submodule $name (path=$path, pointer=$pointer):"

    # Pick which remote(s) to verify against:
    #   - If PUSH_REMOTE is set, only check that remote on the submodule
    #     (mirrors the parent's push destination).
    #   - Otherwise verify against both 'origin' and 'ipnode' when
    #     present (the conventional dual-remote pair for this repo).
    if [[ -n "$PUSH_REMOTE" ]]; then
      check_pointer_reachable "$path" "$pointer" "$PUSH_REMOTE" "$sm_dir" || true
    else
      for remote in origin ipnode; do
        check_pointer_reachable "$path" "$pointer" "$remote" "$sm_dir" || true
      done
    fi
  done
}

# pre-push protocol: stdin lines are `<local ref> <local sha> <remote ref> <remote sha>`.
# Check each pushed local sha; an all-zero sha is a delete and is ignored. With no
# ref lines at all (manual invocation, tty or empty stdin) fall back to HEAD.
SAW_REFS=0
SEEN=" "
if [[ ! -t 0 ]]; then
  while read -r local_ref local_sha _remote_ref _remote_sha || [[ -n "${local_ref:-}" ]]; do
    [[ -z "${local_ref:-}" ]] && continue
    SAW_REFS=1
    [[ "$local_sha" =~ ^0+$ ]] && continue
    [[ "$SEEN" == *" $local_sha "* ]] && continue
    SEEN+="$local_sha "
    check_commit "$local_sha" "$local_ref"
  done
fi
if [[ $SAW_REFS -eq 0 ]]; then
  check_commit "$(git rev-parse HEAD)" "HEAD"
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo ""
  echo "✗ Submodule pointer check FAILED:"
  for msg in "${FAILURES[@]}"; do echo "    $msg"; done
  echo ""
  echo "Fix: cd into each submodule above and push the missing commit:"
  echo "    cd extensions/<name>"
  echo "    git push origin <branch>"
  echo "    git push ipnode <branch>   # if dual-remoted"
  echo ""
  echo "Bypass (use only when intentional — e.g. publishing a parent commit"
  echo "that drops a submodule, not bumps it):"
  echo "    git push --no-verify"
  exit 1
fi

echo ""
echo "✓ All submodule pointers reachable on their remotes."
