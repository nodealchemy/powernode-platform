#!/usr/bin/env bash
# regen-public-lockfile.sh — regenerate server/Gemfile.lock with only
# public-extension gems declared, so the committed lockfile works on
# clones that don't have access to private submodules (CI, contributors).
#
# Background: server/Gemfile dynamically declares extension gems based on
# what's present in extensions/. A maintainer with extensions/private/business
# on disk will have that gem declared and locked. CI sees only the
# public submodules, so frozen-mode `bundle install` fails with "You
# have deleted from the Gemfile" (the lockfile names a gem the Gemfile
# no longer declares).
#
# Private extensions are excluded from the lockfile BY DEFAULT (see
# extensions_loader_helper.rb), so this script just makes sure the full-mode
# opt-in is OFF and runs `bundle lock` (or `bundle install`) to rewrite the
# lockfile to the public-only set — handy after editing the Gemfile, or to
# reset a full-mode working lock back to public before committing.
#
# Usage:
#   bash scripts/regen-public-lockfile.sh             # full install
#   bash scripts/regen-public-lockfile.sh --lock-only # update lockfile only, skip install
#
# After running, commit server/Gemfile.lock.
# scripts/check-lockfile-public-only.sh (pre-commit hook) verifies the
# result.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT/server"

LOCK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --lock-only) LOCK_ONLY=1 ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

echo "[regen-public-lockfile] excluding private extensions from discovery (default)..."
# Guarantee the public-only set regardless of any ambient full-mode opt-in
# (the var lives in the server's service env, and a maintainer may have it
# exported or sourced into their shell).
unset POWERNODE_INCLUDE_PRIVATE_EXTENSIONS
export BUNDLE_FROZEN=false

if [[ "$LOCK_ONLY" -eq 1 ]]; then
  echo "[regen-public-lockfile] running 'bundle lock' (no install)..."
  bundle lock
else
  echo "[regen-public-lockfile] running 'bundle install'..."
  bundle install
fi

echo ""
echo "[regen-public-lockfile] result:"
bash "$REPO_ROOT/scripts/check-lockfile-public-only.sh"
echo ""
echo "Now commit server/Gemfile.lock to land the public-only lockfile."
