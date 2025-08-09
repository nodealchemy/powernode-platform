# frozen_string_literal: true

SecureHeaders::Configuration.default do |config|
  # Enable security headers in production/staging or when HTTPS is detected
  # This allows tests to simulate production behavior with HTTPS headers
  is_production_like = Rails.env.production? || Rails.env.staging?

  # Configure based on environment
  if is_production_like
    # Deny all framing (prevents clickjacking)
    config.x_frame_options = "DENY"

    # Prevent MIME type sniffing
    config.x_content_type_options = "nosniff"

    # Enable XSS filtering
    config.x_xss_protection = "1; mode=block"

    # Force HTTPS for 1 year (31536000 seconds)
    config.hsts = "max-age=31536000; includeSubDomains; preload"

    # Referrer policy - only send referrer for same origin
    config.referrer_policy = "strict-origin-when-cross-origin"

    # Content Security Policy - restrictive but allows API functionality
    config.csp = {
      # Allow resources from same origin by default
      default_src: %w['self'],

      # Scripts only from same origin
      script_src: %w['self'],

      # Stylesheets from same origin
      style_src: %w['self'],

      # Images from same origin and data URIs
      img_src: %w['self' data:],

      # Fonts from same origin
      font_src: %w['self'],

      # API should not load external content
      connect_src: %w['self'],

      # No plugins allowed
      object_src: %w['none'],

      # No media elements expected in API
      media_src: %w['none'],

      # No frames
      frame_src: %w['none']

      # Report CSP violations (can be configured later)
      # report_uri: %w[/csp-violation-report-endpoint]
    }
  else
    # In development/test, use more permissive settings
    config.x_frame_options = "SAMEORIGIN"
    config.x_content_type_options = "nosniff"
    config.x_xss_protection = "1; mode=block"

    # No HSTS in development - use OPT_OUT constant
    config.hsts = SecureHeaders::OPT_OUT

    # More permissive CSP for development
    config.csp = {
      default_src: %w['self' 'unsafe-inline' 'unsafe-eval'],
      script_src: %w['self' 'unsafe-inline' 'unsafe-eval'],
      style_src: %w['self' 'unsafe-inline'],
      img_src: %w['self' data: http: https:],
      font_src: %w['self' data:],
      connect_src: %w['self' http: https: ws: wss:],
      object_src: %w['none'],
      frame_src: %w['self']
    }
  end

  # Disable features that we don't need for an API
  config.x_download_options = SecureHeaders::OPT_OUT
  config.x_permitted_cross_domain_policies = SecureHeaders::OPT_OUT
end
