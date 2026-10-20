#!/usr/bin/env bash
# compute-build-info.sh -- print BUILD_INFO.json for the current checkout.
#
#   scripts/compute-build-info.sh [--branch NAME]
#
# The CI side of Powernode::Version (server/config/version.rb): the same
# version format, derived from release tags and never from a file:
#   exact tag X.Y.Z                    -> X.Y.Z
#   branch release/X.Y.Z, hotfix/X.Y.Z -> X.Y.Z-rc.N+sha
#   otherwise                          -> latest tag, minor+1, patch 0: -dev.N+sha
#   no tags reachable                  -> 0.0.0-dev.0+sha
# `release` is true only for an exact X.Y.Z tag at the tip of master.
#
# Needs a FULL clone with tags (actions/checkout fetch-depth: 0). The branch is
# --branch, else $GITHUB_REF_NAME / $GITEA_REF_NAME, else the checked-out branch.
# Pass the output to image builds as POWERNODE_BUILD_INFO_JSON.
set -euo pipefail

branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) branch="${2:?--branch needs a value}"; shift 2 ;;
    *) echo "usage: compute-build-info.sh [--branch NAME]" >&2; exit 2 ;;
  esac
done
[ -n "$branch" ] || branch="${GITHUB_REF_NAME:-${GITEA_REF_NAME:-}}"
[ -n "$branch" ] || branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
# A detached HEAD prints the literal "HEAD", which is not a branch.
[ "$branch" != "HEAD" ] || branch="unknown"

sha="$(git rev-parse --verify HEAD)"
short="${sha:0:7}"
tag="$(git tag --points-at HEAD | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)"
describe="$(git describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)"

if [ -n "$tag" ]; then
  version="$tag"
elif [[ "$describe" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-([0-9]+)-g[0-9a-f]+$ ]]; then
  major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" ahead="${BASH_REMATCH[4]}"
  if [[ "$branch" =~ ^(release|hotfix)/([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    version="${BASH_REMATCH[2]}-rc.${ahead}+${short}"
  else
    version="${major}.$((minor + 1)).0-dev.${ahead}+${short}"
  fi
else
  version="0.0.0-dev.0+${short}"
fi

release=false
if [ -n "$tag" ]; then
  master_sha="$(git rev-parse --verify -q "refs/remotes/origin/master" || git rev-parse --verify -q "refs/heads/master" || true)"
  [ -n "$master_sha" ] && [ "$master_sha" = "$sha" ] && release=true
fi

printf '{"version":"%s","sha":"%s","short_sha":"%s","branch":"%s","tag":%s,"release":%s,"built_at":"%s","source":"ci"}\n' \
  "$version" "$sha" "$short" "$branch" \
  "$( [ -n "$tag" ] && printf '"%s"' "$tag" || printf null )" "$release" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
