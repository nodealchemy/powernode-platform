#!/usr/bin/env bash
# check-lockfile-public-only.sh — fail if the COMMITTED server/Gemfile.lock
# declares a powernode_* gem whose corresponding extension isn't listed in
# .gitmodules. The gate for CI + the pre-commit hook.
#
# A passing run means CI's default `bundle install` will succeed in frozen
# mode on a clone that doesn't have the private submodules (private
# extensions are excluded from the lockfile by default).
#
# IMPORTANT: this validates the STAGED/index content (`git show :<lock>`),
# NOT the working tree. A maintainer running full-mode dev has private-
# extension gems in their *working-tree* lock (the running services need
# them), but that must not block commits that don't touch the lock — only a
# lock actually being committed is checked. In CI the index (post-checkout)
# equals the committed file, so the check is identical there.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

LOCKFILE="server/Gemfile.lock"
# Prefer the staged/index blob; fall back to the working-tree file (e.g. a
# manual run outside git, or an untracked lock). Skip if neither exists.
if lock_content="$(git show ":$LOCKFILE" 2>/dev/null)" && [[ -n "$lock_content" ]]; then
  :
elif [[ -f "$LOCKFILE" ]]; then
  lock_content="$(cat "$LOCKFILE")"
else
  echo "skip: no $LOCKFILE (staged or working)"; exit 0
fi

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

# Extract powernode_* lines from the (staged) Gemfile.lock DEPENDENCIES section.
declared=$(printf '%s\n' "$lock_content" \
  | awk '/^DEPENDENCIES/{flag=1;next} /^[^[:space:]]/{flag=0} flag && /^[[:space:]]+powernode_/{print $1}' \
  | sed 's/!*$//')

violations=()
while IFS= read -r dep; do
  [[ -z "$dep" ]] && continue
  if [[ " $public_gems " != *" $dep "* ]]; then
    violations+=("$dep")
  fi
done <<< "$declared"

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "✗ check-lockfile-public-only: the STAGED server/Gemfile.lock declares"
  echo "  private-extension gem(s) CI can't resolve:"
  for v in "${violations[@]}"; do echo "    $v"; done
  echo ""
  echo "If you're in full-mode dev, just don't stage the lock — keep your"
  echo "private-extension lock local/unstaged: git restore --staged server/Gemfile.lock"
  echo ""
  echo "If you intend to commit a lock change, regenerate the public one"
  echo "(private extensions are excluded by default now):"
  echo "    cd server && bundle lock      # or: bash scripts/regen-public-lockfile.sh"
  echo "then re-stage server/Gemfile.lock."
  exit 1
fi

echo "✓ check-lockfile-public-only: only public-extension gems declared"
