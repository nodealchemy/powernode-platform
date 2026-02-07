#!/usr/bin/env bash
# Wrapper script for Powernode Worker (Sidekiq)
# Sources RVM environment then exec's the Sidekiq process.
# Using exec ensures the Sidekiq process becomes PID 1 for proper signal handling.
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
WORKER_ENV="${WORKER_ENV:-development}"
WORKER_CONCURRENCY="${WORKER_CONCURRENCY:-5}"

export RAILS_ENV="${WORKER_ENV}"

exec bundle exec sidekiq \
    -r ./config/application.rb \
    -C ./config/sidekiq.yml \
    -c "${WORKER_CONCURRENCY}"
