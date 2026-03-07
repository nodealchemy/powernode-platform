#!/usr/bin/env bash
# Wrapper script for Powernode Worker Web UI (Sidekiq Web)
# Sources RVM environment then exec's the rackup process.
# Using exec ensures the process becomes PID 1 for proper signal handling.
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

# Use configured Ruby version
if [[ -n "${POWERNODE_RUBY_VERSION:-}" ]]; then
    rvm use "${POWERNODE_RUBY_VERSION}" || {
        echo "ERROR: Failed to activate Ruby ${POWERNODE_RUBY_VERSION}" >&2
        exit 1
    }
fi

# Defaults
SIDEKIQ_WEB_HOST="${SIDEKIQ_WEB_HOST:-127.0.0.1}"
SIDEKIQ_WEB_PORT="${SIDEKIQ_WEB_PORT:-4567}"
WORKER_WEB_THREADS="${WORKER_WEB_THREADS:-16}"

exec bundle exec rackup \
    -s puma \
    -o "${SIDEKIQ_WEB_HOST}" \
    -p "${SIDEKIQ_WEB_PORT}" \
    -O "Threads=0:${WORKER_WEB_THREADS}" \
    config.ru
