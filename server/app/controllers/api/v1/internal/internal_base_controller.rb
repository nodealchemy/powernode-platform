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
  include MtlsClientAuthentication

  skip_before_action :authenticate_request
  before_action :authenticate_worker_via_mtls!

  private

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
