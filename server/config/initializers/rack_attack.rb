# frozen_string_literal: true

class Rack::Attack
  # =========================================================================
  # CONFIGURATION
  # =========================================================================

  # Enable rate limiting in all environments (can be disabled via env var or admin settings)
  Rails.application.config.rate_limiting_enabled = !Rails.env.test? && (
    begin
      SystemSettingsService.rate_limiting_enabled?
    rescue StandardError
      ENV["DISABLE_RATE_LIMITING"] != "true" # Fallback to env var if service fails
    end
  )

  # =========================================================================
  # HELPER METHODS
  # =========================================================================

  # Helper method to get rate limits from system settings
  def self.get_rate_limit(setting_key, fallback_limit)
    SystemSettingsService.rate_limit_setting(setting_key) || fallback_limit
  rescue StandardError
    fallback_limit
  end

  # Helper method to check if rate limiting is enabled at runtime
  def self.rate_limiting_enabled?
    SystemSettingsService.rate_limiting_enabled?
  rescue StandardError
    ENV["DISABLE_RATE_LIMITING"] != "true"
  end

  # Extract user from JWT token
  def self.extract_user_from_request(request)
    auth_header = request.get_header("HTTP_AUTHORIZATION")
    return nil unless auth_header&.start_with?("Bearer ")

    token = auth_header.split(" ")[1]
    decoded = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: "HS256")
    user_id = decoded[0]["user_id"]
    User.find_by(id: user_id) if user_id
  rescue JWT::DecodeError, ActiveRecord::RecordNotFound
    nil
  end

  # Extract account from request (via user or API key)
  def self.extract_account_from_request(request)
    # Try to get from user first
    user = extract_user_from_request(request)
    return user.account if user&.account

    # Try to get from API key
    api_key = request.get_header("HTTP_X_API_KEY")
    if api_key
      key = ApiKey.active.find_by(key_hash: Digest::SHA256.hexdigest(api_key))
      return key.account if key&.account
    end

    nil
  end

  # Get tier-based limit for an account
  def self.tier_based_limit(account, limit_type)
    return 999_999 unless rate_limiting_enabled?

    tier = TieredRateLimitService.tier_for_account(account)
    config = TieredRateLimitService.tier_config(tier)
    config[limit_type.to_sym] || 999_999
  end

  # =========================================================================
  # THROTTLE RULES
  # =========================================================================

  unless Rails.env.test?
    # -----------------------------------------------------------------------
    # AUTHENTICATION ENDPOINTS (Strict limits - not tier-based)
    # -----------------------------------------------------------------------

    # Login attempts - IP-based
    throttle("auth_login_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("login_attempts_per_hour", 10) : 999_999 }, period: 1.hour) do |request|
      if request.path == "/api/v1/auth/login" && request.post?
        request.ip
      end
    end

    # Login attempts - by email (prevent brute force on specific account)
    throttle("auth_login_by_email", limit: proc { rate_limiting_enabled? ? 5 : 999_999 }, period: 1.hour) do |request|
      if request.path == "/api/v1/auth/login" && request.post?
        begin
          body = JSON.parse(request.body.read)
          request.body.rewind
          body["email"]&.downcase
        rescue StandardError
          nil
        end
      end
    end

    # Registration attempts - IP-based
    throttle("auth_register_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("registration_attempts_per_hour", 5) : 999_999 }, period: 1.hour) do |request|
      if request.path == "/api/v1/auth/register" && request.post?
        request.ip
      end
    end

    # Password reset requests - IP-based
    throttle("auth_password_reset_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("password_reset_attempts_per_hour", 3) : 999_999 }, period: 1.hour) do |request|
      if (request.path == "/api/v1/auth/forgot-password" || request.path == "/api/v1/auth/reset-password") && request.post?
        request.ip
      end
    end

    # Email verification attempts - IP-based
    throttle("auth_email_verification_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("email_verification_attempts_per_hour", 10) : 999_999 }, period: 1.hour) do |request|
      if request.path.include?("/verify-email") || request.path.include?("/resend-verification")
        request.ip
      end
    end

    # 2FA attempts - stricter limits
    throttle("auth_2fa_by_ip", limit: proc { rate_limiting_enabled? ? 5 : 999_999 }, period: 15.minutes) do |request|
      if request.path.include?("/two_factor") && request.post?
        request.ip
      end
    end

    # -----------------------------------------------------------------------
    # TIER-BASED API RATE LIMITING (Account-level)
    # -----------------------------------------------------------------------

    # Account-level API throttling - per minute
    throttle("account_api_per_minute", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :api_requests_per_minute)
    }, period: 1.minute) do |request|
      if request.path.start_with?("/api/")
        account = extract_account_from_request(request)
        "account:#{account.id}" if account
      end
    end

    # Account-level API throttling - per hour
    throttle("account_api_per_hour", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :api_requests_per_hour)
    }, period: 1.hour) do |request|
      if request.path.start_with?("/api/")
        account = extract_account_from_request(request)
        "account:#{account.id}" if account
      end
    end

    # -----------------------------------------------------------------------
    # HEAVY OPERATIONS (AI, Reports, Exports)
    # -----------------------------------------------------------------------

    throttle("heavy_operations_by_account", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :heavy_requests_per_hour)
    }, period: 1.hour) do |request|
      heavy_paths = %w[/api/v1/ai_ /api/v1/workflows /api/v1/reports /api/v1/analytics /api/v1/data_export /api/v1/bulk_]
      if heavy_paths.any? { |path| request.path.start_with?(path) }
        account = extract_account_from_request(request)
        "heavy:account:#{account.id}" if account
      end
    end

    # -----------------------------------------------------------------------
    # FILE OPERATIONS
    # -----------------------------------------------------------------------

    throttle("file_uploads_by_account", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :file_uploads_per_hour)
    }, period: 1.hour) do |request|
      if request.path.match?(%r{^/api/v1/files?}) && request.post?
        account = extract_account_from_request(request)
        "files:account:#{account.id}" if account
      end
    end

    # -----------------------------------------------------------------------
    # WEBHOOK OPERATIONS
    # -----------------------------------------------------------------------

    throttle("webhook_requests_by_account", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :webhook_requests_per_minute)
    }, period: 1.minute) do |request|
      if request.path.start_with?("/webhooks/") || request.path.start_with?("/api/v1/webhook")
        account = extract_account_from_request(request)
        "webhooks:account:#{account.id}" if account
      end
    end

    # Incoming webhook throttling by IP (external services calling us)
    throttle("incoming_webhooks_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("webhook_requests_per_minute", 100) : 999_999 }, period: 1.minute) do |request|
      if request.path.start_with?("/webhooks/")
        request.ip
      end
    end

    # -----------------------------------------------------------------------
    # WEBSOCKET CONNECTIONS
    # -----------------------------------------------------------------------

    throttle("websocket_connections_by_account", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :websocket_connections_per_minute)
    }, period: 1.minute) do |request|
      if request.path == "/cable" && request.get_header("HTTP_UPGRADE")&.downcase == "websocket"
        account = extract_account_from_request(request)
        "websocket:account:#{account.id}" if account
      end
    end

    # WebSocket by IP (fallback for unauthenticated)
    throttle("websocket_connections_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("websocket_connections_per_minute", Rails.env.development? ? 30 : 10) : 999_999 }, period: 1.minute) do |request|
      if request.path == "/cable" && request.get_header("HTTP_UPGRADE")&.downcase == "websocket"
        request.ip
      end
    end

    # -----------------------------------------------------------------------
    # ADMIN/IMPERSONATION ENDPOINTS
    # -----------------------------------------------------------------------

    throttle("admin_impersonation_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("impersonation_attempts_per_hour", Rails.env.development? ? 50 : 5) : 999_999 }, period: 1.hour) do |request|
      if request.path.include?("/impersonation") || request.path.include?("/admin/users")
        request.ip
      end
    end

    throttle("impersonation_by_user", limit: proc { rate_limiting_enabled? ? get_rate_limit("impersonation_attempts_per_hour", Rails.env.development? ? 50 : 5) : 999_999 }, period: 1.hour) do |request|
      if (request.path.include?("/impersonation") || request.path.include?("/admin/users")) && request.post?
        user = extract_user_from_request(request)
        "user:#{user.id}" if user
      end
    end

    # -----------------------------------------------------------------------
    # IP-BASED FALLBACK (for unauthenticated requests)
    # -----------------------------------------------------------------------

    throttle("api_requests_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("api_requests_per_minute", Rails.env.development? ? 1000 : 300) : 999_999 }, period: 15.minutes) do |request|
      if request.path.start_with?("/api/") && !extract_account_from_request(request)
        request.ip
      end
    end

    # -----------------------------------------------------------------------
    # OAUTH ENDPOINTS (Based on application tier)
    # -----------------------------------------------------------------------

    throttle("oauth_token_requests", limit: proc { rate_limiting_enabled? ? 100 : 999_999 }, period: 1.hour) do |request|
      if request.path == "/oauth/token" && request.post?
        request.ip
      end
    end

    throttle("oauth_authorize_requests", limit: proc { rate_limiting_enabled? ? 50 : 999_999 }, period: 1.hour) do |request|
      if request.path == "/oauth/authorize"
        request.ip
      end
    end
  end

  # =========================================================================
  # BLOCKLIST RULES
  # =========================================================================

  # Block IPs that are clearly malicious
  blocklist("malicious_ips") do |request|
    # You can add known bad IPs here
    false # For now, don't block any IPs
  end

  # Block accounts that exceed extreme limits (10x normal)
  blocklist("extreme_abuse") do |request|
    next false unless rate_limiting_enabled?

    account = extract_account_from_request(request)
    next false unless account

    # Check if account has been flagged for abuse
    cache_key = "abuse_block:account:#{account.id}"
    Rails.cache.read(cache_key).present?
  end

  # =========================================================================
  # SAFELIST RULES
  # =========================================================================

  # Safelist trusted internal services
  safelist("internal_services") do |request|
    # Allow requests from localhost in development
    Rails.env.development? && [ "127.0.0.1", "::1" ].include?(request.ip)
  end

  # Safelist specific API keys (e.g., system workers)
  safelist("system_api_keys") do |request|
    api_key = request.get_header("HTTP_X_API_KEY")
    next false unless api_key

    # Check if it's a system API key
    cache_key = "system_api_key:#{Digest::SHA256.hexdigest(api_key)}"
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      key = ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(api_key))
      key&.metadata&.dig("is_system_key") == true
    end
  rescue StandardError
    false
  end

  # =========================================================================
  # RESPONSE HANDLERS
  # =========================================================================

  # Custom response for throttled requests
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]

    # Try to get tier-specific info
    account = extract_account_from_request(request)
    tier = account ? TieredRateLimitService.tier_for_account(account) : :free
    tier_config = TieredRateLimitService.tier_config(tier)

    headers = {
      "Content-Type" => "application/json",
      "Retry-After" => match_data[:period].to_s,
      "X-RateLimit-Limit" => match_data[:limit].to_s,
      "X-RateLimit-Remaining" => "0",
      "X-RateLimit-Reset" => (now + match_data[:period]).to_s,
      "X-RateLimit-Tier" => tier.to_s,
      "X-RateLimit-Tier-Name" => tier_config[:name]
    }

    body = {
      success: false,
      error: "Too many requests",
      message: "Rate limit exceeded. Please try again later.",
      tier: tier.to_s,
      tier_name: tier_config[:name],
      retry_after: match_data[:period],
      upgrade_available: tier != :enterprise && tier != :unlimited
    }.to_json

    [ 429, headers, [ body ] ]
  end

  # Custom response for blocked requests
  self.blocklisted_responder = lambda do |_request|
    [ 403, { "Content-Type" => "application/json" }, [ {
      success: false,
      error: "Forbidden",
      message: "Your request has been blocked due to excessive abuse."
    }.to_json ] ]
  end
end

# Enable Rack::Attack middleware in all environments except test
unless Rails.env.test?
  Rails.application.config.middleware.use Rack::Attack
end

# =========================================================================
# LOGGING & MONITORING
# =========================================================================

# Add logging for rate limit hits
ActiveSupport::Notifications.subscribe("rack.attack") do |_name, _start, _finish, _request_id, payload|
  request = payload[:request]

  if request.env["rack.attack.matched"]
    match_type = request.env["rack.attack.match_type"]
    match_data = request.env["rack.attack.match_data"]

    case match_type
    when :throttle
      Rails.logger.warn(
        "[RateLimit] Throttled: " \
        "IP=#{request.ip} " \
        "Path=#{request.path} " \
        "Rule=#{request.env['rack.attack.matched']} " \
        "Count=#{match_data[:count]}/#{match_data[:limit]} " \
        "Period=#{match_data[:period]}s"
      )
    when :blocklist
      Rails.logger.error(
        "[RateLimit] Blocked: " \
        "IP=#{request.ip} " \
        "Path=#{request.path} " \
        "Rule=#{request.env['rack.attack.matched']}"
      )
    end
  end
end
