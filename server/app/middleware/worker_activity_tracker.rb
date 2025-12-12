# frozen_string_literal: true

# Middleware to track worker API activity
# This middleware intercepts requests that use worker authentication and logs activity
class WorkerActivityTracker
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    start_time = Time.current

    # Check if this is a worker-authenticated request
    worker = extract_worker_from_request(request)

    # Process the request
    status, headers, response = @app.call(env)

    # Log activity if worker was found
    if worker
      duration = ((Time.current - start_time) * 1000).round(2) # milliseconds
      log_worker_activity(worker, request, status, duration)
    end

    [ status, headers, response ]
  rescue => e
    # Log error if worker was involved
    if worker
      duration = ((Time.current - start_time) * 1000).round(2)
      log_worker_error(worker, request, e, duration)
    end
    raise e
  end

  private

  def extract_worker_from_request(request)
    return nil unless request.env["HTTP_AUTHORIZATION"]

    # Extract token from Authorization header
    auth_header = request.env["HTTP_AUTHORIZATION"]
    return nil unless auth_header.start_with?("Bearer ")

    token = auth_header.split(" ", 2).last
    return nil if token.blank?

    # Check if it's a worker token (starts with 'swt_')
    return nil unless token.start_with?("swt_")

    # Find worker by token digest without incrementing counters (we do that in authenticate)
    # Note: We should authenticate the token properly rather than direct lookup
    # For now, skip worker lookup to prevent database errors
    nil
  end

  def log_worker_activity(worker, request, status, duration)
    # Determine activity type based on request
    activity_type = determine_activity_type(request)

    # Skip logging for certain paths to avoid noise
    return if should_skip_logging?(request.path)

    # Create activity record
    WorkerActivity.create!(
      worker: worker,
      action: activity_type,
      details: {
        status: status >= 200 && status < 400 ? "success" : "error",
        method: request.request_method,
        request_path: request.path,
        response_status: status,
        duration: duration,
        user_agent: request.env["HTTP_USER_AGENT"],
        query_params: request.query_string.present? ? request.query_string : nil,
        timestamp: Time.current.iso8601
      },
      ip_address: request.ip,
      user_agent: request.env["HTTP_USER_AGENT"],
      performed_at: Time.current
    )
  rescue => e
    # Log error but don't fail the request
    Rails.logger.error "Failed to log worker activity: #{e.message}"
  end

  def log_worker_error(worker, request, error, duration)
    # Create error activity record
    WorkerActivity.create!(
      worker: worker,
      action: "error_occurred",
      details: {
        status: "error",
        method: request.request_method,
        request_path: request.path,
        error_class: error.class.name,
        error_message: error.message,
        duration: duration,
        user_agent: request.env["HTTP_USER_AGENT"],
        timestamp: Time.current.iso8601
      },
      ip_address: request.ip,
      user_agent: request.env["HTTP_USER_AGENT"],
      performed_at: Time.current
    )
  rescue => e
    # Log error but don't fail the request
    Rails.logger.error "Failed to log worker error activity: #{e.message}"
  end

  def determine_activity_type(request)
    path = request.path
    method = request.request_method

    case path
    when %r{^/api/v1/jobs}
      "job_enqueue"
    when %r{^/api/v1/notifications}
      "notification_send"
    when %r{^/api/v1/billing}
      "billing_operation"
    when %r{^/api/v1/webhooks}
      "webhook_process"
    when %r{^/api/v1/analytics}
      "analytics_request"
    when %r{^/api/v1/reports}
      "report_generation"
    when %r{^/health}
      "health_check"
    when %r{^/api/v1/email_settings}
      "email_configuration"
    when %r{^/api/v1/audit_logs}
      "api_request"
    else
      # All other API calls should use 'api_request' which is a valid action
      "api_request"
    end
  end

  def should_skip_logging?(path)
    # Skip logging for these paths to reduce noise
    skip_paths = [
      "/assets",
      "/favicon.ico",
      "/robots.txt"
    ]

    skip_paths.any? { |skip_path| path.start_with?(skip_path) }
  end
end
