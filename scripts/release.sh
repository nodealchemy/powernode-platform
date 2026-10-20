#!/usr/bin/env bash
# release.sh -- cut a release: running this script IS the release.
#
#   scripts/release.sh X.Y.Z [--dry-run]
#
# Nothing in the tree hand-maintains a version; every version is set here, from
# the release tag (X.Y.Z, no "v" prefix). Run it from the checked-out
# release/X.Y.Z (or hotfix/X.Y.Z) branch of the parent repo, with every submodule on its own
# release/X.Y.Z branch, all trees clean.
#
# What it does:
#   1. Asserts: clean trees, branch release/X.Y.Z (parent and submodules), and
#      no X.Y.Z tag in the parent or any submodule.
#   2. Stamps every extension gemspec (spec.version -- Bundler needs a literal,
#      this script is its only writer), runs `bundle lock` in server/ and
#      `npm version X.Y.Z --no-git-tag-version` in the root and frontend/.
#   3. Commits inside each submodule, then the parent (one commit per concern).
#   4. Merges release/X.Y.Z into master with --no-ff (submodules first, so the
#      parent records their merge commits), tags X.Y.Z on master and on every
#      submodule's master merge commit, and pushes master and the tags.
#   5. Back-merges to develop (submodules, then the parent, then re-points the
#      parent's gitlinks at the submodules' develop tips) and pushes.
#
# --dry-run runs step 1 for real and PRINTS steps 2-5 without changing anything
# (no stamp, no commit, no merge, no tag, no push).
#
# Environment: RELEASE_REMOTE (default origin), RELEASE_MASTER (default master),
# RELEASE_DEVELOP (default develop).
set -euo pipefail

REMOTE="${RELEASE_REMOTE:-origin}"
MASTER="${RELEASE_MASTER:-master}"
DEVELOP="${RELEASE_DEVELOP:-develop}"

die() { echo "release.sh: $*" >&2; exit 1; }
usage() { echo "usage: scripts/release.sh X.Y.Z [--dry-run]" >&2; exit 2; }

VERSION=""
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    -*) echo "release.sh: unknown option $arg" >&2; usage ;;
    *) [ -z "$VERSION" ] || usage; VERSION="$arg" ;;
  esac
done
[ -n "$VERSION" ] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z with no \"v\" prefix (got '$VERSION')"
BRANCH="release/$VERSION"
# A hotfix is released from hotfix/X.Y.Z instead.
if [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "hotfix/$VERSION" ]; then BRANCH="hotfix/$VERSION"; fi

ROOT="$(git rev-parse --show-toplevel)" || die "not inside a git repository"
cd "$ROOT"

# Submodules from .gitmodules (initialized ones only).
SUBS=()
if [ -f .gitmodules ]; then
  while read -r _ path; do
    [ -e "$path/.git" ] && SUBS+=("$path")
  done < <(git config -f .gitmodules --get-regexp '\.path$' || true)
fi

say()  { echo "[release $VERSION] $*"; }
plan() { echo "[dry-run] $*"; }

# run <desc> <cmd...> : execute, or print under --dry-run.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then plan "$*"; else "$@"; fi
}

# ---- 1. assertions (always real, also under --dry-run) ----------------------
check_repo() {
  local dir="$1" label="$2"
  [ -z "$(git -C "$dir" status --porcelain)" ] || die "$label working tree is not clean"
  local cur
  cur="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
  [ "$cur" = "$BRANCH" ] || die "$label must be on branch $BRANCH (is on '$cur')"
  if git -C "$dir" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
    die "tag $VERSION already exists in $label"
  fi
  if git -C "$dir" ls-remote --exit-code --tags "$REMOTE" "refs/tags/$VERSION" >/dev/null 2>&1; then
    die "tag $VERSION already exists on the remote of $label"
  fi
  git -C "$dir" rev-parse -q --verify "refs/heads/$MASTER" >/dev/null || die "$label has no local $MASTER branch"
  git -C "$dir" rev-parse -q --verify "refs/heads/$DEVELOP" >/dev/null || die "$label has no local $DEVELOP branch"
}

check_repo "$ROOT" "parent"
for s in "${SUBS[@]+"${SUBS[@]}"}"; do check_repo "$ROOT/$s" "submodule $s"; done
say "preconditions OK (parent${SUBS[*]:+ + ${#SUBS[@]} submodule(s)}) on $BRANCH"
[ "$DRY_RUN" -eq 1 ] && plan "no changes will be made"

# ---- 2. stamp ---------------------------------------------------------------
stamp_gemspecs() {
  local sub="$1" f
  while IFS= read -r f; do
    sed -i -E "s/^([[:space:]]*spec\.version[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\1\"$VERSION\"/" "$f"
  done < <(find "$ROOT/$sub" -maxdepth 3 -name '*.gemspec' -not -path '*/node_modules/*' 2>/dev/null)
}

for s in "${SUBS[@]+"${SUBS[@]}"}"; do
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "stamp spec.version = \"$VERSION\" in $s/**/*.gemspec"
  else
    stamp_gemspecs "$s"
  fi
done

if [ -f server/Gemfile ]; then
  if [ "$DRY_RUN" -eq 1 ]; then plan "(cd server && bundle lock)"; else (cd server && bundle lock); fi
fi
for pkg in . frontend; do
  if [ -f "$pkg/package.json" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      plan "(cd $pkg && npm version $VERSION --no-git-tag-version)"
    else
      (cd "$pkg" && npm version "$VERSION" --no-git-tag-version --allow-same-version >/dev/null)
    fi
  fi
done

# ---- 3. commits -------------------------------------------------------------
for s in "${SUBS[@]+"${SUBS[@]}"}"; do
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "git -C $s commit -m 'chore(release): stamp gemspec version $VERSION'"
  elif [ -n "$(git -C "$s" status --porcelain)" ]; then
    git -C "$s" add -u
    git -C "$s" commit -q -m "chore(release): stamp gemspec version $VERSION"
  fi
done

# ---- 4. merge to master, tag, push -------------------------------------------
# Submodules first so the parent's gitlinks record their master merge commits.
merge_to() {
  local dir="$1" into="$2" from="$3" msg="$4"
  git -C "$dir" checkout -q "$into"
  git -C "$dir" merge -q --no-ff "$from" -m "$msg"
}

for s in "${SUBS[@]+"${SUBS[@]}"}"; do
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "$s: merge --no-ff $BRANCH into $MASTER; tag $VERSION; push $MASTER + tag $VERSION"
  else
    merge_to "$ROOT/$s" "$MASTER" "$BRANCH" "Merge $BRANCH into $MASTER"
    git -C "$ROOT/$s" tag "$VERSION"
    git -C "$ROOT/$s" push -q "$REMOTE" "$MASTER" "refs/tags/$VERSION"
  fi
done

if [ "$DRY_RUN" -eq 1 ]; then
  plan "parent: commit gitlinks + server/Gemfile.lock 'chore(release): pin extensions and lock at $VERSION'"
  plan "parent: commit package.json + package-lock.json (root, frontend) 'chore(release): stamp package versions $VERSION'"
  plan "parent: merge --no-ff $BRANCH into $MASTER; tag $VERSION on $MASTER; push $MASTER + tag $VERSION"
else
  # The submodule checkouts now sit on master merge commits: pin those, by concern.
  pins=()
  for s in "${SUBS[@]+"${SUBS[@]}"}"; do pins+=("$s"); done
  [ -f server/Gemfile.lock ] && pins+=(server/Gemfile.lock)
  if [ "${#pins[@]}" -gt 0 ] && [ -n "$(git status --porcelain -- "${pins[@]}")" ]; then
    git add -- "${pins[@]}"
    git commit -q -m "chore(release): pin extensions and lock at $VERSION"
  fi
  pkgs=()
  for f in package.json package-lock.json frontend/package.json frontend/package-lock.json; do
    [ -f "$f" ] && pkgs+=("$f")
  done
  if [ "${#pkgs[@]}" -gt 0 ] && [ -n "$(git status --porcelain -- "${pkgs[@]}")" ]; then
    git add -- "${pkgs[@]}"
    git commit -q -m "chore(release): stamp package versions $VERSION"
  fi
  [ -z "$(git status --porcelain)" ] || die "parent tree unexpectedly dirty after stamping; aborting before merge"
  merge_to "$ROOT" "$MASTER" "$BRANCH" "Merge $BRANCH into $MASTER"
  git tag "$VERSION"
  git push -q "$REMOTE" "$MASTER" "refs/tags/$VERSION"
fi

# ---- 5. back-merge to develop --------------------------------------------------
for s in "${SUBS[@]+"${SUBS[@]}"}"; do
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "$s: back-merge $MASTER into $DEVELOP; push $DEVELOP"
  else
    merge_to "$ROOT/$s" "$DEVELOP" "$MASTER" "Merge $MASTER ($VERSION) back into $DEVELOP"
    git -C "$ROOT/$s" push -q "$REMOTE" "$DEVELOP"
  fi
done
if [ "$DRY_RUN" -eq 1 ]; then
  plan "parent: back-merge $MASTER into $DEVELOP; point extensions at their $DEVELOP tips; push $DEVELOP"
else
  merge_to "$ROOT" "$DEVELOP" "$MASTER" "Merge $MASTER ($VERSION) back into $DEVELOP"
  if [ "${#SUBS[@]}" -gt 0 ] && [ -n "$(git status --porcelain -- "${SUBS[@]}")" ]; then
    git add -- "${SUBS[@]}"
    git commit -q -m "chore(release): point extensions at $DEVELOP after the $VERSION back-merge"
  fi
  git push -q "$REMOTE" "$DEVELOP"
  say "released $VERSION: tagged $MASTER, pushed tags, back-merged to $DEVELOP"
  say "the tag push triggers .gitea/workflows/release.yml (docker + module build)"
fi
[ "$DRY_RUN" -eq 1 ] && plan "dry-run complete: $VERSION would be released as above"
exit 0
