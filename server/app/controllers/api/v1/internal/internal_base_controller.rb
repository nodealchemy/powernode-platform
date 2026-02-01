# frozen_string_literal: true

# Base controller for internal API endpoints accessed by worker service
class Api::V1::Internal::InternalBaseController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token

  private

  def authenticate_service_token
    token = request.headers["Authorization"]&.split(" ")&.last

    unless token.present?
      render_error("Service token required", status: :unauthorized)
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: "HS256").first

      unless payload["service"] == "worker" && payload["type"] == "service"
        render_error("Invalid service token", status: :unauthorized)
        return
      end

      # Mark request as internal for permission validation
      request.env["powernode.internal_request"] = true

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error("Invalid service token", status: :unauthorized)
    end
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
      details: metadata.merge(
        internal_request: true,
        service: "worker",
        timestamp: Time.current.iso8601
      )
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log internal audit event '#{action}': #{e.message}"
  end
end
