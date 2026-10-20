#!/usr/bin/env bash
# release.sh -- cut a release: running this script IS the release.
#
#   scripts/release.sh X.Y.Z [--dry-run]
#
# Nothing in the tree hand-maintains a version; every version is set here, from
# the release tag (X.Y.Z, no "v" prefix). Run it from the checked-out
# release/X.Y.Z (or hotfix/X.Y.Z) branch of the parent repo, with every
# submodule on the same branch, all trees clean.
#
# Order of work (ALL local work first, pushes only at the very end):
#   1. Fetch every remote of every repo. Assert clean trees, the release branch,
#      no X.Y.Z tag on ANY remote (a local tag from an earlier, interrupted run is
#      the resume signal), and local master/develop equal to the remote tips.
#   2. Local work. Submodules: stamp gemspec versions, commit, merge --no-ff to
#      master, tag X.Y.Z, back-merge master into develop. Parent: run
#      `bundle lock`, `npm version X.Y.Z --no-git-tag-version` (root + frontend),
#      commit per concern, merge --no-ff to master, tag X.Y.Z, back-merge into
#      develop (a conflict that touches only submodule gitlinks is resolved by
#      taking the submodule's develop tip; any other conflict aborts), then
#      point the gitlinks at the submodules' develop tips.
#   3. Gate: scripts/validate.sh in the parent (the commit hooks already ran).
#   4. Push, submodules first then the parent; branches first, then the tag;
#      every repo to EVERY configured remote, gitea first.
#
# A failed push prints exact resume instructions. Re-running the same command is
# safe: existing local tags/commits are detected and the script continues.
#
# Remotes: by default every one of {gitea, origin} that a repo has, gitea first
# (gitea fires .gitea/workflows/release.yml; origin is the GitHub mirror).
# Override with RELEASE_REMOTES="gitea origin" (space or comma separated).
#
# --dry-run runs step 1 for real (including the fetch) and PRINTS the rest.
#
# Environment: RELEASE_REMOTES, RELEASE_MASTER (master), RELEASE_DEVELOP (develop),
# RELEASE_SKIP_VALIDATE=1 (skip step 3).
set -euo pipefail

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

SUBS=()
if [ -f .gitmodules ]; then
  while read -r _ path; do
    [ -e "$path/.git" ] && SUBS+=("$path")
  done < <(git config -f .gitmodules --get-regexp '\.path$' || true)
fi

say()  { echo "[release $VERSION] $*"; }
plan() { echo "[dry-run] $*"; }

# remotes_of <dir> : the remotes to use for a repo, gitea first.
remotes_of() {
  local dir="$1" r have out=()
  have="$(git -C "$dir" remote)"
  if [ -n "${RELEASE_REMOTES:-}" ]; then
    for r in $(echo "$RELEASE_REMOTES" | tr ',' ' '); do
      grep -qx "$r" <<<"$have" || die "$dir has no remote '$r' (RELEASE_REMOTES=$RELEASE_REMOTES)"
      out+=("$r")
    done
  else
    for r in gitea origin; do
      if grep -qx "$r" <<<"$have"; then out+=("$r"); fi
    done
  fi
  [ "${#out[@]}" -gt 0 ] || die "$dir has none of the remotes gitea/origin (set RELEASE_REMOTES)"
  echo "${out[@]}"
}

has_local_tag() { git -C "$1" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; }

# ---- 1. assertions (real, also under --dry-run) -----------------------------
# A repo is "resumed" when the local tag already exists (an earlier run did the
# local work); its branch/equality checks are replaced by looser ones.
REPOS=("$ROOT"); LABELS=("parent")
for s in "${SUBS[@]+"${SUBS[@]}"}"; do REPOS+=("$ROOT/$s"); LABELS+=("submodule $s"); done
RESUMED=()

check_repo() {
  local dir="$1" label="$2" idx="$3" r b code lsout local_sha remote_sha cur remotes
  remotes="$(remotes_of "$dir")"

  for r in $remotes; do
    git -C "$dir" fetch -q --no-tags "$r" 2>/dev/null || die "cannot fetch remote '$r' of $label (unreachable?)"
  done

  # An existing tag on ANY remote blocks a fresh release. ls-remote --exit-code:
  # 0 = found, 2 = no such ref, anything else (128) = unreachable -> abort.
  for r in $remotes; do
    code=0
    lsout="$(git -C "$dir" ls-remote --exit-code --tags "$r" "refs/tags/$VERSION" 2>/dev/null)" || code=$?
    case "$code" in
      0)
        if has_local_tag "$dir"; then
          remote_sha="$(awk 'NR==1{print $1}' <<<"$lsout")"
          local_sha="$(git -C "$dir" rev-parse "refs/tags/$VERSION")"
          [ "$remote_sha" = "$local_sha" ] || die "tag $VERSION already exists on remote '$r' of $label at a different commit"
        else
          die "tag $VERSION already exists on remote '$r' of $label"
        fi ;;
      2) ;;
      *) die "cannot query tags on remote '$r' of $label (ls-remote exit $code; unreachable?)" ;;
    esac
  done

  if has_local_tag "$dir"; then
    # Only the result of an earlier run of THIS release counts as a resume: the
    # tag must be a commit that contains the release branch tip (the --no-ff merge).
    git -C "$dir" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null \
      && [ "$(git -C "$dir" rev-parse "refs/tags/$VERSION^{commit}")" != "$(git -C "$dir" rev-parse "refs/heads/$BRANCH")" ] \
      && git -C "$dir" merge-base --is-ancestor "refs/heads/$BRANCH" "refs/tags/$VERSION" \
      || die "tag $VERSION already exists locally in $label and is not the result of an earlier run on $BRANCH"
    RESUMED[idx]=1
    git -C "$dir" merge-base --is-ancestor "refs/tags/$VERSION" "refs/heads/$MASTER" \
      || die "local tag $VERSION in $label is not on $MASTER; resolve by hand"
    [ -z "$(git -C "$dir" status --porcelain --ignore-submodules=all)" ] || die "$label working tree is not clean"
    # Resume: the remotes must be behind us, never diverged.
    for r in $remotes; do
      for b in "$MASTER" "$DEVELOP"; do
        if git -C "$dir" rev-parse -q --verify "refs/remotes/$r/$b" >/dev/null; then
          git -C "$dir" merge-base --is-ancestor "refs/remotes/$r/$b" "refs/heads/$b" \
            || die "remote '$r' $b of $label has commits missing locally; cannot resume"
        fi
      done
    done
    return
  fi

  RESUMED[idx]=0
  [ -z "$(git -C "$dir" status --porcelain --ignore-submodules=all)" ] || die "$label working tree is not clean"
  cur="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
  [ "$cur" = "$BRANCH" ] || die "$label must be on branch $BRANCH (is on '$cur')"
  for b in "$MASTER" "$DEVELOP"; do
    git -C "$dir" rev-parse -q --verify "refs/heads/$b" >/dev/null || die "$label has no local $b branch"
    for r in $remotes; do
      git -C "$dir" rev-parse -q --verify "refs/remotes/$r/$b" >/dev/null \
        || die "remote '$r' of $label has no $b branch"
      [ "$(git -C "$dir" rev-parse "refs/heads/$b")" = "$(git -C "$dir" rev-parse "refs/remotes/$r/$b")" ] \
        || die "local $b of $label does not equal the tip of remote '$r' (pull or push first)"
    done
  done
}

for i in "${!REPOS[@]}"; do check_repo "${REPOS[$i]}" "${LABELS[$i]}" "$i"; done
say "preconditions OK (parent${SUBS[*]:+ + ${#SUBS[@]} submodule(s)}); remotes: $(remotes_of "$ROOT")"

# ---- plan (dry-run) ---------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  plan "no changes will be made"
  for i in "${!REPOS[@]}"; do
    if [ "${RESUMED[$i]}" = "1" ]; then plan "${LABELS[$i]}: local tag $VERSION exists -> local work is skipped (resume)"; fi
  done
  for s in "${SUBS[@]+"${SUBS[@]}"}"; do
    plan "$s: stamp spec.version = \"$VERSION\" in **/*.gemspec; commit; merge --no-ff $BRANCH into $MASTER; tag $VERSION; back-merge $MASTER into $DEVELOP"
  done
  if [ -f server/Gemfile ]; then plan "(cd server && bundle lock)"; fi
  for pkg in . frontend; do
    if [ -f "$pkg/package.json" ]; then plan "(cd $pkg && npm version $VERSION --no-git-tag-version)"; fi
  done
  plan "parent: commit 'chore(release): pin extensions and lock at $VERSION' and 'chore(release): stamp package versions $VERSION'"
  plan "parent: merge --no-ff $BRANCH into $MASTER; tag $VERSION; back-merge into $DEVELOP (gitlink-only conflicts take the submodule develop tip); point gitlinks at develop tips"
  if [ -x scripts/validate.sh ]; then plan "gate: scripts/validate.sh"; fi
  for s in "${SUBS[@]+"${SUBS[@]}"}"; do plan "push $s -> $(remotes_of "$ROOT/$s"): $MASTER $DEVELOP, then tag $VERSION"; done
  plan "push parent -> $(remotes_of "$ROOT"): $MASTER $DEVELOP, then tag $VERSION"
  plan "dry-run complete: $VERSION would be released as above"
  exit 0
fi

# ---- 2. local work ----------------------------------------------------------
merge_to() {
  local dir="$1" into="$2" from="$3" msg="$4"
  git -C "$dir" checkout -q "$into"
  git -C "$dir" merge -q --no-ff "$from" -m "$msg"
}

stamp_gemspecs() {
  local f
  while IFS= read -r f; do
    sed -i -E "s/^([[:space:]]*spec\.version[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\1\"$VERSION\"/" "$f"
  done < <(find "$1" -maxdepth 3 -name '*.gemspec' -not -path '*/node_modules/*' 2>/dev/null)
}

for idx in "${!SUBS[@]}"; do
  s="${SUBS[$idx]}"; dir="$ROOT/$s"; i=$((idx + 1))
  if [ "${RESUMED[$i]}" != "1" ]; then
    stamp_gemspecs "$dir"
    if [ -n "$(git -C "$dir" status --porcelain)" ]; then
      git -C "$dir" add -u
      git -C "$dir" commit -q -m "chore(release): stamp gemspec version $VERSION"
    fi
    merge_to "$dir" "$MASTER" "$BRANCH" "Merge $BRANCH into $MASTER"
    git -C "$dir" tag "$VERSION"
  fi
  if ! git -C "$dir" merge-base --is-ancestor "$MASTER" "$DEVELOP"; then
    git -C "$dir" checkout -q "$DEVELOP"
    if ! git -C "$dir" merge -q --no-ff "$MASTER" -m "Merge $MASTER ($VERSION) back into $DEVELOP"; then
      git -C "$dir" merge --abort 2>/dev/null || true
      die "back-merge of $MASTER into $DEVELOP failed in submodule $s (conflict); nothing was pushed. Resolve by hand, then re-run scripts/release.sh $VERSION"
    fi
  fi
done

if [ "${RESUMED[0]}" != "1" ]; then
  if [ -f server/Gemfile ]; then (cd server && bundle lock); fi
  for pkg in . frontend; do
    if [ -f "$pkg/package.json" ]; then (cd "$pkg" && npm version "$VERSION" --no-git-tag-version --allow-same-version >/dev/null); fi
  done
  # The release pins the TAGGED master merge commits of the submodules.
  for s in "${SUBS[@]+"${SUBS[@]}"}"; do git -C "$ROOT/$s" checkout -q "$VERSION"; done
  pins=("${SUBS[@]+"${SUBS[@]}"}")
  if [ -f server/Gemfile.lock ]; then pins+=(server/Gemfile.lock); fi
  if [ "${#pins[@]}" -gt 0 ] && [ -n "$(git status --porcelain -- "${pins[@]}")" ]; then
    git add -- "${pins[@]}"
    git commit -q -m "chore(release): pin extensions and lock at $VERSION"
  fi
  pkgs=()
  for f in package.json package-lock.json frontend/package.json frontend/package-lock.json; do
    if [ -f "$f" ]; then pkgs+=("$f"); fi
  done
  if [ "${#pkgs[@]}" -gt 0 ] && [ -n "$(git status --porcelain -- "${pkgs[@]}")" ]; then
    git add -- "${pkgs[@]}"
    git commit -q -m "chore(release): stamp package versions $VERSION"
  fi
  [ -z "$(git status --porcelain --ignore-submodules=all)" ] || die "parent tree unexpectedly dirty after stamping; aborting before merge"
  merge_to "$ROOT" "$MASTER" "$BRANCH" "Merge $BRANCH into $MASTER"
  git tag "$VERSION"
fi

# Back-merge the parent into develop (idempotent), resolving gitlink-only conflicts.
if ! git merge-base --is-ancestor "$MASTER" "$DEVELOP"; then
  for s in "${SUBS[@]+"${SUBS[@]}"}"; do git -C "$ROOT/$s" checkout -q "$DEVELOP"; done
  git checkout -q "$DEVELOP"
  if ! git merge -q --no-ff "$MASTER" -m "Merge $MASTER ($VERSION) back into $DEVELOP" >/dev/null 2>&1; then
    conflicts="$(git diff --name-only --diff-filter=U)"
    if [ -z "$conflicts" ]; then
      git merge --abort 2>/dev/null || true
      die "back-merge of $MASTER into $DEVELOP failed without a conflict list; aborted. Nothing was pushed."
    fi
    while IFS= read -r path; do
      is_sub=0
      for s in "${SUBS[@]+"${SUBS[@]}"}"; do
        if [ "$path" = "$s" ]; then is_sub=1; fi
      done
      if [ "$is_sub" -ne 1 ]; then
        git merge --abort 2>/dev/null || true
        die "non-gitlink conflict in '$path' while back-merging $MASTER into $DEVELOP; merge aborted. Nothing was pushed. Resolve by hand (merge $MASTER into $DEVELOP), then re-run scripts/release.sh $VERSION"
      fi
    done <<<"$conflicts"
    # Gitlink-only: take the submodule's develop tip (checked out above).
    while IFS= read -r path; do git add -- "$path"; done <<<"$conflicts"
    git commit -q --no-edit
  fi
fi
for s in "${SUBS[@]+"${SUBS[@]}"}"; do git -C "$ROOT/$s" checkout -q "$DEVELOP"; done
if [ "${#SUBS[@]}" -gt 0 ] && [ -n "$(git status --porcelain -- "${SUBS[@]}")" ]; then
  git add -- "${SUBS[@]}"
  git commit -q -m "chore(release): point extensions at $DEVELOP after the $VERSION back-merge"
fi

# ---- 3. gate ----------------------------------------------------------------
if [ "${RELEASE_SKIP_VALIDATE:-0}" != "1" ] && [ -x scripts/validate.sh ]; then
  say "running the parent gate: scripts/validate.sh"
  scripts/validate.sh || die "scripts/validate.sh failed; nothing was pushed. Fix it, then re-run scripts/release.sh $VERSION (local work is kept)"
fi

# ---- 4. push (submodules first, then parent; branches, then the tag) --------
push_failed() {
  local label="$1" r="$2" s rr
  {
    echo "release.sh: PUSH FAILED for $label to remote '$r'."
    echo "All local work is complete (merged, tagged, back-merged). To resume:"
    echo "  fix the remote/credentials problem, then re-run: scripts/release.sh $VERSION"
    echo "  (idempotent: it detects the local tag and commits and only pushes what is missing)"
    echo "Or push by hand, submodules first, branches before the tag:"
    for s in "${SUBS[@]+"${SUBS[@]}"}"; do
      for rr in $(remotes_of "$ROOT/$s"); do
        echo "  git -C $ROOT/$s push $rr $MASTER $DEVELOP && git -C $ROOT/$s push $rr refs/tags/$VERSION"
      done
    done
    for rr in $(remotes_of "$ROOT"); do
      echo "  git -C $ROOT push $rr $MASTER $DEVELOP && git -C $ROOT push $rr refs/tags/$VERSION"
    done
  } >&2
  exit 1
}

push_repo() {
  local dir="$1" label="$2" r
  for r in $(remotes_of "$dir"); do
    say "pushing $label to $r"
    git -C "$dir" push -q "$r" "$MASTER" "$DEVELOP" || push_failed "$label" "$r"
    git -C "$dir" push -q "$r" "refs/tags/$VERSION" || push_failed "$label" "$r"
  done
}

for s in "${SUBS[@]+"${SUBS[@]}"}"; do push_repo "$ROOT/$s" "submodule $s"; done
push_repo "$ROOT" "parent"

say "released $VERSION: tagged $MASTER, pushed to $(remotes_of "$ROOT"), back-merged to $DEVELOP"
say "the tag push to gitea triggers .gitea/workflows/release.yml (docker + module build)"
