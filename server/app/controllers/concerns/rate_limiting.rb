# frozen_string_literal: true

module RateLimiting
  extend ActiveSupport::Concern

  included do
    before_action :check_and_increment_rate_limit
  end

  private

  def check_and_increment_rate_limit
    return unless should_rate_limit?
    return if ENV["DISABLE_RATE_LIMITING"] == "true"

    key = rate_limit_key
    current_count = Rails.cache.read(key) || 0

    if current_count >= rate_limit_max_attempts
      render json: {
        success: false,
        error: "rate limit exceeded. Too many attempts. Please try again later.",
        retry_after: rate_limit_window_seconds
      }, status: :too_many_requests
      return
    end
    # Store the current count for potential increment after request
    @rate_limit_key = key
    @rate_limit_current_count = current_count
  end

  def increment_rate_limit_count
    return unless @rate_limit_key && @rate_limit_current_count

    new_count = @rate_limit_current_count + 1
    Rails.cache.write(@rate_limit_key, new_count, expires_in: rate_limit_window_seconds.seconds)
  end

  def should_rate_limit?
    # Override in controllers that need rate limiting
    false
  end

  def rate_limit_key
    "rate_limit:#{controller_name}:#{request.remote_ip}"
  end

  def rate_limit_max_attempts
    5 # Default max attempts
  end

  def rate_limit_window_seconds
    300 # Default 5 minutes
  end
end
