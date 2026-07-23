#!/usr/bin/env bash
# Wrapper script for Powernode Worker (Sidekiq)
# Sources RVM environment then exec's the Sidekiq process.
# Using exec ensures the Sidekiq process becomes PID 1 for proper signal handling.
set -eo pipefail

# Source RVM (disable nounset — RVM uses uninitialized variables internally).
# Hosts without RVM (immutable-image nodes like the dev-cell, where runtime-ruby
# bakes ruby into /usr/local) fall back to the ruby already on PATH.
RVM_SOURCED=false
if [[ -n "${RVM_PATH:-}" ]] && [[ -s "${RVM_PATH}/scripts/rvm" ]]; then
    source "${RVM_PATH}/scripts/rvm"
    RVM_SOURCED=true
elif [[ -s "/usr/local/rvm/scripts/rvm" ]]; then
    source "/usr/local/rvm/scripts/rvm"
    RVM_SOURCED=true
elif [[ -s "$HOME/.rvm/scripts/rvm" ]]; then
    source "$HOME/.rvm/scripts/rvm"
    RVM_SOURCED=true
elif command -v ruby &>/dev/null && command -v bundle &>/dev/null; then
    echo "[powernode] RVM not found; using system ruby: $(command -v ruby) ($(ruby -v))"
else
    echo "ERROR: RVM not found and no ruby/bundle on PATH. Set RVM_PATH in powernode.conf or install ruby." >&2
    exit 1
fi

# Use configured Ruby version
if [[ "${RVM_SOURCED}" == true ]] && [[ -n "${POWERNODE_RUBY_VERSION:-}" ]]; then
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
