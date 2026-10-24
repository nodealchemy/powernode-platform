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
RAILS_ENV="${RAILS_ENV:-development}"
# Production listens on loopback only (the ingress is the sole way in; it strips
# and sets the forwarded client-cert headers the app trusts). HOST overrides it.
if [[ "${RAILS_ENV}" == "production" ]]; then
    HOST="${HOST:-127.0.0.1}"
else
    HOST="${HOST:-0.0.0.0}"
fi

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

# One-time legacy cache clear (production): the deploy that turns on solid_cache
# encryption must not leave entries written in plain text before it at rest (on
# an installer host those include cached Vault values). Emptying the cache is a
# cold start, not data loss. Bounded, never fails the start, and guarded twice:
# this marker file skips the extra Rails boot once done, and the task's own
# SiteSetting marker makes a repeat a no-op. A failed run leaves both unset and
# retries next start.
CACHE_CLEAR_MARKER="${POWERNODE_BASE:-/opt/powernode}/server/tmp/.solid-cache-legacy-plaintext-cleared"
if [[ "${RAILS_ENV}" == "production" ]] && [[ ! -f "${CACHE_CLEAR_MARKER}" ]]; then
    if timeout 120 bundle exec rails powernode:cache:clear_legacy_plaintext; then
        touch "${CACHE_CLEAR_MARKER}" || true
    else
        echo "[backend] legacy cache clear did not finish; continuing, it retries next start" >&2
    fi
fi

exec bundle exec rails server -p "${PORT}" -b "${HOST}"
