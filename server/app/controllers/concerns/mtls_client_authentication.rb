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
# Requires Traefik to forward the full client-cert PEM
# (passTLSClientCert.pem=true); without it verify_request returns nil and the
# route fails closed. Sets @current_worker + @current_account on success;
# renders 401 on a missing / unverifiable cert, unknown CN, or inactive worker.
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
