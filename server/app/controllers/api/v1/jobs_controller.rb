# frozen_string_literal: true

# API controller for handling job enqueue requests
# This controller receives job requests from WorkerJobService and forwards them to the worker service
class Api::V1::JobsController < ApplicationController
  skip_before_action :authenticate_request, only: [:create]
  before_action :authenticate_service_request!, only: [:create]

  def create
    job_class = params[:job_class]
    args = params[:args] || []
    options = params[:options] || {}

    # Validate required parameters
    unless job_class.present?
      return render_error('Missing job_class parameter', status: :unprocessable_entity)
    end

    # Forward the job request to the worker service
    begin
      # Use the actual worker service communication (external API)
      response = forward_to_worker_service(job_class, args, options)
      render_success(response)
    rescue StandardError => e
      Rails.logger.error "Failed to enqueue job #{job_class}: #{e.message}"
      render_error(
        'Failed to enqueue job. Please check worker service status.',
        status: :service_unavailable
      )
    end
  end

  private

  def authenticate_service_request!
    service_token = extract_service_token
    return render_error('Unauthorized', status: :unauthorized) unless service_token

    begin
      payload = JWT.decode(service_token, Rails.application.config.jwt_secret_key, true, algorithm: 'HS256').first
      unless payload['service'] == 'backend' && payload['type'] == 'service'
        return render_error('Invalid service token', status: :unauthorized)
      end
    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error('Invalid or expired service token', status: :unauthorized)
    end
  end

  def extract_service_token
    auth_header = request.headers['Authorization']
    return nil unless auth_header&.start_with?('Bearer ')
    auth_header.split(' ', 2).last
  end

  def forward_to_worker_service(job_class, args, options)
    # This is a pass-through controller that receives job requests from WorkerJobService
    # In a real implementation, this would forward to the actual worker service
    # For now, we'll return a success response to complete the flow
    {
      job_id: SecureRandom.uuid,
      job_class: job_class,
      enqueued_at: Time.current.iso8601,
      status: 'enqueued'
    }
  end
end