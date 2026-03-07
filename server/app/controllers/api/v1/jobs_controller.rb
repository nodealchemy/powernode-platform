# frozen_string_literal: true

# API controller for handling job enqueue requests
# This controller receives job requests from WorkerJobService and forwards them to the worker service
class Api::V1::JobsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :create ]
  before_action :authenticate_service_token, only: [ :create ]

  def create
    job_class = params[:job_class]
    args = params[:args] || []
    options = params[:options] || {}

    # Validate required parameters
    unless job_class.present?
      return render_error("Missing job_class parameter", status: :unprocessable_content)
    end

    # Forward the job request to the worker service
    begin
      # Use the actual worker service communication (external API)
      response = forward_to_worker_service(job_class, args, options)
      render_success(response)
    rescue StandardError => e
      Rails.logger.error "Failed to enqueue job #{job_class}: #{e.message}"
      render_error(
        "Failed to enqueue job. Please check worker service status.",
        status: :service_unavailable
      )
    end
  end

  private

  def authenticate_service_token
    token = request.headers["Authorization"]&.split(" ")&.last
    return render_error("Service authentication required", status: :unauthorized) unless token

    begin
      payload = Security::JwtService.decode(token)
      worker = Worker.find_by(id: payload[:sub]) if payload[:type] == "worker"
    rescue StandardError
      worker = nil
    end

    unless worker&.active?
      render_error("Service authentication required", status: :unauthorized)
    end
  end

  def forward_to_worker_service(job_class, args, options)
    # Enqueue job directly to Redis for Sidekiq worker processing
    require "redis"
    require "json"
    require "securerandom"

    redis = Powernode::Redis.new_worker_client

    jid = SecureRandom.hex(12)
    queue_name = options[:queue] || "default"

    job_data = {
      "class" => job_class,
      "args" => args,
      "queue" => queue_name,
      "jid" => jid,
      "created_at" => Time.current.to_f,
      "retry" => options[:retry] || true
    }

    # Push job to Sidekiq queue in Redis
    redis.lpush("queue:#{queue_name}", job_data.to_json)

    {
      job_id: jid,
      job_class: job_class,
      enqueued_at: Time.current.iso8601,
      status: "enqueued"
    }
  rescue StandardError => e
    Rails.logger.error "Failed to enqueue job to Redis: #{e.message}"
    raise e
  end
end
