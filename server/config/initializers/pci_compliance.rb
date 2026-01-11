# frozen_string_literal: true

# PCI Compliance Configuration
Rails.application.configure do
  # Add PCI security headers middleware (disabled for testing - would be enabled in production)
  # config.middleware.use 'PciSecurityHeaders'

  # Force SSL in production for PCI DSS requirement
  if Rails.env.production?
    config.force_ssl = true
    config.ssl_options = {
      hsts: {
        expires: 1.year,
        subdomains: true,
        preload: true
      },
      secure_cookies: true,
      redirect: {
        exclude: ->(request) { request.path.start_with?("/health") }
      }
    }
  end

  # Session security for PCI compliance
  config.session_store :cookie_store,
    key: "_powernode_session",
    secure: Rails.env.production?,
    httponly: true,
    same_site: :strict,
    expire_after: 30.minutes

  # Configure sensitive parameter filtering for PCI DSS
  config.filter_parameters += [
    :password, :password_confirmation,
    :card_number, :cardnumber, :credit_card_number,
    :cvv, :cvc, :cvn, :security_code, :verification_value,
    :exp_month, :exp_year, :expiry_month, :expiry_year,
    :track_data, :track1, :track2,
    :pin, :pincode, :passcode,
    :account_number, :routing_number, :aba_number,
    :ssn, :social_security_number,
    :secret_key, :api_key, :webhook_secret,
    :stripe_secret_key, :paypal_client_secret,
    /\Acard.*number\z/i, /\Acredit.*card\z/i,
    /\Aexp.*date\z/i, /\Aexpir/i,
    /\Asecurity.*code\z/i, /\Averification/i
  ]

  # PCI-compliant logging configuration
  config.log_level = Rails.env.production? ? :info : :debug

  # Custom log formatter that sanitizes sensitive data
  config.log_formatter = proc do |severity, timestamp, progname, msg|
    sanitized_msg = if msg.is_a?(String)
                      DataManagement::Sanitizer.sanitize_string(msg)
    else
                      msg
    end

    "[#{timestamp}] #{severity} -- #{progname}: #{sanitized_msg}\n"
  end

  # Configure ActionController parameter filtering (Rails 8 compatible)
  # Note: parameter_filter_policy is not available in Rails 8, using filter_parameters instead

  # Additional security configurations
  config.assume_ssl = true if Rails.env.production?

  # Rate limiting configuration (if using rack-attack)
  if defined?(Rack::Attack)
    # Throttle payment endpoints more aggressively
    Rack::Attack.throttle("payment_api", limit: 10, period: 1.minute) do |req|
      req.ip if req.path.start_with?("/api/v1/payment", "/api/v1/billing")
    end

    # Block requests from known malicious IPs
    Rack::Attack.blocklist("block_malicious_ips") do |req|
      # This would be populated with actual malicious IP data
      false
    end
  end
end

# PCI DSS Requirement: Regularly test security systems
# This initializer also sets up security monitoring hooks
ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  # Log security-relevant events
  if event.payload[:controller]&.include?("Payment") ||
     event.payload[:controller]&.include?("Billing") ||
     event.payload[:action]&.include?("webhook")

    # Sanitize and log security events
    sanitized_params = DataManagement::Sanitizer.sanitize_hash(event.payload[:params] || {})

    Rails.logger.info "SECURITY_EVENT: #{event.payload[:controller]}##{event.payload[:action]} " \
                      "IP: #{event.payload[:remote_ip]} " \
                      "Duration: #{event.duration.round(2)}ms " \
                      "Status: #{event.payload[:status]}"
  end
end

# Monitor for potential security violations
ActiveSupport::Notifications.subscribe("security.data_access") do |name, start, finish, id, payload|
  # Log all payment data access for audit trails (PCI DSS requirement)
  Rails.logger.info "DATA_ACCESS: #{payload[:resource_type]} " \
                    "User: #{payload[:user_id]} " \
                    "Account: #{payload[:account_id]} " \
                    "Action: #{payload[:action]}"
end
