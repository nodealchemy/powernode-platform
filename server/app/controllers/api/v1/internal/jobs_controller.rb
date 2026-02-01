# frozen_string_literal: true

class Api::V1::Internal::JobsController < Api::V1::Internal::InternalBaseController
  # Internal API endpoints for job tracking
  # These endpoints are called by background workers only

  # PATCH /api/v1/internal/jobs/:id
  def update
    job = BackgroundJob.find_by!(job_id: params[:id])

    case params[:status]
    when "in_progress", "processing"
      job.mark_in_progress!
    when "completed"
      job.mark_completed!
    when "failed"
      job.mark_failed!(params[:error] || "Job failed", params[:error_details]&.to_s)
    else
      job.update!(
        error_message: params[:error]
      )
    end

    render_success({
      job_id: job.job_id,
      status: job.status,
      message: "Job status updated successfully"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Job not found", status: :not_found)
  rescue StandardError => e
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
  rescue StandardError => e
    Rails.logger.error "Failed to get job status: #{e.message}"
    render_error("Failed to get job status", status: :internal_server_error)
  end
end
