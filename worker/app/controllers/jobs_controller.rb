# frozen_string_literal: true

# Jobs API controller for receiving job enqueue requests from the backend
class JobsController
  def self.call(env)
    new.call(env)
  end

  def call(env)
    request = Rack::Request.new(env)
    
    case [request.request_method, request.path_info]
    when ['POST', '/'], ['POST', ''], ['POST', '/api/v1/jobs']
      enqueue_job(request)
    else
      not_found_response
    end
  rescue StandardError => e
    PowernodeWorker.application.logger.error "Jobs API error: #{e.message}"
    error_response(500, 'Internal server error')
  end

  private

  def enqueue_job(request)
    # Verify authentication
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    # Parse request body
    begin
      body = request.body.read
      job_data = JSON.parse(body)
    rescue JSON::ParserError
      return error_response(400, 'Invalid JSON')
    end

    # Validate required fields
    unless job_data['job_class']
      return error_response(422, 'Missing job_class parameter')
    end

    job_class = job_data['job_class']
    args = job_data['args'] || []
    options = job_data['options'] || {}
    delay = job_data['delay']
    queue = job_data['queue']

    # Validate job class exists
    unless valid_job_class?(job_class)
      return error_response(422, "Invalid job class: #{job_class}")
    end

    begin
      # Get the actual job class
      klass = Object.const_get(job_class)
      
      # Enqueue the job with proper queue handling
      if delay
        # Parse delay (seconds, time string, or duration)
        delay_time = parse_delay(delay)
        if queue
          job = klass.set(queue: queue).perform_in(delay_time, *args, **options.symbolize_keys)
        else
          job = klass.perform_in(delay_time, *args, **options.symbolize_keys)
        end
      else
        if queue
          job = klass.set(queue: queue).perform_async(*args, **options.symbolize_keys)
        else
          job = klass.perform_async(*args, **options.symbolize_keys)
        end
      end

      PowernodeWorker.application.logger.info "Enqueued job #{job_class} with ID: #{job}"

      success_response({
        job_id: job,
        job_class: job_class,
        enqueued_at: Time.current.iso8601,
        delay: delay
      }.compact)

    rescue NameError => e
      PowernodeWorker.application.logger.error "Job class not found: #{job_class} - #{e.message}"
      error_response(422, "Job class not found: #{job_class}")
    rescue ArgumentError => e
      PowernodeWorker.application.logger.error "Invalid job arguments for #{job_class}: #{e.message}"
      error_response(422, "Invalid job arguments: #{e.message}")
    rescue StandardError => e
      PowernodeWorker.application.logger.error "Failed to enqueue job #{job_class}: #{e.message}"
      error_response(500, "Failed to enqueue job: #{e.message}")
    end
  end

  def authenticated?(request)
    auth_header = request.env['HTTP_AUTHORIZATION']
    return false unless auth_header

    token = auth_header.sub(/^Bearer /, '')
    return false if token.empty?

    # Check if token matches the configured WORKER_TOKEN
    expected_token = PowernodeWorker.application.config.worker_token
    return false unless expected_token

    token == expected_token
  end

  def valid_job_class?(job_class)
    # List of allowed job classes for security
    allowed_jobs = [
      'Billing::BillingAutomationJob',
      'Billing::PaymentRetryJob',
      'Billing::SubscriptionLifecycleJob',
      'Billing::BillingSchedulerJob',
      'Billing::BillingCleanupJob',
      'Reports::GenerateReportJob',
      'Reports::ScheduledReportJob',
      'Webhooks::ProcessWebhookJob',
      'Analytics::RecalculateAnalyticsJob',
      'Analytics::UpdateRevenueSnapshotsJob',
      'SendNotificationEmailJob',
      'TestEmailJob',
      'TestWorkerJob',
      'RefreshEmailSettingsJob',
      'Notifications::EmailDeliveryJob',
      'Notifications::BulkEmailJob',
      'Notifications::TransactionalEmailJob',
      'Services::TestPaymentGatewayConnectionJob'
    ]

    allowed_jobs.include?(job_class)
  end

  def parse_delay(delay)
    case delay
    when Numeric
      delay # Assume seconds
    when String
      if delay.match?(/^\d+$/)
        delay.to_i # Numeric string in seconds
      else
        # Try to parse as duration (e.g., "1.hour", "30.minutes")
        eval(delay) # Note: This is not safe in production without proper validation
      end
    else
      raise ArgumentError, "Invalid delay format: #{delay}"
    end
  rescue StandardError
    raise ArgumentError, "Unable to parse delay: #{delay}"
  end

  def success_response(data)
    [200, 
     {'content-type' => 'application/json'}, 
     [data.to_json]]
  end

  def error_response(status, message)
    [status, 
     {'content-type' => 'application/json'}, 
     [{error: message, timestamp: Time.current.iso8601}.to_json]]
  end

  def not_found_response
    error_response(404, 'Not found')
  end
  
  def jwt_secret_key
    ENV['JWT_SECRET_KEY'] || 'development_jwt_secret_key_that_persists_across_restarts_and_is_secure_enough_for_local_development_only'
  end
end