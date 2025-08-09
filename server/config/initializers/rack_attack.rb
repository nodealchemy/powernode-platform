# frozen_string_literal: true

class Rack::Attack
  # Enable rate limiting
  Rails.application.config.rate_limiting_enabled = true

  # Throttle login attempts by IP
  throttle("login_attempts_by_ip", limit: 5, period: 15.minutes) do |request|
    if request.path == "/api/v1/auth/login" && request.post?
      request.ip
    end
  end

  # Throttle general API requests by IP
  throttle("api_requests_by_ip", limit: 300, period: 15.minutes) do |request|
    if request.path.start_with?("/api/")
      request.ip
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

# Enable Rack::Attack middleware
Rails.application.config.middleware.use Rack::Attack
