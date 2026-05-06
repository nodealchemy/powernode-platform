#!/usr/bin/env bash
#
# Symlink each extension's frontend node_modules to the parent's so extension
# Jest tests can resolve babel/jest/react packages without each extension
# maintaining its own node_modules. The symlinks are gitignored (since
# node_modules/ is universally gitignored) — this script recreates them
# after a fresh clone.
#
# Idempotent: skips extensions that already have a symlink or directory.
#
# Usage:
#   ./scripts/setup-extension-frontend-symlinks.sh
#
# Run once after `cd frontend && npm install`. Required before running
# extension Jest tests (e.g. extensions/marketing/frontend/jest.config.js).

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

for ext in system marketing; do
  ext_frontend="extensions/${ext}/frontend"
  link="${ext_frontend}/node_modules"
  target="../../../frontend/node_modules"

  if [ ! -d "$ext_frontend" ]; then
    echo "  ${ext}: extension directory not present — skipping"
    continue
  fi

  if [ -e "$link" ] || [ -L "$link" ]; then
    echo "  ${ext}: $link already exists — skipping"
    continue
  fi

  ln -s "$target" "$link"
  echo "  ${ext}: linked $link → $target"
done

echo
echo "Done. Run extension Jest tests with:"
echo "  cd extensions/<ext>/frontend && npx --prefix ../../../frontend jest --config=jest.config.js"
