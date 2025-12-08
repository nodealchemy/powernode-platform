# frozen_string_literal: true

# Middleware for API key authentication
# Supports multiple authentication strategies: API key, Bearer token
class ApiKeyAuthentication
  API_KEY_HEADER = 'X-API-Key'
  AUTHORIZATION_HEADER = 'Authorization'
  API_KEY_PARAM = 'api_key'

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    # Skip API key auth for non-API routes
    unless api_route?(request.path)
      return @app.call(env)
    end

    # Try to authenticate via API key
    api_key_token = extract_api_key(request)

    if api_key_token.present?
      authenticate_api_key(env, api_key_token, request)
    else
      # Pass through - let other authentication methods handle it
      @app.call(env)
    end
  end

  private

  def api_route?(path)
    path.start_with?('/api/')
  end

  def extract_api_key(request)
    # Try X-API-Key header first
    api_key = request.get_header("HTTP_#{API_KEY_HEADER.upcase.tr('-', '_')}")
    return api_key if api_key.present?

    # Try Bearer token with api_key prefix
    auth_header = request.get_header("HTTP_#{AUTHORIZATION_HEADER.upcase.tr('-', '_')}")
    if auth_header.present?
      # Support "Bearer api_key_xxxx" format
      match = auth_header.match(/\ABearer\s+(api_key_\w+)\z/i)
      return match[1] if match

      # Support "ApiKey xxxx" format
      match = auth_header.match(/\AApiKey\s+(\S+)\z/i)
      return match[1] if match
    end

    # Try query parameter (not recommended, but supported)
    request.params[API_KEY_PARAM] if request.params[API_KEY_PARAM].present?
  end

  def authenticate_api_key(env, token, request)
    api_key = ApiKey.find_by_token(token)

    unless api_key
      return unauthorized_response('Invalid API key')
    end

    # Check if API key is active
    unless api_key.active?
      return unauthorized_response('API key is inactive or expired')
    end

    # Check IP restrictions
    if api_key.ip_restrictions.present?
      client_ip = request.ip
      unless ip_allowed?(api_key.ip_restrictions, client_ip)
        log_security_event(api_key, 'api_key_ip_blocked', request)
        return forbidden_response('IP address not allowed for this API key')
      end
    end

    # Check rate limits for API key
    if rate_limited?(api_key, request)
      return rate_limited_response(api_key)
    end

    # Check scope permissions
    env['api_key'] = api_key
    env['api_key_scopes'] = api_key.scopes || []
    env['current_user'] = api_key.user
    env['current_account'] = api_key.account || api_key.user&.account

    # Track API key usage
    track_usage(api_key, request)

    @app.call(env)
  end

  def ip_allowed?(restrictions, client_ip)
    return true if restrictions.blank?

    allowed_ips = restrictions.is_a?(String) ? restrictions.split(',').map(&:strip) : restrictions

    allowed_ips.any? do |pattern|
      if pattern.include?('/')
        # CIDR notation
        IPAddr.new(pattern).include?(client_ip)
      elsif pattern.include?('*')
        # Wildcard pattern
        regex = Regexp.new("\\A#{pattern.gsub('*', '\\d+')}\\z")
        client_ip.match?(regex)
      else
        # Exact match
        pattern == client_ip
      end
    end
  rescue IPAddr::InvalidAddressError
    false
  end

  def rate_limited?(api_key, request)
    # Check if API key has custom rate limit
    return false unless api_key.rate_limit.present?

    cache_key = "api_key:#{api_key.id}:requests:#{Time.current.beginning_of_minute.to_i}"
    current_count = Rails.cache.read(cache_key).to_i

    current_count >= api_key.rate_limit
  end

  def track_usage(api_key, request)
    # Update last used timestamp
    api_key.touch(:last_used_at)

    # Increment request count
    api_key.increment!(:request_count)

    # Track in cache for rate limiting
    if api_key.rate_limit.present?
      cache_key = "api_key:#{api_key.id}:requests:#{Time.current.beginning_of_minute.to_i}"
      Rails.cache.increment(cache_key, 1, expires_in: 2.minutes)
    end

    # Log API access
    Rails.logger.info(
      "API Key Access: key_id=#{api_key.id} " \
      "endpoint=#{request.path} method=#{request.request_method} " \
      "ip=#{request.ip}"
    )
  rescue StandardError => e
    Rails.logger.error("Failed to track API key usage: #{e.message}")
  end

  def log_security_event(api_key, event_type, request)
    Rails.logger.warn(
      "API Key Security Event: #{event_type} " \
      "key_id=#{api_key.id} ip=#{request.ip} " \
      "endpoint=#{request.path}"
    )

    # Create audit log if possible
    AuditLog.create(
      action: 'api_access_denied',
      resource_type: 'ApiKey',
      resource_id: api_key.id,
      account: api_key.account || api_key.user&.account,
      user: api_key.user,
      ip_address: request.ip,
      user_agent: request.user_agent,
      source: 'api',
      severity: 'high',
      risk_level: 'medium',
      details: {
        event_type: event_type,
        endpoint: request.path,
        method: request.request_method
      }
    )
  rescue StandardError => e
    Rails.logger.error("Failed to log security event: #{e.message}")
  end

  def unauthorized_response(message)
    [
      401,
      {
        'Content-Type' => 'application/json',
        'WWW-Authenticate' => 'ApiKey realm="API"'
      },
      [{ success: false, error: message }.to_json]
    ]
  end

  def forbidden_response(message)
    [
      403,
      { 'Content-Type' => 'application/json' },
      [{ success: false, error: message }.to_json]
    ]
  end

  def rate_limited_response(api_key)
    retry_after = 60 - Time.current.sec # Seconds until next minute

    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s,
        'X-RateLimit-Limit' => api_key.rate_limit.to_s,
        'X-RateLimit-Remaining' => '0',
        'X-RateLimit-Reset' => (Time.current.beginning_of_minute + 1.minute).to_i.to_s
      },
      [{ success: false, error: 'Rate limit exceeded' }.to_json]
    ]
  end
end

# Concern for controllers to check API key scopes
module ApiKeyAuthorization
  extend ActiveSupport::Concern

  included do
    before_action :check_api_key_scope, if: :api_key_request?
  end

  private

  def api_key_request?
    request.env['api_key'].present?
  end

  def current_api_key
    request.env['api_key']
  end

  def api_key_scopes
    request.env['api_key_scopes'] || []
  end

  def check_api_key_scope
    required_scope = scope_for_action
    return if required_scope.blank?

    unless scope_allowed?(required_scope)
      render json: {
        success: false,
        error: "API key does not have required scope: #{required_scope}"
      }, status: :forbidden
    end
  end

  def scope_allowed?(scope)
    return true if api_key_scopes.include?('*') # Wildcard scope

    api_key_scopes.any? do |allowed|
      scope == allowed ||
        (allowed.end_with?(':*') && scope.start_with?(allowed.chomp(':*')))
    end
  end

  def scope_for_action
    # Override in controllers to specify required scope
    # Example: 'users:read', 'billing:manage', etc.
    nil
  end
end
