# PCI Compliance Security Headers Middleware
class PciSecurityHeaders
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)
    
    # Add PCI DSS required security headers
    add_security_headers(headers, env)
    
    [status, headers, response]
  end

  private

  def add_security_headers(headers, env)
    request = Rack::Request.new(env)
    
    # Only apply to payment-related endpoints
    if payment_endpoint?(request.path)
      # Strict Transport Security (HSTS) - Required for PCI DSS
      headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains; preload'
      
      # Content Security Policy - Prevent XSS and data injection
      headers['Content-Security-Policy'] = build_csp_header
      
      # X-Frame-Options - Prevent clickjacking
      headers['X-Frame-Options'] = 'DENY'
      
      # X-Content-Type-Options - Prevent MIME sniffing
      headers['X-Content-Type-Options'] = 'nosniff'
      
      # X-XSS-Protection - Enable XSS filtering
      headers['X-XSS-Protection'] = '1; mode=block'
      
      # Referrer Policy - Control referrer information
      headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
      
      # Feature Policy / Permissions Policy
      headers['Permissions-Policy'] = build_permissions_policy
      
      # Cache Control for sensitive data
      headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, private'
      headers['Pragma'] = 'no-cache'
      headers['Expires'] = '0'
      
      # Custom security headers for PCI compliance
      headers['X-PCI-Compliant'] = 'true'
      headers['X-Sensitive-Data-Policy'] = 'no-log-no-cache'
    end
  end

  def payment_endpoint?(path)
    payment_patterns = [
      /\/api\/v1\/payment/,
      /\/api\/v1\/billing/,
      /\/webhooks\/(stripe|paypal)/,
      /\/api\/v1\/subscriptions/,
      /\/api\/v1\/invoices/
    ]
    
    payment_patterns.any? { |pattern| path.match?(pattern) }
  end

  def build_csp_header
    # Strict CSP for payment pages
    [
      "default-src 'self'",
      "script-src 'self' https://js.stripe.com https://www.paypal.com",
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
      "font-src 'self' https://fonts.gstatic.com",
      "img-src 'self' data: https:",
      "connect-src 'self' https://api.stripe.com https://api.paypal.com",
      "frame-src https://js.stripe.com https://www.paypal.com",
      "form-action 'self'",
      "base-uri 'self'",
      "object-src 'none'",
      "frame-ancestors 'none'"
    ].join('; ')
  end

  def build_permissions_policy
    [
      'camera=()',
      'microphone=()',
      'geolocation=()',
      'payment=(self)',
      'usb=()',
      'magnetometer=()',
      'gyroscope=()',
      'accelerometer=()'
    ].join(', ')
  end
end