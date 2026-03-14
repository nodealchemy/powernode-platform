# frozen_string_literal: true

require_relative 'backend_api_client'

class BaseWorkerService
  # Include Sidekiq::Logging if available (for runtime) but skip in tests
  include Sidekiq::Logging if defined?(Sidekiq::Logging)

  def initialize
    @api_client = BackendApiClient.new
  end

  protected

  attr_reader :api_client

  # Logger accessor - uses PowernodeWorker logger or falls back to STDOUT
  def logger
    @logger ||= if defined?(PowernodeWorker) && PowernodeWorker.application.respond_to?(:logger)
                  PowernodeWorker.application.logger
                else
                  Logger.new($stdout)
                end
  end

  # Standardized logging methods
  def log_info(message, **metadata)
    logger.info format_log_message(message, **metadata)
  end

  def log_error(message, exception = nil, **metadata)
    error_details = {
      message: message,
      exception: exception&.class&.name,
      exception_message: exception&.message,
      backtrace: exception&.backtrace&.first(5)
    }.merge(metadata).compact

    logger.error format_log_message(message, **error_details)
  end

  def log_warn(message, **metadata)
    logger.warn format_log_message(message, **metadata)
  end

  # Create audit log entry via API
  def create_audit_log(account_id: nil, action:, resource_type:, resource_id:, user_id: nil, metadata: {})
    audit_data = {
      account_id: account_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      user_id: user_id,
      source: 'worker',
      metadata: metadata,
      ip_address: '127.0.0.1', # Worker service internal IP
      user_agent: 'Worker Service'
    }.compact

    begin
      api_client.post('/api/v1/audit_logs', audit_data)
    rescue => e
      log_error("Failed to create audit log", e, audit_data: audit_data)
    end
  end

  # API retry wrapper
  def with_api_retry(max_retries: 3, &block)
    retries = 0
    begin
      yield
    rescue BackendApiClient::ApiError => e
      retries += 1
      if retries <= max_retries && e.retryable?
        log_warn("API call failed, retrying", retry_attempt: retries, error: e.message)
        sleep(2 ** retries) # Exponential backoff
        retry
      else
        log_error("API call failed after #{retries} retries", e)
        raise
      end
    end
  end

  # Helper method to safely parse JSON responses
  def parse_json_response(response)
    return response if response.is_a?(Hash)
    
    begin
      JSON.parse(response)
    rescue JSON::ParserError => e
      log_error("Failed to parse JSON response", e, response: response.to_s[0..200])
      { success: false, error: "Invalid JSON response" }
    end
  end

  # Standardized error response format
  def error_response(message, code: nil, details: nil)
    {
      success: false,
      error: message,
      error_code: code,
      details: details
    }.compact
  end

  # Standardized success response format
  def success_response(data = nil, message: nil)
    {
      success: true,
      data: data,
      message: message
    }.compact
  end

  # Format log messages with consistent structure
  def format_log_message(message, **metadata)
    if metadata.any?
      "#{message} | #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    else
      message
    end
  end

  # Validate required parameters
  def validate_required_params(params, *required_keys)
    missing_keys = required_keys.select { |key| params[key].nil? || params[key].to_s.strip.empty? }
    
    if missing_keys.any?
      raise ArgumentError, "Missing required parameters: #{missing_keys.join(', ')}"
    end
  end

  # Convert string keys to symbols recursively
  def symbolize_keys(hash)
    return hash unless hash.is_a?(Hash)
    
    hash.each_with_object({}) do |(key, value), result|
      new_key = key.is_a?(String) ? key.to_sym : key
      new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
      result[new_key] = new_value
    end
  end

  # Rate limiting helper
  def rate_limit(key, limit: 60, period: 1.minute)
    redis_key = "rate_limit:#{key}"
    current_count = Sidekiq.redis { |r| r.get(redis_key) }.to_i
    
    if current_count >= limit
      log_warn("Rate limit exceeded", key: key, limit: limit, current: current_count)
      return false
    end
    
    Sidekiq.redis do |r|
      r.multi do |multi|
        multi.incr(redis_key)
        multi.expire(redis_key, period.to_i)
      end
    end
    
    true
  end

  # Cache helper methods
  def cache_key(*parts)
    "worker:#{self.class.name.underscore}:#{parts.join(':')}"
  end

  def cached_fetch(key, expires_in: 1.hour, &block)
    cache_key = "cache:#{key}"
    
    cached_result = Sidekiq.redis { |r| r.get(cache_key) }
    
    if cached_result
      begin
        return JSON.parse(cached_result)
      rescue JSON::ParserError
        log_warn("Invalid cached data, regenerating", cache_key: cache_key)
      end
    end
    
    result = yield
    
    if result
      Sidekiq.redis do |r|
        r.set(cache_key, result.to_json, ex: expires_in.to_i)
      end
    end
    
    result
  end

  # Background job scheduling helpers
  def schedule_job(job_class, args, delay = 0)
    if delay > 0
      job_class.perform_in(delay, *args)
    else
      job_class.perform_async(*args)
    end
    
    log_info("Scheduled job", job: job_class.name, delay: delay, args: args)
  end
  
  # Notification helper
  def send_notification(type:, recipient:, subject:, body:, **options)
    notification_data = {
      type: type,
      recipient: recipient,
      subject: subject,
      body: body,
      source: 'worker_service',
      metadata: options
    }
    
    begin
      api_client.post('/api/v1/notifications', notification_data)
      log_info("Notification sent", type: type, recipient: recipient)
    rescue => e
      log_error("Failed to send notification", e, notification_data: notification_data)
    end
  end
end