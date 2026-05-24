#!/usr/bin/env bash
# verify-submodule-pointers.sh — pre-push gate for parent-platform submodule integrity.
#
# Reads .gitmodules in the parent repo, then for each submodule:
#   1. Looks up the parent's pointer commit via `git ls-tree HEAD <path>`
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

# Resolve the list of submodule paths from .gitmodules — the canonical
# source of "what the parent thinks the submodules are." Skip silently
# if .gitmodules is absent (e.g., test fixtures or stripped checkouts).
if [[ ! -f .gitmodules ]]; then
  echo "[verify-submodule-pointers] no .gitmodules in $REPO_ROOT — nothing to check"
  exit 0
fi

# Use --name-only to get the section names, then look up each path.
SECTIONS=$(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $1}' | sed 's/^submodule\.//; s/\.path$//')

FAILURES=()

check_pointer_reachable() {
  local path="$1"
  local pointer="$2"
  local sm_remote="$3"

  # First confirm the remote exists in the submodule's clone. If not,
  # skip with a note — this is normal for fresh clones that haven't
  # added the private upstream yet.
  if ! git -C "$path" remote get-url "$sm_remote" >/dev/null 2>&1; then
    echo "  [skip] submodule $path has no remote named '$sm_remote' — skipping"
    return 0
  fi

  # Cheap check first: pointer already in local clone? If not, we can't
  # even ask the remote intelligently. (This is rare — usually the
  # pointer IS local because the operator just bumped it.)
  if ! git -C "$path" cat-file -e "${pointer}^{commit}" 2>/dev/null; then
    echo "  [warn] submodule $path: pointer $pointer not in local clone — fetching $sm_remote"
    git -C "$path" fetch --quiet "$sm_remote" 2>/dev/null || true
    if ! git -C "$path" cat-file -e "${pointer}^{commit}" 2>/dev/null; then
      FAILURES+=("$path: pointer $pointer not found anywhere (not local, not on $sm_remote)")
      return 1
    fi
  fi

  # Now the real check: is the pointer reachable from any ref on the
  # remote? We use `git branch --remotes --contains` after a refresh.
  # If the result is empty for $sm_remote, the commit isn't on any
  # branch on that remote — meaning a fresh clone of the parent would
  # fail to resolve this pointer.
  git -C "$path" fetch --quiet "$sm_remote" 2>/dev/null || true
  local containing
  containing=$(git -C "$path" branch --remotes --contains "$pointer" 2>/dev/null \
                 | grep -E "^[[:space:]]+${sm_remote}/" || true)
  if [[ -z "$containing" ]]; then
    FAILURES+=("$path: pointer $pointer not on any branch of remote '$sm_remote'")
    return 1
  fi
  echo "  ✓ $path: pointer $pointer reachable on $sm_remote ($(echo "$containing" | head -1 | xargs))"
  return 0
}

echo "[verify-submodule-pointers] checking $(echo "$SECTIONS" | wc -l | xargs) submodule(s)..."
for name in $SECTIONS; do
  path=$(git config --file .gitmodules "submodule.${name}.path")
  if [[ ! -d "$path" ]]; then
    echo "  [skip] $path not present in checkout (not initialized) — skipping"
    continue
  fi

  # Parent's pointer commit for this submodule.
  pointer=$(git ls-tree HEAD "$path" | awk '{print $3}')
  if [[ -z "$pointer" ]]; then
    echo "  [skip] $path not in HEAD tree — skipping"
    continue
  fi

  echo "submodule $name (path=$path, pointer=$pointer):"

  # Pick which remote(s) to verify against:
  #   - If PUSH_REMOTE is set, only check that remote on the submodule
  #     (mirrors the parent's push destination).
  #   - Otherwise verify against both 'origin' and 'ipnode' when
  #     present (the conventional dual-remote pair for this repo).
  if [[ -n "$PUSH_REMOTE" ]]; then
    check_pointer_reachable "$path" "$pointer" "$PUSH_REMOTE" || true
  else
    for remote in origin ipnode; do
      check_pointer_reachable "$path" "$pointer" "$remote" || true
    done
  fi
done

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
