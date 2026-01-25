# frozen_string_literal: true

class Api::V1::Admin::JobsController < ApplicationController
  before_action :authenticate_request
  before_action :require_system_admin_permission

  # GET /api/v1/admin/jobs/:id
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
      duration: job.duration&.round(2),
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

  # GET /api/v1/admin/jobs
  def index
    jobs = BackgroundJob.recent.limit(50)

    job_filter = params[:status]
    jobs = jobs.where(status: job_filter) if job_filter.present?

    job_type_filter = params[:job_type]
    jobs = jobs.where(job_type: job_type_filter) if job_type_filter.present?

    render_success({
      jobs: jobs.map do |job|
        {
          job_id: job.job_id,
          job_type: job.job_type,
          status: job.status,
          progress: job.progress_percentage,
          duration: job.duration&.round(2),
          created_at: job.created_at,
          completed_at: job.completed_at,
          has_result: job.result.present?,
          has_error: job.error_message.present?
        }
      end,
      pagination: {
        count: jobs.count,
        limit: 50
      }
    })
  rescue StandardError => e
    Rails.logger.error "Failed to list jobs: #{e.message}"
    render_error("Failed to list jobs", status: :internal_server_error)
  end

  private

  def require_system_admin_permission
    unless current_user.has_permission?("admin.settings.update")
      render_error("Insufficient permissions to view jobs", status: :forbidden)
    end
  end
end
