# frozen_string_literal: true

# SecurityHeaders middleware adds security-related HTTP headers to all responses
# This provides defense-in-depth against common web vulnerabilities
class SecurityHeaders
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    # Add security headers
    add_security_headers(headers)

    [ status, headers, body ]
  end

  private

  def add_security_headers(headers)
    # Prevent clickjacking
    headers["X-Frame-Options"] ||= "DENY"

    # Prevent MIME type sniffing
    headers["X-Content-Type-Options"] ||= "nosniff"

    # Enable XSS filter in browsers
    headers["X-XSS-Protection"] ||= "1; mode=block"

    # Control referrer information
    headers["Referrer-Policy"] ||= "strict-origin-when-cross-origin"

    # Restrict browser features/APIs
    headers["Permissions-Policy"] ||= "microphone=(), camera=(), geolocation=()"

    # Prevent cross-domain policy file loading
    headers["X-Permitted-Cross-Domain-Policies"] ||= "none"

    # Content Security Policy (API mode - relaxed for JSON responses)
    # More restrictive CSP should be set for HTML pages
    headers["Content-Security-Policy"] ||= build_csp unless api_request?(headers)
  end

  def build_csp
    [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: https:",
      "font-src 'self'",
      "connect-src 'self'",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ].join("; ")
  end

  def api_request?(headers)
    content_type = headers["Content-Type"] || ""
    content_type.include?("application/json")
  end
end
