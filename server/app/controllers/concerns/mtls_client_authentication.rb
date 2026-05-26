# frozen_string_literal: true

# Resolves the worker identity from a Traefik-forwarded mTLS client cert.
# Routes that include this concern must be reachable only via the
# `websecure-mtls` (:4443) entrypoint — Traefik's passTLSClientCert
# middleware sets `X-Forwarded-Tls-Client-Cert-Info` only for verified
# client certs, and the listener-level mtls-required@file option rejects
# unverified connections before they reach Rails.
#
# Sets @current_worker + @current_account on success; renders 401 on
# missing header, unknown CN, or inactive worker.
module MtlsClientAuthentication
  extend ActiveSupport::Concern

  private

  def authenticate_worker_via_mtls!
    subject_cn = mtls_subject_cn
    if subject_cn.blank?
      render_error("mTLS client certificate required", status: :unauthorized)
      return
    end

    @current_worker = Worker.find_by(node_instance_id: subject_cn)
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

  # Reads the verified mTLS client subject CN from the Traefik v3
  # passTLSClientCert middleware header (URL-encoded `Subject="CN=<value>"`).
  def mtls_subject_cn
    info = request.headers["X-Forwarded-Tls-Client-Cert-Info"].presence
    return nil unless info

    decoded = CGI.unescape(info)
    match = decoded.match(/\bCN\s*=\s*"?([^,"]+)"?/i)
    match && match[1].strip
  end
end
