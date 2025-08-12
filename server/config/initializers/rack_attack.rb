# frozen_string_literal: true

class Rack::Attack
  # Enable rate limiting in all environments (can be disabled via env var or admin settings)
  Rails.application.config.rate_limiting_enabled = !Rails.env.test? && (
    begin
      SystemSettingsService.rate_limiting_enabled?
    rescue
      ENV['DISABLE_RATE_LIMITING'] != 'true' # Fallback to env var if service fails
    end
  )

  # Helper method to get rate limits from system settings
  def self.get_rate_limit(setting_key, fallback_limit)
    begin
      SystemSettingsService.rate_limit_setting(setting_key) || fallback_limit
    rescue
      fallback_limit
    end
  end
  
  # Helper method to check if rate limiting is enabled at runtime
  def self.rate_limiting_enabled?
    begin
      SystemSettingsService.rate_limiting_enabled?
    rescue
      ENV['DISABLE_RATE_LIMITING'] != 'true'
    end
  end

  # Apply throttling in development, staging, and production
  unless Rails.env.test?
    # Strict throttling for authentication endpoints
    throttle("auth_login_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit('login_attempts_per_hour', 10) : 999999 }, period: 1.hour) do |request|
      if request.path == "/api/v1/auth/login" && request.post?
        request.ip
      end
    end

    # Throttle registration attempts
    throttle("auth_register_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit('registration_attempts_per_hour', 5) : 999999 }, period: 1.hour) do |request|
      if request.path == "/api/v1/auth/register" && request.post?
        request.ip
      end
    end

    # Throttle password reset requests
    throttle("auth_password_reset_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit('password_reset_attempts_per_hour', 3) : 999999 }, period: 1.hour) do |request|
      if (request.path == "/api/v1/auth/forgot-password" || request.path == "/api/v1/auth/reset-password") && request.post?
        request.ip
      end
    end

    # Throttle email verification attempts
    throttle("auth_email_verification_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit('email_verification_attempts_per_hour', 10) : 999999 }, period: 1.hour) do |request|
      if request.path.include?("/verify-email") || request.path.include?("/resend-verification")
        request.ip
      end
    end

    # Throttle admin/impersonation endpoints using system settings
    throttle("admin_impersonation_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit('impersonation_attempts_per_hour', Rails.env.development? ? 50 : 5) : 999999 }, period: 1.hour) do |request|
      if request.path.include?("/impersonation") || request.path.include?("/admin/users")
        request.ip
      end
    end

    # General API throttling using system settings
    throttle("api_requests_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit('api_requests_per_minute', Rails.env.development? ? 1000 : 300) : 999999 }, period: 15.minutes) do |request|
      if request.path.start_with?("/api/")
        request.ip
      end
    end

    # Per-user throttling for authenticated endpoints using system settings
    throttle("auth_requests_by_user", limit: proc { rate_limiting_enabled? ? get_rate_limit('authenticated_requests_per_hour', 200) : 999999 }, period: 1.hour) do |request|
      if request.path.start_with?("/api/") && request.env["rack.session"]
        # Extract user ID from JWT token if present
        auth_header = request.get_header("HTTP_AUTHORIZATION")
        if auth_header&.start_with?("Bearer ")
          token = auth_header.split(" ")[1]
          begin
            decoded = JWT.decode(token, Rails.application.credentials.jwt_secret_key, true, algorithm: 'HS256')
            decoded[0]["user_id"] if decoded[0]
          rescue JWT::DecodeError
            nil
          end
        end
      end
    end

    # Webhook throttling using system settings
    throttle("webhook_requests_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit('webhook_requests_per_minute', 100) : 999999 }, period: 1.minute) do |request|
      if request.path.start_with?("/webhooks/")
        request.ip
      end
    end
  end

  # Block IPs that are clearly malicious
  blocklist("malicious_ips") do |request|
    # You can add known bad IPs here
    false # For now, don't block any IPs
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]

    headers = {
      "Content-Type" => "application/json",
      "Retry-After" => match_data[:period].to_s,
      "X-RateLimit-Limit" => match_data[:limit].to_s,
      "X-RateLimit-Remaining" => "0",
      "X-RateLimit-Reset" => (now + match_data[:period]).to_s
    }

    body = {
      success: false,
      error: "Too many requests",
      message: "Rate limit exceeded. Please try again later."
    }.to_json

    [ 429, headers, [ body ] ]
  end

  # Custom response for blocked requests
  self.blocklisted_responder = lambda do |request|
    [ 403, { "Content-Type" => "application/json" }, [ {
      success: false,
      error: "Forbidden",
      message: "Your request has been blocked."
    }.to_json ] ]
  end
end

# Enable Rack::Attack middleware in all environments except test
unless Rails.env.test?
  Rails.application.config.middleware.use Rack::Attack
end

# Add logging for rate limit hits
ActiveSupport::Notifications.subscribe("rack.attack") do |name, start, finish, request_id, payload|
  request = payload[:request]
  if request.env["rack.attack.throttle_data"]
    Rails.logger.warn "Rate limit hit: #{request.ip} - #{request.path} - #{request.env['rack.attack.throttle_data']}"
  end
end
