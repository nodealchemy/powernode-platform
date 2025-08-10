require 'faraday'
require 'faraday/retry'
require 'oj'

# API client for worker-to-backend communication
# Handles all HTTP requests to the Rails backend with service authentication
class BackendApiClient
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
    get("/api/v1/accounts/#{account_id}/subscription")
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

  # Service authentication verification
  def verify_service_token
    post("/api/v1/service/verify", {})
  end

  # Health check
  def health_check
    get("/api/v1/health")
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

  def get(path, params = {})
    make_request(:get, path, params)
  end

  def post(path, data = {})
    make_request(:post, path, data)
  end

  def put(path, data = {})
    make_request(:put, path, data)
  end

  def patch(path, data = {})
    make_request(:patch, path, data)
  end

  def delete(path)
    make_request(:delete, path)
  end

  def make_request(method, path, data = {})
    response = @connection.send(method) do |req|
      req.url path
      req.headers['Authorization'] = "Bearer #{@config.service_token}"
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

    handle_response(response)
  rescue Faraday::TimeoutError => e
    @logger.error "API request timeout: #{e.message}"
    raise ApiError.new("Request timeout: #{e.message}", 408)
  rescue Faraday::ConnectionFailed => e
    @logger.error "API connection failed: #{e.message}"
    raise ApiError.new("Connection failed: #{e.message}", 503)
  rescue Faraday::Error => e
    @logger.error "API request failed: #{e.message}"
    raise ApiError.new("Request failed: #{e.message}")
  end

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
    
    response_body['message'] || 
    response_body['error'] ||
    response_body.dig('errors', 'message') ||
    (response_body['errors'].is_a?(Array) ? response_body['errors'].first : nil)
  end
end