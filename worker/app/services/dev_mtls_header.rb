# frozen_string_literal: true

# The WORKER half of the dev-only mTLS client-cert header contract.
#
# Why this is its own file, and why it has no dependencies:
# the header format is an inter-app contract with two independent
# implementations — this emitter, and Security::MtlsTrust.forwarded_subject_cn's
# regex in the server. Neither app can load the other's code (the server bundle
# has no `oj`/`faraday-retry`, so it cannot require BackendApiClient; the worker
# has no ActiveRecord, so it cannot resolve a Worker row). Keeping the emitter
# free of faraday/oj/Rails lets the SERVER suite `require_relative` this exact
# file and drive the real emitter through the real parser — see
# server/spec/security/dev_mtls_header_contract_spec.rb. Do not add requires.
module DevMtlsHeader
  # Traefik's passTLSClientCert "info" header. MUST equal
  # Security::MtlsTrust::SUBJECT_HEADER
  # (server/app/services/security/mtls_trust.rb).
  HEADER = 'X-Forwarded-Tls-Client-Cert-Info'

  # The CN presented when DEV_WORKER_NODE_INSTANCE_ID is unset — which is the
  # NORMAL dev state: no .env, compose file or script in this repo sets that
  # var. The server binds its system Worker row to this same id in development
  # (Workers::EnsureSystemWorker#bind_dev_sentinel), so a worker that presented
  # nothing here would 401 on every /api/v1/internal/* call.
  #
  # DUPLICATED, BY NECESSITY, in the server as
  # Workers::EnsureSystemWorker::DEV_SENTINEL_NODE_ID
  # (server/app/services/workers/ensure_system_worker.rb). The two apps are
  # separate processes with separate bundles and no shared load path, so no
  # single constant can reach both — change this literal and you MUST change
  # that one. server/spec/security/dev_mtls_header_contract_spec.rb pins them
  # together by driving this emitter through the server's real parser.
  DEV_SENTINEL_NODE_ID = '00000000-0000-7000-8000-000000000001'

  module_function

  # The CN to present: the configured override, else the shared dev sentinel.
  def common_name
    configured = ENV['DEV_WORKER_NODE_INSTANCE_ID']
    return DEV_SENTINEL_NODE_ID if configured.nil? || configured.empty?

    configured
  end

  # The header value Traefik would synthesize from a verified client cert.
  # Always present — callers gate on environment, not on this being nil.
  #
  # Emitted UNENCODED, whereas real Traefik percent-encodes this header. The
  # server's parser calls CGI.unescape first, which is a no-op on a UUID, so
  # the sentinel and any UUID CN round-trip exactly. A CN containing '+' or '%'
  # would NOT survive (CGI.unescape turns '+' into a space) — dev CNs are
  # NodeInstance UUIDs, so this is a documented constraint, not a live bug.
  # Escaping here would cost a `require "cgi"` and this file's dependency-free
  # property, which the cross-app contract spec depends on.
  def header_value
    %(Subject="CN=#{common_name}")
  end
end
