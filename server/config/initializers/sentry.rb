# frozen_string_literal: true

# Sentry Error Tracking Configuration
# https://docs.sentry.io/platforms/ruby/guides/rails/

if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]

    # Environment identification
    config.environment = Rails.env

    # Enable performance monitoring
    config.enable_tracing = true

    # Sample rate for performance monitoring (0.0 to 1.0)
    # In production, start with a lower rate and adjust based on volume
    config.traces_sample_rate = Rails.env.production? ? 0.1 : 1.0

    # Sample rate for profiling (requires traces to be enabled)
    config.profiles_sample_rate = Rails.env.production? ? 0.1 : 1.0

    # Breadcrumbs configuration
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]

    # Release tracking (use git SHA or version)
    config.release = ENV.fetch("APP_VERSION") { `git rev-parse HEAD`.strip rescue "unknown" }

    # Server name for identification
    config.server_name = ENV.fetch("HOSTNAME") { Socket.gethostname rescue "unknown" }

    # Filter sensitive data
    config.before_send = lambda do |event, hint|
      # Skip certain exceptions
      if hint[:exception].is_a?(ActiveRecord::RecordNotFound) ||
         hint[:exception].is_a?(ActionController::RoutingError)
        return nil
      end

      # Scrub sensitive parameters
      if event.request&.data
        event.request.data = filter_sensitive_data(event.request.data)
      end

      event
    end

    # Filter sensitive parameters from being sent to Sentry
    config.send_default_pii = false

    # Exclude common bot user agents
    config.excluded_exceptions += [
      "ActionController::BadRequest",
      "ActionController::UnknownFormat",
      "ActionDispatch::Http::MimeNegotiation::InvalidType"
    ]

    # Background job integration
    config.rails.report_rescued_exceptions = true

    # Set async to avoid blocking requests
    config.background_worker_threads = 2
  end

  def filter_sensitive_data(data)
    return data unless data.is_a?(Hash)

    sensitive_keys = %w[
      password password_confirmation current_password
      token access_token refresh_token api_key secret
      credit_card cvv card_number
      ssn social_security
    ]

    data.transform_values.with_index do |(key, value), _|
      if sensitive_keys.any? { |k| key.to_s.downcase.include?(k) }
        "[FILTERED]"
      elsif value.is_a?(Hash)
        filter_sensitive_data(value)
      else
        value
      end
    end
  rescue StandardError
    data
  end

  Rails.logger.info "[Sentry] Initialized for environment: #{Rails.env}"
else
  Rails.logger.info "[Sentry] Skipped - SENTRY_DSN not configured"
end
