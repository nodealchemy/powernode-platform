# frozen_string_literal: true

# Base controller for internal API endpoints (`/api/v1/internal/*`).
# These endpoints are called exclusively by the standalone Sidekiq worker.
#
# Auth model: mTLS. Workers are deployed as NodeInstances (Stage 8b);
# the worker host runs the powernode-agent, which manages the mTLS
# cert lifecycle (enrollment via /node_api/enroll, rotation via the
# agent's CertRotator). Traefik terminates the handshake on the
# `<slug>-internal-api` router (mTLS-required against the platform's
# internal CA) and forwards the verified CN — which is the
# NodeInstance.id — via `X-Forwarded-Tls-Client-Cert-Info`. This
# controller resolves the Worker via `node_instance_id`.
class Api::V1::Internal::InternalBaseController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_worker_via_mtls!

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

  # Audit logging helper for internal service operations
  # @param action [String] The action being performed (e.g., 'account.anonymize', 'user.delete')
  # @param resource_type [String] The type of resource being affected
  # @param resource_id [String] The ID of the resource being affected
  # @param metadata [Hash] Additional context for the audit log
  def log_internal_audit(action, resource_type, resource_id, metadata = {})
    AuditLog.create!(
      account_id: metadata[:account_id],
      user_id: nil, # Internal service request - no user
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: metadata.merge(
        internal_request: true,
        service: "worker",
        timestamp: Time.current.iso8601
      )
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log internal audit event '#{action}': #{e.message}"
  end
end
