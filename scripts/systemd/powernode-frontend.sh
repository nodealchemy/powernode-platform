#!/usr/bin/env bash
# Wrapper script for Powernode Frontend (Vite dev server)
# Sources nvm environment then exec's npm start.
# Using exec ensures the Node process becomes PID 1 for proper signal handling.
set -euo pipefail

# Source nvm
if [[ -n "${NVM_DIR:-}" ]] && [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    source "${NVM_DIR}/nvm.sh"
elif [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    export NVM_DIR="$HOME/.nvm"
    source "${NVM_DIR}/nvm.sh"
else
    echo "ERROR: nvm not found. Set NVM_DIR in /etc/powernode/powernode.conf" >&2
    exit 1
fi

# Use configured Node version
if [[ -n "${NODE_VERSION:-}" ]]; then
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
