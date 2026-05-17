#!/usr/bin/env bash
#
# powernode-reverse-proxy.sh — systemd entry point for the platform's
# bundled Traefik reverse proxy. Invoked by
# scripts/systemd/units/powernode-reverse-proxy@.service.
#
# Resolves the binary, regenerates the static config (from the Rails
# TraefikConfigWriter via a tiny one-liner runner), and execs Traefik.
#
# Required env (from /etc/powernode/powernode.conf or
# /etc/powernode/reverse-proxy-<instance>.conf):
#
#   POWERNODE_TRAEFIK_DYNAMIC_DIR   (defaults to TraefikConfigWriter's fallback)
#   POWERNODE_TRAEFIK_CERT_DIR      (defaults likewise)
#   POWERNODE_TRAEFIK_STATIC_CONFIG (defaults likewise)
#   POWERNODE_PROXY_BACKEND_URL     (defaults http://127.0.0.1:3000)
#   POWERNODE_PROXY_FRONTEND_URL    (defaults http://127.0.0.1:3001)
#
# Plan reference: Decentralized Federation §J + P2.5.11.

set -eo pipefail

PLATFORM_ROOT="${POWERNODE_BASE:-/opt/powernode}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  GOARCH=amd64 ;;
  aarch64|arm64) GOARCH=arm64 ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

BINARY="${POWERNODE_TRAEFIK_BIN:-$PLATFORM_ROOT/extensions/system/agent/dist/powernode-reverse-proxy-linux-$GOARCH}"

if [[ ! -x "$BINARY" ]]; then
  echo "powernode-reverse-proxy binary not found at $BINARY" >&2
  echo "Build it: cd $PLATFORM_ROOT/extensions/system/agent && make vendor-traefik" >&2
  exit 1
fi

# Source RVM so `bundle exec` resolves to the correct ruby. Mirrors the
# pattern in powernode-backend.sh — without this, systemd's stripped
# env has no PATH to ruby/bundler and the rails runner call returns
# empty / nothing useful. RVM uses uninitialized vars internally so we
# keep nounset off (matches backend.sh).
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
if [[ -n "${POWERNODE_RUBY_VERSION:-}" ]]; then
  rvm use "${POWERNODE_RUBY_VERSION}" >/dev/null 2>&1 || true
fi

# Regenerate the static config from the Rails-side TraefikConfigWriter
# so env-derived paths (dynamic dir, etc.) stay in sync. The runner
# also (re)writes the per-account dynamic YAML so a stale config from a
# previous environment doesn't survive into this start.
cd "$PLATFORM_ROOT/server"
STATIC_CONFIG="$(bundle exec rails runner '
  Account.find_each do |acct|
    Acme::TraefikConfigWriter.write!(account: acct) rescue nil
  end
  print Acme::TraefikConfigWriter.write_static_config!
' 2>&1)"

if [[ -z "$STATIC_CONFIG" ]] || [[ ! -f "$STATIC_CONFIG" ]]; then
  echo "Failed to generate Traefik static config; runner output:" >&2
  echo "$STATIC_CONFIG" >&2
  exit 1
fi

echo "Starting Traefik with static config: $STATIC_CONFIG"
exec "$BINARY" --configFile="$STATIC_CONFIG"
