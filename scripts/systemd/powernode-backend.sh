#!/usr/bin/env bash
# Wrapper script for Powernode Backend (Rails/Puma)
# Sources RVM environment then exec's the Rails server process.
# Using exec ensures the Ruby process becomes PID 1 for proper signal handling.
set -eo pipefail

# Source RVM (disable nounset — RVM uses uninitialized variables internally)
if [[ -n "${RVM_PATH:-}" ]] && [[ -s "${RVM_PATH}/scripts/rvm" ]]; then
    source "${RVM_PATH}/scripts/rvm"
elif [[ -s "/usr/local/rvm/scripts/rvm" ]]; then
    source "/usr/local/rvm/scripts/rvm"
elif [[ -s "$HOME/.rvm/scripts/rvm" ]]; then
    source "$HOME/.rvm/scripts/rvm"
else
    echo "ERROR: RVM not found. Set RVM_PATH in /etc/powernode/powernode.conf" >&2
    exit 1
fi

# Use configured Ruby version (POWERNODE_RUBY_VERSION to avoid conflict with RVM's RUBY_VERSION)
if [[ -n "${POWERNODE_RUBY_VERSION:-}" ]]; then
    rvm use "${POWERNODE_RUBY_VERSION}" || {
        echo "ERROR: Failed to activate Ruby ${POWERNODE_RUBY_VERSION}" >&2
        exit 1
    }
fi

# Defaults
PORT="${PORT:-3000}"
HOST="${HOST:-0.0.0.0}"
RAILS_ENV="${RAILS_ENV:-development}"

export PORT HOST RAILS_ENV

exec bundle exec rails server -p "${PORT}" -b "${HOST}"
