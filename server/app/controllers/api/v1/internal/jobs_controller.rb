# frozen_string_literal: true

class Api::V1::Internal::JobsController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token

  # Internal API endpoints for job tracking
  # These endpoints are called by background workers only

  # PATCH /api/v1/internal/jobs/:id
  def update
    job = BackgroundJob.find_by!(job_id: params[:id])

    case params[:status]
    when "in_progress"
      job.mark_in_progress!
    when "completed"
      job.mark_completed!(params[:result] || {})
    when "failed"
      job.mark_failed!(params[:error] || "Job failed", params[:error_details] || {})
    else
      job.update!(
        result: params[:result],
        error_message: params[:error],
        error_details: params[:error_details]
      )
    end

    render_success({
      job_id: job.job_id,
      status: job.status,
      message: "Job status updated successfully"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Job not found", status: :not_found)
  rescue => e
    Rails.logger.error "Failed to update job status: #{e.message}"
    render_error("Failed to update job status", status: :internal_server_error)
  end

  # GET /api/v1/internal/jobs/:id
  def show
    job = BackgroundJob.find_by!(job_id: params[:id])

    render_success({
      job_id: job.job_id,
      job_type: job.job_type,
      status: job.status,
      progress: job.progress_percentage,
      parameters: job.parameters,
      result: job.result,
      error_message: job.error_message,
      error_details: job.error_details,
      duration: job.duration,
      created_at: job.created_at,
      started_at: job.started_at,
      completed_at: job.completed_at
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Job not found", status: :not_found)
  rescue => e
    Rails.logger.error "Failed to get job status: #{e.message}"
    render_error("Failed to get job status", status: :internal_server_error)
  end

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
        nil
      end

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error("Invalid service token", status: :unauthorized)
    end
  end
end
