#!/usr/bin/env bash
# Wrapper script for Powernode Backend (Rails/Puma)
# Sources RVM environment then exec's the Rails server process.
# Using exec ensures the Ruby process becomes PID 1 for proper signal handling.
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

# Use configured Ruby version (POWERNODE_RUBY_VERSION to avoid conflict with RVM's RUBY_VERSION)
if [[ "${RVM_SOURCED}" == true ]] && [[ -n "${POWERNODE_RUBY_VERSION:-}" ]]; then
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

# Clear bootsnap instruction sequence cache before starting.
# Extension code changes (submodules) are not always detected by bootsnap's
# compile-cache-iseq, causing stale bytecode to be served. Removing the cache
# forces a clean recompile on boot.
ISEQ_CACHE="${POWERNODE_BASE:-/opt/powernode}/server/tmp/cache/bootsnap/compile-cache-iseq"
if [[ -d "${ISEQ_CACHE}" ]]; then
    rm -rf "${ISEQ_CACHE}"
fi

# Ensure the agent-serving symlink exists: server/public/agent -> the system
# extension's built agent dist. The /agent/* Traefik router serves the fleet
# agent binary from this path; it is gitignored deploy plumbing, so (re)create
# it on boot rather than depend on a manual per-host step.
AGENT_LINK="${POWERNODE_BASE:-/opt/powernode}/server/public/agent"
if [[ ! -L "${AGENT_LINK}" ]]; then
    ln -sfn ../../extensions/system/agent/dist "${AGENT_LINK}" \
        && echo "[backend] created agent-serving symlink ${AGENT_LINK}"
fi

exec bundle exec rails server -p "${PORT}" -b "${HOST}"
