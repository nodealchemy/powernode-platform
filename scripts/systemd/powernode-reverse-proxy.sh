#!/usr/bin/env bash
#
# powernode-reverse-proxy.sh — systemd entry point for the platform's
# bundled Traefik reverse proxy. Invoked by
# scripts/systemd/units/powernode-reverse-proxy@.service.
#
# Resolves the binary, regenerates the config (via Core::IngressConfigWriter,
# a tiny one-liner runner), and execs Traefik. Core::IngressConfigWriter
# delegates to the system extension's Acme::TraefikConfigWriter when it's
# loaded (full ACME/mTLS/federation ingress); otherwise it renders the core
# baseline (self-signed host cert + the 4 generic routers) — this script no
# longer hard-refs the extension writer or its binary path (docs/operations/
# reverse-proxy.md §7-8, campaign 019f3458 increment 8).
#
# Required env (from /etc/powernode/powernode.conf or
# /etc/powernode/reverse-proxy-<instance>.conf):
#
#   POWERNODE_TRAEFIK_DYNAMIC_DIR   (defaults to Core::IngressConfigWriter's fallback)
#   POWERNODE_TRAEFIK_CERT_DIR      (defaults likewise)
#   POWERNODE_TRAEFIK_STATIC_CONFIG (defaults likewise)
#   POWERNODE_PROXY_BACKEND_URL     (defaults http://127.0.0.1:3000)
#   POWERNODE_PROXY_FRONTEND_URL    (defaults http://127.0.0.1:3001)
#   POWERNODE_INGRESS_HOST          (core-mode self-signed cert CN; defaults to hostname)
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

# Binary resolution order: explicit override, then the system extension's
# vendored copy (unchanged path — existing installs keep working exactly as
# before), then core's own vendored copy (`make vendor-traefik` at the repo
# root — see the root Makefile), which is what a pure-core install (no
# `system` extension) uses.
EXT_BINARY="$PLATFORM_ROOT/extensions/system/agent/dist/powernode-reverse-proxy-linux-$GOARCH"
CORE_BINARY="$PLATFORM_ROOT/scripts/systemd/dist/powernode-reverse-proxy-linux-$GOARCH"
if [[ -n "${POWERNODE_TRAEFIK_BIN:-}" ]]; then
  BINARY="$POWERNODE_TRAEFIK_BIN"
elif [[ -x "$EXT_BINARY" ]]; then
  BINARY="$EXT_BINARY"
else
  BINARY="$CORE_BINARY"
fi

if [[ ! -x "$BINARY" ]]; then
  echo "powernode-reverse-proxy binary not found at $BINARY" >&2
  if [[ -d "$PLATFORM_ROOT/extensions/system" ]]; then
    echo "Build it: cd $PLATFORM_ROOT/extensions/system/agent && make vendor-traefik" >&2
  else
    echo "Build it: cd $PLATFORM_ROOT && make vendor-traefik" >&2
  fi
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

# Regenerate the config via Core::IngressConfigWriter so env-derived paths
# (dynamic dir, etc.) stay in sync. The runner:
#   - bootstraps the shared mTLS dynamic config (internal CA + _mtls.yaml) —
#     ONLY when the system extension is loaded (Core::IngressConfigWriter
#     no-ops in core mode, where no router ever references an mtls@file
#     option).
#   - (re)writes the per-account dynamic YAML — extension-mode: full ACME/
#     mTLS/federation/worker routers (delegated, unchanged); core mode: the
#     self-signed baseline + 4 generic routers.
#   - (re)writes the per-account local-services YAML (the Sdwan::Service
#     `/svc/<slug>` bridge plane) for the same reason as before. This writer
#     is UNRELATED to the ingress_certs/ingress_routers seam — untouched by
#     increment 8 — still guarded by `rescue nil` so it safely no-ops in
#     core mode where Sdwan::ServiceExposureWriter is undefined (NameError
#     is a StandardError).
# Order matters: shared mTLS YAML + CA bundle must exist before per-account
# routers reference `mtls-required@file` / `pass-tls-client-cert@file`.
cd "$PLATFORM_ROOT/server"
# Pipe through `tail -n 1` to skip the initializer chatter that Rails 8.1+
# emits to stdout during boot (Sentry status, billing automation init, JWT
# algorithm log, ActiveRecord encryption status, etc.). The `print` (not
# `puts`) in the runner block leaves the path as the FINAL non-newlined
# character of stdout — `tail -n 1` reliably extracts just the path.
STATIC_CONFIG="$(bundle exec rails runner '
  Core::IngressConfigWriter.bootstrap_shared_dynamic! rescue nil
  Account.find_each do |acct|
    Core::IngressConfigWriter.write!(account: acct) rescue nil
    Sdwan::ServiceExposureWriter.write!(account: acct) rescue nil
  end
  print Core::IngressConfigWriter.write_static_config!
' 2>&1 | tail -n 1)"

if [[ -z "$STATIC_CONFIG" ]] || [[ ! -f "$STATIC_CONFIG" ]]; then
  echo "Failed to generate Traefik static config; runner output:" >&2
  echo "$STATIC_CONFIG" >&2
  exit 1
fi

echo "Starting Traefik with static config: $STATIC_CONFIG"
exec "$BINARY" --configFile="$STATIC_CONFIG"
