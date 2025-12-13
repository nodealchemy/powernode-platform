# frozen_string_literal: true

require 'net/http'
require 'timeout'

# Shared concern for AI-related job functionality
# Provides enhanced error handling, circuit breaker integration, and structured logging
module AiJobsConcern
  extend ActiveSupport::Concern

  included do
    require_relative '../../services/concerns/circuit_breaker'
    include CircuitBreaker
  end

  # Enhanced backend API methods with structured logging
  # Note: Circuit breaker is handled by BackendApiClient directly
  def backend_api_get(path, params = {})
    log_api_request('GET', path, params)
    start_time = Time.current

    begin
      result = api_client.get(path, params)
      duration = Time.current - start_time

      log_api_success('GET', path, duration, result)
      result
    rescue StandardError => e
      duration = Time.current - start_time
      log_api_error('GET', path, duration, e)
      raise
    end
  end

  def backend_api_post(path, data = {})
    log_api_request('POST', path, data)
    start_time = Time.current

    begin
      result = api_client.post(path, data)
      duration = Time.current - start_time

      log_api_success('POST', path, duration, result)
      result
    rescue StandardError => e
      duration = Time.current - start_time
      log_api_error('POST', path, duration, e)
      raise
    end
  end

  def backend_api_patch(path, data = {})
    log_api_request('PATCH', path, data)
    start_time = Time.current

    begin
      result = api_client.patch(path, data)
      duration = Time.current - start_time

      log_api_success('PATCH', path, duration, result)
      result
    rescue StandardError => e
      duration = Time.current - start_time
      log_api_error('PATCH', path, duration, e)
      raise
    end
  end

  def backend_api_put(path, data = {})
    log_api_request('PUT', path, data)
    start_time = Time.current

    begin
      result = api_client.put(path, data)
      duration = Time.current - start_time

      log_api_success('PUT', path, duration, result)
      result
    rescue StandardError => e
      duration = Time.current - start_time
      log_api_error('PUT', path, duration, e)
      raise
    end
  end

  def backend_api_delete(path)
    log_api_request('DELETE', path)
    start_time = Time.current

    begin
      result = api_client.delete(path)
      duration = Time.current - start_time

      log_api_success('DELETE', path, duration, result)
      result
    rescue StandardError => e
      duration = Time.current - start_time
      log_api_error('DELETE', path, duration, e)
      raise
    end
  end

  # Enhanced HTTP request method with circuit breaker for external APIs
  def make_http_request(url, method: :get, headers: {}, body: nil, timeout: 300)
    # Extract provider/service name from URL for circuit breaker
    service_name = extract_service_name(url)

    with_ai_provider_circuit_breaker(service_name) do
      start_time = Time.current

      begin
        # Use Net::HTTP for external requests
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = timeout
        http.open_timeout = timeout

        # Prepare request
        case method
        when :get
          request = Net::HTTP::Get.new(uri)
        when :post
          request = Net::HTTP::Post.new(uri)
          request.body = body if body
        when :put
          request = Net::HTTP::Put.new(uri)
          request.body = body if body
        when :patch
          request = Net::HTTP::Patch.new(uri)
          request.body = body if body
        when :delete
          request = Net::HTTP::Delete.new(uri)
        else
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

        # Set headers
        headers.each { |key, value| request[key] = value }

        # Make request
        response = http.request(request)
        duration = Time.current - start_time

        log_external_api_success(method, url, duration, response)
        response

      rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
        duration = Time.current - start_time
        log_external_api_error(method, url, duration, e)
        raise
      rescue StandardError => e
        duration = Time.current - start_time
        log_external_api_error(method, url, duration, e)
        raise
      end
    end
  rescue CircuitBreaker::CircuitOpenError => e
    log_circuit_breaker_open(method, url, e)
    # Return a mock response for circuit breaker scenarios
    mock_response = Class.new do
      def code; 503; end
      def body; '{"error": "Service temporarily unavailable"}'; end
    end
    mock_response.new
  end

  # Enhanced error handling with structured logging
  def handle_ai_processing_error(error, context = {})
    # Add job context
    # Access retry count from Sidekiq's job context if available
    # Sidekiq stores retry count in the job's payload
    job_retry_count = begin
                        # Try to get retry count from current job if available
                        if defined?(jid) && jid
                          # Access from Sidekiq's current job context
                          current_job = Thread.current['sidekiq_context']
                          current_job&.dig('retry_count') || 0
                        else
                          0
                        end
                      rescue
                        0
                      end

    enhanced_context = context.merge(
      job_class: self.class.name,
      retry_count: job_retry_count,
      queue: self.class.get_sidekiq_options['queue']
    )

    # Track error in centralized error tracking service (if available)
    # Comment out for now as the service doesn't exist yet
    # AiWorkflowErrorTrackingService.instance.track_error(error, enhanced_context)

    error_data = {
      error_class: error.class.name,
      error_message: error.message,
      context: enhanced_context,
      timestamp: Time.current.iso8601,
      job_class: self.class.name,
      circuit_breaker_status: circuit_breaker_status
    }

    # Log structured error
    log_error("[AI_JOB_ERROR] #{error_data.to_json}")

    # Additional error tracking based on error type
    case error
    when BackendApiClient::ApiError
      track_api_error(error, enhanced_context)
    when CircuitBreaker::CircuitOpenError
      track_circuit_breaker_error(error, enhanced_context)
    when Net::ReadTimeout, Net::OpenTimeout, Timeout::Error
      track_timeout_error(error, enhanced_context)
    else
      track_generic_error(error, enhanced_context)
    end

    # Re-raise for Sidekiq retry mechanism
    raise error
  end

  private

  # Backend API client instance
  def api_client
    @api_client ||= BackendApiClient.new
  end

  # Structured logging methods
  def log_api_request(method, path, data = {})
    data_summary = data.is_a?(Hash) ? { keys: data.keys, size: data.size } : { size: data.to_s.length }
    log_info("[API_REQUEST] #{method} #{path} | #{data_summary.to_json}")
  end

  def log_api_success(method, path, duration, result)
    success = result.is_a?(Hash) ? result['success'] : 'unknown'
    log_info("[API_SUCCESS] #{method} #{path} | duration=#{duration.round(3)}s success=#{success}")
  end

  def log_api_error(method, path, duration, error)
    log_error("[API_ERROR] #{method} #{path} | duration=#{duration.round(3)}s error=#{error.class.name} message=#{error.message}")
  end

  def log_circuit_breaker_open(method, path, error)
    log_warn("[CIRCUIT_BREAKER] #{method} #{path} | status=OPEN message=#{error.message}")
  end

  def log_external_api_success(method, url, duration, response)
    log_info("[EXTERNAL_API_SUCCESS] #{method} #{url} | duration=#{duration.round(3)}s status=#{response.code}")
  end

  def log_external_api_error(method, url, duration, error)
    log_error("[EXTERNAL_API_ERROR] #{method} #{url} | duration=#{duration.round(3)}s error=#{error.class.name} message=#{error.message}")
  end

  # Extract service name from URL for circuit breaker naming
  def extract_service_name(url)
    uri = URI(url)

    # Special handling for known AI providers
    case uri.host
    when /localhost/
      'ollama_local'
    when /api\.openai\.com/
      'openai'
    when /api\.anthropic\.com/
      'anthropic'
    when /api\.cohere\.ai/
      'cohere'
    else
      # Use hostname as service name
      uri.host&.gsub('.', '_') || 'unknown_service'
    end
  rescue StandardError
    'unknown_service'
  end

  # Error tracking methods
  def track_api_error(error, context)
    # Could integrate with error tracking service
    log_warn("[ERROR_TRACKING] Backend API error: #{error.status} - #{error.message}")
  end

  def track_circuit_breaker_error(error, context)
    log_warn("[ERROR_TRACKING] Circuit breaker error: #{error.message}")
  end

  def track_timeout_error(error, context)
    log_warn("[ERROR_TRACKING] Timeout error: #{error.message}")
  end

  def track_generic_error(error, context)
    log_warn("[ERROR_TRACKING] Generic error: #{error.class.name} - #{error.message}")
  end
end