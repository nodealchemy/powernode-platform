# frozen_string_literal: true

module RateLimiting
  extend ActiveSupport::Concern

  included do
    before_action :check_and_increment_rate_limit
  end

  private

  def check_and_increment_rate_limit
    return unless should_rate_limit?
    return unless SystemSettingsService.rate_limiting_enabled?
    return if RateLimitService.temporarily_disabled?

    key = rate_limit_key
    current_count = Rails.cache.read(key) || 0
    max_attempts = rate_limit_max_attempts

    if current_count >= max_attempts
      render_rate_limit_exceeded
      return
    end
    
    # Store the current count for potential increment after request
    @rate_limit_key = key
    @rate_limit_current_count = current_count
  end

  def increment_rate_limit_count
    return unless @rate_limit_key && @rate_limit_current_count

    new_count = @rate_limit_current_count + 1
    window_seconds = rate_limit_window_seconds
    Rails.cache.write(@rate_limit_key, new_count, expires_in: window_seconds.seconds)

    # Log rate limiting for monitoring
    Rails.logger.info "Rate limit increment: #{rate_limit_key} = #{new_count}/#{rate_limit_max_attempts} (window: #{window_seconds}s)"
  end

  def render_rate_limit_exceeded
    render_error(
      "Rate limit exceeded. Too many attempts. Please try again later.",
      status: :too_many_requests,
      code: "RATE_LIMITED",
      details: {
        retry_after: rate_limit_window_seconds,
        limit: rate_limit_max_attempts,
        window: rate_limit_window_seconds
      }
    )
  end

  def should_rate_limit?
    # Default to true for all API endpoints - can be overridden
    true
  end

  def rate_limit_key
    # Include user ID if authenticated for more granular limiting
    identifier = current_user ? "user_#{current_user.id}" : "ip_#{request.remote_ip}"
    "rate_limit:#{controller_name}:#{action_name}:#{identifier}"
  end

  def rate_limit_max_attempts
    # Get limit from system settings based on endpoint type
    limit_type = rate_limit_type
    SystemSettingsService.rate_limit_setting(limit_type) || default_rate_limit_for_type(limit_type)
  end

  def rate_limit_window_seconds
    # Determine window based on rate limit type
    limit_type = rate_limit_type
    if limit_type.include?('per_minute')
      60  # 1 minute
    else
      3600  # 1 hour (default)
    end
  end

  def rate_limit_type
    # Determine rate limit type based on controller and action
    case controller_name
    when 'sessions'
      'login_attempts_per_hour'
    when 'registrations'
      'registration_attempts_per_hour'
    when 'passwords'
      'password_reset_attempts_per_hour'
    when 'email_verifications'
      'email_verification_attempts_per_hour'
    when 'webhooks'
      'webhook_requests_per_minute'
    when 'impersonation_sessions'
      'impersonation_attempts_per_hour'
    else
      authenticated_request? ? 'authenticated_requests_per_hour' : 'api_requests_per_minute'
    end
  end

  def default_rate_limit_for_type(limit_type)
    # Fallback limits if system settings are unavailable
    defaults = {
      'api_requests_per_minute' => 60,
      'authenticated_requests_per_hour' => 200,
      'login_attempts_per_hour' => 10,
      'registration_attempts_per_hour' => 5,
      'password_reset_attempts_per_hour' => 3,
      'email_verification_attempts_per_hour' => 10,
      'webhook_requests_per_minute' => 100,
      'impersonation_attempts_per_hour' => 5,
      'websocket_connections_per_minute' => 10
    }
    
    defaults[limit_type] || 30
  end

  def authenticated_request?
    current_user.present?
  rescue
    false
  end
end
