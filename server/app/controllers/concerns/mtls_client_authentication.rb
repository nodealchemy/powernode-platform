# frozen_string_literal: true

# Resolves the worker identity from a Traefik-forwarded mTLS client cert.
#
# Federation mTLS Phase 2 (symmetric) added peer CAs to the shared Traefik
# client-auth bundle, so Traefik's chain-check alone no longer proves a
# presented cert was issued by THIS platform. We therefore re-verify the
# forwarded leaf cryptographically against OUR CA (Security::MtlsTrust /
# Security::MtlsClientVerifier) before resolving the worker — a peer-CA-signed
# cert must not be able to impersonate a worker on these routes.
#
# Security::MtlsTrust.verify_request has TWO trust paths, and only one of them
# is cryptographic:
#
#   * NON-BLANK PEM forwarded (passTLSClientCert.pem=true) — the leaf is
#     re-verified against OUR CA here, so a cert we did not issue is rejected
#     even though Traefik accepted it against the shared client-auth bundle.
#     The branch is chosen via `.presence`, so a BLANK PEM header counts as
#     absent and silently takes the Info path below.
#
#   * PEM absent, `X-Forwarded-Tls-Client-Cert-Info` only — the forwarded
#     subject CN is trusted WITHOUT re-verification. See verify_request's
#     no-PEM branch for why that is sound in this posture: peer CAs are only
#     added to the client-auth bundle by the same writer that enables
#     pem-forwarding, so with no PEM, Traefik's chain-check against our-CA-only
#     is authoritative. This path does NOT fail closed — a request carrying
#     only that header authenticates as whichever Worker matches the CN. What
#     stops a client from forging it is not this class but the ingress:
#     Core::IngressConfigWriter::STRIP_FORWARDED_CLIENT_CERT_MW deletes any
#     client-supplied X-Forwarded-Tls-Client-Cert[-Info] and is applied FIRST
#     on every backend router, with pass-tls layered after it.
#
# So the cert check rejects a request carrying neither header, rejects a
# non-blank PEM that fails verification, and rejects an Info header with no
# parseable CN — but ACCEPTS any Info header it can parse a CN out of.
#
# Sets @current_worker + @current_account on success; renders 401 on a missing /
# unverifiable cert, unknown CN, or inactive worker.
module MtlsClientAuthentication
  extend ActiveSupport::Concern

  private

  def authenticate_worker_via_mtls!
    verified_cn = Security::MtlsTrust.verify_request(request)
    if verified_cn.blank?
      render_error("valid mTLS client certificate required", status: :unauthorized)
      return
    end

    @current_worker = Worker.find_by(node_instance_id: verified_cn)
    unless @current_worker
      render_error("Worker not found for mTLS subject", status: :unauthorized)
      return
    end

    unless @current_worker.active?
      render_error("Worker is not active", status: :unauthorized)
      return
    end

    @current_account = @current_worker.account
    request.env["powernode.internal_request"] = true
  end
end
