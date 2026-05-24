#!/usr/bin/env bash
# check-lockfile-public-only.sh — fail if server/Gemfile.lock declares a
# powernode_* gem whose corresponding extension isn't listed in
# .gitmodules. This is the "did the maintainer forget to regenerate the
# public lockfile before commit?" gate for CI + the pre-commit hook.
#
# A passing run means CI's default `bundle install --without
# private_extensions` will succeed in frozen mode on a clone that
# doesn't have the private submodules.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

LOCKFILE="server/Gemfile.lock"
[[ -f "$LOCKFILE" ]] || { echo "skip: no $LOCKFILE"; exit 0; }

if [[ ! -f .gitmodules ]]; then
  echo "skip: no .gitmodules — cannot derive public-extension allow-list"
  exit 0
fi

# Public extensions: slugs listed in .gitmodules. Strip trailing
# whitespace per line (not all whitespace — that would concatenate
# every slug into one false-match-prone token).
public_slugs=$(awk -F'extensions/' '/^[[:space:]]*path[[:space:]]*=[[:space:]]*extensions\//{
  slug = $2
  gsub(/[[:space:]]+$/, "", slug)
  print slug
}' .gitmodules | tr '\n' ' ')
# Convert hyphens to underscores so we can match against the
# powernode_<slug> gem-name convention.
public_gems=""
for s in $public_slugs; do
  # The slug-as-gem-name uses underscore in place of hyphen.
  underscored="${s//-/_}"
  public_gems+=" powernode_$underscored"
done

# Extract powernode_* lines from Gemfile.lock DEPENDENCIES section.
declared=$(awk '/^DEPENDENCIES/{flag=1;next} /^[^[:space:]]/{flag=0} flag && /^[[:space:]]+powernode_/{print $1}' "$LOCKFILE" \
  | sed 's/!*$//')

violations=()
while IFS= read -r dep; do
  [[ -z "$dep" ]] && continue
  if [[ " $public_gems " != *" $dep "* ]]; then
    violations+=("$dep")
  fi
done <<< "$declared"

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "✗ check-lockfile-public-only: server/Gemfile.lock declares private-extension gem(s) CI can't resolve:"
  for v in "${violations[@]}"; do echo "    $v"; done
  echo ""
  echo "Fix: regenerate the lockfile without private extensions:"
  echo "    bash scripts/regen-public-lockfile.sh"
  echo ""
  echo "Then commit the regenerated server/Gemfile.lock."
  exit 1
fi

echo "✓ check-lockfile-public-only: only public-extension gems declared"
