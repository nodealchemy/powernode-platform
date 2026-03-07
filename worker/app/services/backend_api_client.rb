# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'oj'
require_relative 'concerns/circuit_breaker'

# API client for worker-to-backend communication
# Handles all HTTP requests to the Rails backend with service authentication
class BackendApiClient
  include CircuitBreaker
  class ApiError < StandardError
    attr_reader :status, :response_body

    def initialize(message, status = nil, response_body = nil)
      super(message)
      @status = status
      @response_body = response_body
    end
  end

  def initialize
    @config = PowernodeWorker.application.config
    @logger = PowernodeWorker.application.logger
    @connection = build_connection
  end

  # Account operations
  def get_account(account_id)
    get("/api/v1/accounts/#{account_id}")
  end

  def get_account_subscription(account_id)
    # Get account data which includes subscription info
    account_data = get("/api/v1/accounts/#{account_id}")
    account_data['subscription']
  end

  # Analytics operations
  def get_analytics(type, params = {})
    get("/api/v1/analytics/#{type}", params)
  end

  # Report operations
  def create_report(report_data)
    post("/api/v1/reports", report_data)
  end

  def get_scheduled_reports(params = {})
    get("/api/v1/reports/scheduled", params)
  end

  def update_scheduled_report(report_id, data)
    put("/api/v1/reports/scheduled/#{report_id}", data)
  end

  # Report request management methods
  def get_report_request(request_id)
    get("/api/v1/reports/requests/#{request_id}")
  end

  def update_report_request_status(request_id, status)
    patch("/api/v1/reports/requests/#{request_id}", { status: status })
  end

  def complete_report_request(request_id, file_path: nil, file_size: nil, file_url: nil)
    patch("/api/v1/reports/requests/#{request_id}", {
      status: 'completed',
      file_path: file_path,
      file_size: file_size,
      file_url: file_url,
      completed_at: Time.current.iso8601
    })
  end

  def fail_report_request(request_id, error_message)
    patch("/api/v1/reports/requests/#{request_id}", {
      status: 'failed',
      error_message: error_message,
      completed_at: Time.current.iso8601
    })
  end

  # Get report data for generation
  def get_report_data(report_type, account_id = nil, parameters = {})
    params = {
      report_type: report_type,
      parameters: parameters
    }
    params[:account_id] = account_id if account_id
    
    get("/api/v1/analytics/export", params)
  end

  # Service authentication verification
  def verify_service_token
    post("/api/v1/service/verify", {})
  end

  # User authentication for web interface access
  def authenticate_user(email, password)
    post("/api/v1/worker_auth/authenticate_user", {
      email: email,
      password: password
    })
  end

  # Platform JWT verification for web interface access
  def verify_platform_token(token)
    post("/api/v1/worker_auth/verify_platform_token", { token: token })
  end

  # Session verification for authenticated users
  def verify_session(session_token)
    post("/api/v1/worker_auth/verify_session", {
      session_token: session_token
    })
  end

  # Health check
  def health_check
    get("/api/v1/health")
  end

  # Subscription operations (for billing jobs)
  def get_subscription_data(account_id: nil, status: nil)
    params = {}
    params[:account_id] = account_id if account_id
    params[:status] = status if status
    get('/api/v1/subscriptions', params)
  end

  def update_subscription_status(subscription_id, status, metadata = {})
    patch("/api/v1/subscriptions/#{subscription_id}", {
      status: status,
      metadata: metadata
    })
  end

  # Invoice operations
  def get_invoice_data(account_id: nil, status: nil, **params)
    query_params = params.dup
    query_params[:account_id] = account_id if account_id
    query_params[:status] = status if status
    get('/api/v1/invoices', query_params)
  end

  def create_invoice(subscription_id, line_items)
    post('/api/v1/invoices', {
      subscription_id: subscription_id,
      line_items: line_items
    })
  end

  # Report generation
  def generate_pdf_report(report_type, account_id: nil, start_date: nil, end_date: nil, user_id: nil)
    post('/api/v1/reports/generate', {
      reports: [{
        type: report_type,
        format: 'pdf'
      }],
      account_id: account_id,
      start_date: start_date,
      end_date: end_date,
      user_id: user_id
    })
  end

  # Webhook event updates
  def update_webhook_event(event_id, status, error_message = nil)
    patch("/api/v1/webhooks/events/#{event_id}", {
      status: status,
      error_message: error_message
    })
  end

  # File processing operations
  def get_file_processing_job(job_id)
    get("/api/v1/worker/processing_jobs/#{job_id}")
  end

  def update_file_processing_job(job_id, data)
    patch("/api/v1/worker/processing_jobs/#{job_id}", data)
  end

  def complete_file_processing_job(job_id, result_data = {})
    patch("/api/v1/worker/processing_jobs/#{job_id}", {
      status: 'completed',
      result_data: result_data,
      completed_at: Time.current.iso8601
    })
  end

  def fail_file_processing_job(job_id, error_message, error_data = {})
    patch("/api/v1/worker/processing_jobs/#{job_id}", {
      status: 'failed',
      error_details: {
        error_message: error_message
      }.merge(error_data),
      completed_at: Time.current.iso8601
    })
  end

  # File object operations
  def get_file_object(file_id)
    get("/api/v1/worker/files/#{file_id}")
  end

  def update_file_object(file_id, data)
    patch("/api/v1/worker/files/#{file_id}", data)
  end

  def download_file_content(file_id)
    # Returns binary file content
    response = @connection.get do |req|
      req.url "/api/v1/worker/files/#{file_id}/download"
      req.headers['Authorization'] = "Bearer #{WorkerJwt.token}"
    end

    if response.status == 200
      response.body
    else
      raise ApiError.new("Failed to download file #{file_id}", response.status, response.body)
    end
  end

  def upload_processed_file(file_id, file_content, metadata = {})
    # Upload binary file content with metadata
    payload = {
      file_content: Base64.strict_encode64(file_content),
      metadata: metadata
    }

    post("/api/v1/worker/files/#{file_id}/processed", payload)
  end

  # Quarantine an infected file
  def quarantine_file(file_id, quarantine_data = {})
    post("/api/v1/worker/files/#{file_id}/quarantine", quarantine_data)
  end

  def make_request(method, path, data = {})
    # Use circuit breaker for all backend API requests
    with_backend_api_circuit_breaker do
      start_time = Time.current

      begin
        response = @connection.send(method) do |req|
          req.url path
          req.headers['Authorization'] = "Bearer #{WorkerJwt.token}"
          req.headers['Content-Type'] = 'application/json'
          req.headers['Accept'] = 'application/json'
          req.headers['User-Agent'] = 'PowernodeWorker/1.0'

          case method
          when :get, :delete
            req.params = data if data.any?
          else
            req.body = data if data.any?
          end
        end

        duration = Time.current - start_time
        @logger.debug "[BackendAPI] #{method.upcase} #{path} completed in #{duration.round(3)}s"

        handle_response(response)

      rescue Faraday::TimeoutError => e
        @logger.error "[BackendAPI] Request timeout for #{method.upcase} #{path}: #{e.message}"
        raise ApiError.new("Request timeout: #{e.message}", 408)
      rescue Faraday::ConnectionFailed => e
        @logger.error "[BackendAPI] Connection failed for #{method.upcase} #{path}: #{e.message}"
        raise ApiError.new("Connection failed: #{e.message}", 503)
      rescue Faraday::Error => e
        @logger.error "[BackendAPI] Request failed for #{method.upcase} #{path}: #{e.message}"
        raise ApiError.new("Request failed: #{e.message}")
      end
    end
  rescue CircuitOpenError => e
    @logger.warn "[BackendAPI] Circuit breaker OPEN: #{e.message}"
    raise ApiError.new("Service temporarily unavailable: #{e.message}", 503)
  end

  private

  def build_connection
    Faraday.new(url: @config.backend_api_url) do |conn|
      # Request/response middleware
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      
      # Retry middleware with exponential backoff
      conn.request :retry,
                   max: @config.max_retry_attempts,
                   interval: 0.5,
                   interval_randomness: 0.5,
                   backoff_factor: 2,
                   retry_statuses: [500, 502, 503, 504],
                   methods: [:get, :post, :put, :patch, :delete]

      # Timeout configuration
      conn.options.timeout = @config.api_timeout
      conn.options.read_timeout = @config.api_timeout
      conn.options.write_timeout = @config.api_timeout

      # Logging adapter
      development_env = ENV['WORKER_ENV'] == 'development' || ENV['RAILS_ENV'] == 'development' || (!ENV['WORKER_ENV'] && !ENV['RAILS_ENV'])
      conn.response :logger, @logger, { headers: false, bodies: false } if development_env
      
      # HTTP adapter
      conn.adapter Faraday.default_adapter
    end
  end

  # HTTP methods - made public for testing and API flexibility
  public

  def get(path, params = {})
    make_request(:get, path, params)
  end

  def post(path, data = {})
    make_request(:post, path, data)
  end

  # POST with a named circuit breaker instead of the default backend_api one.
  # Use for long-running requests that would exceed the default 120s timeout.
  def post_with_circuit_breaker(path, data = {}, circuit_breaker: nil)
    breaker_method = case circuit_breaker
                     when :trading_training then :with_trading_training_circuit_breaker
                     when :workflow_execution then :with_workflow_execution_circuit_breaker
                     else :with_backend_api_circuit_breaker
                     end

    send(breaker_method) do
      start_time = Time.current
      response = @connection.post do |req|
        req.url path
        req.headers['Authorization'] = "Bearer #{WorkerJwt.token}"
        req.headers['Content-Type'] = 'application/json'
        req.headers['Accept'] = 'application/json'
        req.headers['User-Agent'] = 'PowernodeWorker/1.0'
        req.body = data if data.any?
        # Override default Faraday timeout for long-running requests
        req.options.timeout = 3600
        req.options.read_timeout = 3600
      end
      duration = Time.current - start_time
      @logger.debug "[BackendAPI] POST #{path} completed in #{duration.round(3)}s"
      handle_response(response)
    end
  rescue CircuitBreaker::CircuitOpenError => e
    @logger.warn "[BackendAPI] Circuit breaker OPEN: #{e.message}"
    raise ApiError.new("Service temporarily unavailable: #{e.message}", 503)
  end

  def put(path, data = {})
    make_request(:put, path, data)
  end

  def patch(path, data = {})
    make_request(:patch, path, data)
  end

  def delete(path, params = {})
    make_request(:delete, path, params)
  end

  private

  def handle_response(response)
    case response.status
    when 200..299
      response.body
    when 400
      error_msg = extract_error_message(response.body) || "Bad request"
      @logger.warn "Bad request: #{error_msg}"
      raise ApiError.new(error_msg, response.status, response.body)
    when 401
      error_msg = "Service authentication failed"
      @logger.error error_msg
      raise ApiError.new(error_msg, response.status, response.body)
    when 403
      error_msg = "Service access forbidden"
      @logger.error error_msg
      raise ApiError.new(error_msg, response.status, response.body)
    when 404
      error_msg = extract_error_message(response.body) || "Resource not found"
      @logger.warn "Resource not found: #{error_msg}"
      raise ApiError.new(error_msg, response.status, response.body)
    when 422
      error_msg = extract_error_message(response.body) || "Unprocessable entity"
      @logger.warn "Validation error: #{error_msg}"
      raise ApiError.new(error_msg, response.status, response.body)
    when 500..599
      error_msg = "Backend server error"
      @logger.error "#{error_msg}: #{response.status}"
      raise ApiError.new(error_msg, response.status, response.body)
    else
      error_msg = "Unexpected response: #{response.status}"
      @logger.error error_msg
      raise ApiError.new(error_msg, response.status, response.body)
    end
  end

  def extract_error_message(response_body)
    return nil unless response_body.is_a?(Hash)
    
    # Try standard message fields first
    return response_body['message'] if response_body['message']
    return response_body['error'] if response_body['error']
    
    # Handle 'errors' field which can be a hash or array
    errors = response_body['errors']
    if errors.is_a?(Hash)
      return errors['message'] if errors['message']
    elsif errors.is_a?(Array) && errors.any?
      return errors.first
    end
    
    nil
  end
end