# frozen_string_literal: true

class AuditLoggingMiddleware
  def initialize(app)
    @app = app
    @audit_service = Audit::LoggingService.instance
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    # Skip non-API requests and assets
    return @app.call(env) unless should_audit?(request)

    # Set up request context for audit logging
    setup_audit_context(request)

    start_time = Time.current

    begin
      status, headers, response = @app.call(env)

      # Log successful API requests
      log_api_request(request, status, start_time) if status < 400

      [ status, headers, response ]
    rescue StandardError => error
      # Log failed API requests
      log_api_error(request, error, start_time)

      # Re-raise the error
      raise error
    ensure
      # Clean up audit context
      @audit_service.clear_context
    end
  end

  private

  def should_audit?(request)
    # Audit API requests and admin actions
    return true if request.path.start_with?("/api/")
    return true if request.path.start_with?("/admin/")
    return true if request.path.start_with?("/webhooks/")

    # Audit authentication-related requests
    return true if auth_related_path?(request.path)

    # Skip static assets and health checks
    return false if request.path.start_with?("/assets/")
    return false if request.path == "/up"
    return false if request.path == "/cable"

    false
  end

  def auth_related_path?(path)
    auth_paths = [
      "/login", "/logout", "/register", "/forgot-password",
      "/reset-password", "/verify-email", "/change-password"
    ]

    auth_paths.any? { |auth_path| path.include?(auth_path) }
  end

  def setup_audit_context(request)
    # Extract user from session or token
    user = extract_user_from_request(request)

    # Set up comprehensive request context
    context = {
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      request_id: request.request_id || SecureRandom.uuid,
      session_id: extract_session_id(request),
      referer: request.referer,
      request_method: request.method,
      request_path: request.path,
      user_id: user&.id,
      account_id: user&.account_id,
      api_endpoint: extract_api_endpoint(request),
      api_version: extract_api_version(request),
      client_info: extract_client_info(request),
      correlation_id: extract_correlation_id(request)
    }

    @audit_service.set_request_context(request)
    @audit_service.with_context(context) do
      # This block will be maintained by the middleware
    end
  end

  def log_api_request(request, status, start_time)
    return unless request.path.start_with?("/api/")

    user = extract_user_from_request(request)
    endpoint = extract_api_endpoint(request)

    # Determine action based on HTTP method and endpoint
    action = determine_api_action(request.method, endpoint, status)

    # Create dummy resource for API logging
    api_resource = create_api_resource(endpoint, request)

    response_time = ((Time.current - start_time) * 1000).round(2)

    @audit_service.log(
      action: action,
      resource: api_resource,
      user: user,
      metadata: {
        http_method: request.method,
        http_status: status,
        endpoint: endpoint,
        response_time_ms: response_time,
        request_size: calculate_request_size(request),
        user_agent: request.user_agent,
        api_version: extract_api_version(request)
      },
      severity: determine_severity_by_status(status),
      risk_level: determine_risk_by_endpoint(endpoint, request.method)
    )
  end

  def log_api_error(request, error, start_time)
    user = extract_user_from_request(request)
    endpoint = extract_api_endpoint(request)

    api_resource = create_api_resource(endpoint, request)
    response_time = ((Time.current - start_time) * 1000).round(2)

    @audit_service.log(
      action: "api_error",
      resource: api_resource,
      user: user,
      severity: "high",
      risk_level: "medium",
      metadata: {
        error_class: error.class.name,
        error_message: error.message,
        http_method: request.method,
        endpoint: endpoint,
        response_time_ms: response_time,
        backtrace: error.backtrace&.first(3),
        api_version: extract_api_version(request)
      }
    )
  end

  def extract_user_from_request(request)
    # Try to extract user from JWT token
    if request.headers["Authorization"]&.start_with?("Bearer ")
      token = request.headers["Authorization"].split(" ").last
      return decode_jwt_user(token)
    end

    # Try to extract from session
    if request.session && request.session[:user_id]
      return User.find_by(id: request.session[:user_id])
    end

    nil
  rescue StandardError => e
    Rails.logger.debug "Failed to extract user from request: #{e.message}"
    nil
  end

  def decode_jwt_user(token)
    payload = Security::JwtService.decode(token)
    user_id = payload["sub"] || payload["user_id"]
    User.find_by(id: user_id)
  rescue StandardError
    nil
  end

  def extract_session_id(request)
    request.session.id if request.session
  rescue
    nil
  end

  def extract_api_endpoint(request)
    # Extract clean endpoint from path
    path = request.path

    # Remove API version prefix
    path = path.gsub(/^\/api\/v\d+\//, "")

    # Remove ID parameters for cleaner grouping
    path = path.gsub(/\/\d+/, "/:id")
    path = path.gsub(/\/[a-f0-9-]{36}/, "/:uuid") # UUIDs

    path
  end

  def extract_api_version(request)
    match = request.path.match(/\/api\/(v\d+)\//)
    match ? match[1] : "v1"
  end

  def extract_client_info(request)
    user_agent = request.user_agent
    return {} unless user_agent

    {
      browser: extract_browser_from_ua(user_agent),
      platform: extract_platform_from_ua(user_agent),
      device_type: extract_device_type_from_ua(user_agent),
      is_mobile: user_agent.match?(/Mobile|iPhone|Android/i),
      is_bot: user_agent.match?(/bot|crawler|spider/i)
    }
  end

  def extract_correlation_id(request)
    request.headers["X-Correlation-ID"] ||
    request.headers["X-Request-ID"] ||
    SecureRandom.uuid
  end

  def determine_api_action(method, endpoint, status)
    # Use 'api_request' for all API calls since that's a valid AuditLog action
    # The HTTP method and endpoint details are captured in metadata
    status >= 400 ? "api_request_failed" : "api_request"
  end

  def create_api_resource(endpoint, request)
    OpenStruct.new(
      class: OpenStruct.new(name: "ApiEndpoint"),
      id: endpoint
    )
  end

  def determine_severity_by_status(status)
    case status
    when 200..299 then "low"
    when 300..399 then "low"
    when 400..499 then "medium"
    when 500..599 then "high"
    else "medium"
    end
  end

  def determine_risk_by_endpoint(endpoint, method)
    # Higher risk for sensitive endpoints
    high_risk_patterns = [
      /admin/, /user/, /account/, /payment/, /subscription/,
      /delete/, /suspend/, /activate/, /impersonat/
    ]

    medium_risk_patterns = [
      /setting/, /webhook/, /api_key/, /role/, /permission/
    ]

    if high_risk_patterns.any? { |pattern| endpoint.match?(pattern) }
      method.upcase == "DELETE" ? "critical" : "high"
    elsif medium_risk_patterns.any? { |pattern| endpoint.match?(pattern) }
      "medium"
    else
      "low"
    end
  end

  def calculate_request_size(request)
    # Calculate approximate request size
    headers_size = request.headers.to_h.to_s.bytesize
    body_size = request.body.respond_to?(:size) ? request.body.size : 0
    headers_size + body_size
  rescue
    0
  end

  def extract_browser_from_ua(user_agent)
    case user_agent
    when /Chrome/i then "Chrome"
    when /Firefox/i then "Firefox"
    when /Safari/i then "Safari"
    when /Edge/i then "Edge"
    when /Opera/i then "Opera"
    else "Unknown"
    end
  end

  def extract_platform_from_ua(user_agent)
    case user_agent
    when /Windows/i then "Windows"
    when /Macintosh|Mac OS/i then "macOS"
    when /Linux/i then "Linux"
    when /iPhone|iPad/i then "iOS"
    when /Android/i then "Android"
    else "Unknown"
    end
  end

  def extract_device_type_from_ua(user_agent)
    case user_agent
    when /Mobile|iPhone|Android/i then "mobile"
    when /Tablet|iPad/i then "tablet"
    else "desktop"
    end
  end
end
