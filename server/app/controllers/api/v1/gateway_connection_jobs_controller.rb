# frozen_string_literal: true

class Api::V1::GatewayConnectionJobsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :update ]
  before_action -> { require_permission("admin.settings.payment") }, only: [ :show ]
  before_action :authenticate_service_or_user, only: [ :update ]

  def show
    job = GatewayConnectionJob.find(params[:id])
    render_success({
      id: job.id,
      gateway: job.gateway,
      status: job.status,
      result: job.result,
      created_at: job.created_at,
      updated_at: job.updated_at,
      completed_at: job.completed_at
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Gateway connection job not found", status: :not_found)
  end

  def update
    job = GatewayConnectionJob.find(params[:id])

    update_params = gateway_connection_job_params

    # Set completed_at when status changes to completed or failed
    if update_params[:status].in?(%w[completed failed]) && job.status != update_params[:status]
      update_params[:completed_at] = Time.current
    end

    if job.update(update_params)
      render_success({
        id: job.id,
        status: job.status,
        result: job.result,
        updated_at: job.updated_at,
        completed_at: job.completed_at
      })
    else
      render_validation_error(job.errors)
    end
  rescue ActiveRecord::RecordNotFound
    render_error("Gateway connection job not found", status: :not_found)
  end

  private

  def authenticate_service_or_user
    # Allow service token authentication for worker updates
    return if authenticate_service_token

    # Fallback to user authentication with required permission
    authenticate_request
    return if performed?

    require_permission("admin.settings.payment")
  end

  def authenticate_service_token
    auth_header = request.headers["Authorization"]
    return false unless auth_header&.start_with?("Bearer ")

    token = auth_header.split(" ").last
    begin
      payload = Security::JwtService.decode(token)
      return false unless payload[:type] == "worker"
      worker = Worker.find_by(id: payload[:sub])
      worker&.active? || false
    rescue StandardError
      false
    end
  end

  def gateway_connection_job_params
    params.permit(:status, :updated_at, :completed_at, result: {})
  end
end
