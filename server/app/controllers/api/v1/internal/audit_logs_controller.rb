# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Internal API for worker service to create audit log entries
      class AuditLogsController < InternalBaseController
        # POST /api/v1/internal/audit_logs
        # Called by compliance and maintenance worker jobs
        def create
          # Rails sets params[:action] to controller action ("create"), so
          # use wrap_parameters key (:audit_log) to get the body's "action" field
          body = params[:audit_log] || {}

          audit_log = AuditLog.create!(
            action: body[:action],
            resource_type: body[:resource_type] || params[:resource_type],
            resource_id: body[:resource_id] || params[:resource_id],
            account: @current_account,
            user: nil,
            source: body[:source] || params[:source] || "worker",
            severity: body[:severity] || params[:severity] || "low",
            risk_level: body[:risk_level] || params[:risk_level] || "low",
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            metadata: (body[:metadata] || params[:metadata])&.to_unsafe_h || {}
          )

          render_success(
            { id: audit_log.id, action: audit_log.action, created_at: audit_log.created_at.iso8601 },
            status: :created
          )
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error "Internal audit log validation failed: #{e.record.errors.full_messages.join(', ')}"
          render_error("Invalid audit log data", :unprocessable_content, details: e.record.errors.full_messages)
        rescue StandardError => e
          render_internal_error("Failed to create audit log", exception: e)
        end
      end
    end
  end
end
