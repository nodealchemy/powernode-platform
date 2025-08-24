# frozen_string_literal: true

require 'sidekiq'

# Base job class for all Powernode worker jobs
# Provides common functionality, error handling, and API client access
class BaseJob
  include Sidekiq::Job

  # Common job configuration
  sidekiq_options retry: 3, 
                  dead: true,
                  queue: 'default'

  # Exponential backoff retry strategy
  sidekiq_retry_in do |count, exception|
    case exception
    when BackendApiClient::ApiError
      # API errors get shorter retry intervals
      [30, 60, 180][count - 1] || 300
    else
      # Other errors use exponential backoff
      (count ** 4) + 15 + (rand(30) * (count + 1))
    end
  end

  def perform(*args)
    @started_at = Time.current
    logger.info "Starting #{self.class.name} with args: #{args.inspect}"
    
    execute(*args)
    
    @finished_at = Time.current
    duration = @finished_at - @started_at
    logger.info "Completed #{self.class.name} in #{duration.round(2)}s"
  rescue StandardError => e
    @finished_at = Time.current
    duration = @finished_at - @started_at
    logger.error "Failed #{self.class.name} after #{duration.round(2)}s: #{e.message}"
    logger.error e.backtrace.join("\n") if logger.level <= Logger::DEBUG
    raise
  end

  protected

  # Override this method in subclasses to implement job logic
  def execute(*args)
    raise NotImplementedError, "Subclasses must implement the execute method"
  end

  # API client for backend communication
  def api_client
    @api_client ||= BackendApiClient.new
  end

  # Logger instance
  def logger
    PowernodeWorker.application.logger
  end

  # Helper to safely parse JSON
  def safe_parse_json(json_string, default = {})
    return default if json_string.nil? || json_string.empty?
    
    JSON.parse(json_string)
  rescue JSON::ParserError => e
    logger.warn "Failed to parse JSON: #{e.message}, using default: #{default}"
    default
  end

  # Helper to format currency amounts
  def format_currency(cents, currency = 'USD')
    return '$0.00' unless cents&.positive?
    
    dollars = cents.to_f / 100
    "$#{'%.2f' % dollars}"
  end

  # Helper to validate required parameters
  def validate_required_params(params, *required_keys)
    missing_keys = required_keys - params.keys.map(&:to_s)
    
    if missing_keys.any?
      raise ArgumentError, "Missing required parameters: #{missing_keys.join(', ')}"
    end
  end

  # Helper to handle API errors with retry logic
  def with_api_retry(max_attempts: 3, &block)
    attempts = 0
    
    begin
      attempts += 1
      yield
    rescue BackendApiClient::ApiError => e
      if attempts < max_attempts && retryable_error?(e)
        logger.warn "API call failed (attempt #{attempts}/#{max_attempts}): #{e.message}, retrying..."
        sleep(2 ** attempts) # Exponential backoff
        retry
      else
        logger.error "API call failed after #{attempts} attempts: #{e.message}"
        raise
      end
    end
  end

  private

  def retryable_error?(error)
    case error.status
    when 408, 429, 500, 502, 503, 504
      true
    else
      false
    end
  end
end