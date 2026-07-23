#!/usr/bin/env bash
# Wrapper script for Powernode Frontend (Vite dev server)
# Sources nvm environment then exec's npm start.
# Using exec ensures the Node process becomes PID 1 for proper signal handling.
set -euo pipefail

# Source nvm. Hosts without nvm (immutable-image nodes like the dev-cell, where
# runtime-node bakes node into /usr/local) fall back to the node already on PATH.
NVM_SOURCED=false
if [[ -n "${NVM_DIR:-}" ]] && [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    source "${NVM_DIR}/nvm.sh"
    NVM_SOURCED=true
elif [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    export NVM_DIR="$HOME/.nvm"
    source "${NVM_DIR}/nvm.sh"
    NVM_SOURCED=true
elif command -v node &>/dev/null && command -v npm &>/dev/null; then
    echo "[powernode] nvm not found; using system node: $(command -v node) ($(node --version))"
else
    echo "ERROR: nvm not found and no node/npm on PATH. Set NVM_DIR in powernode.conf or install node." >&2
    exit 1
fi

# Use configured Node version
if [[ "${NVM_SOURCED}" == true ]] && [[ -n "${NODE_VERSION:-}" ]]; then
    nvm use "${NODE_VERSION}" || {
        echo "ERROR: Failed to activate Node ${NODE_VERSION}" >&2
        exit 1
    }
fi

# Defaults
PORT="${PORT:-3001}"
HOST="${HOST:-0.0.0.0}"

# Read app version from VERSION file if not already set
if [[ -z "${VITE_APP_VERSION:-}" ]] && [[ -f "VERSION" ]]; then
    VITE_APP_VERSION="$(cat VERSION)"
fi

export PORT HOST VITE_APP_VERSION

exec npm start
