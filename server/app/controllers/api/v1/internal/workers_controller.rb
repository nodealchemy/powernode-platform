# frozen_string_literal: true

# Internal Workers Controller
# Handles worker-to-backend communication using service authentication
class Api::V1::Internal::WorkersController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_worker_service!

  # POST /api/v1/internal/workers/:id/test_results
  def test_results
    worker = Worker.find(params[:id])
    test_data = params[:test_results] || {}

    # Record the test completion activity
    worker.record_activity!("job_enqueue", {
      test_type: test_data[:test_type] || "unknown",
      status: test_data[:status] || "unknown",
      duration_seconds: test_data[:duration_seconds],
      redis_check: test_data[:redis_check],
      backend_check: test_data[:backend_check],
      performed_by: "test_worker_job",
      timestamp: test_data[:timestamp] || Time.current.iso8601
    })

    # Update worker last_seen_at to show it's active
    worker.touch(:last_seen_at)

    render_success({
      message: "Test results recorded for worker '#{worker.name}'",
      worker_id: worker.id,
      test_status: test_data[:status] || "completed"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Worker not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to record test results for worker #{params[:id]}: #{e.message}"
    render_error("Failed to record test results: #{e.message}", status: :internal_server_error)
  end

  # POST /api/v1/internal/workers/:id/ping
  def ping
    worker = Worker.find(params[:id])

    # Record ping activity
    worker.record_activity!("api_request", {
      endpoint: request.path,
      method: request.request_method,
      timestamp: Time.current.iso8601,
      performed_by: "worker_service"
    })

    # Update last_seen_at
    worker.touch(:last_seen_at)

    render_success({
      message: "Worker ping recorded",
      worker_id: worker.id,
      worker_name: worker.name,
      timestamp: Time.current.iso8601
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Worker not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to record worker ping for #{params[:id]}: #{e.message}"
    render_error("Failed to record ping: #{e.message}", status: :internal_server_error)
  end

  private

  def authenticate_worker_service!
    token = request.headers["Authorization"]&.sub(/^Bearer /, "")
    worker_token = Rails.application.config.worker_token

    unless token.present? && worker_token.present? && ActiveSupport::SecurityUtils.secure_compare(token, worker_token)
      Rails.logger.warn("Worker authentication failed: IP=#{request.remote_ip}, Token present: #{token.present?}")

      # Create audit log for failed worker authentication
      AuditLog.create!(
        account_id: nil, # System-level event
        user_id: nil,
        action: "worker_auth_failed",
        resource_type: "WorkerService",
        resource_id: "internal",
        source: "worker_service",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          endpoint: request.path,
          token_present: token.present?,
          timestamp: Time.current.iso8601
        }
      )

      render_error("Invalid worker authentication", status: :unauthorized)
    end
  end
end
