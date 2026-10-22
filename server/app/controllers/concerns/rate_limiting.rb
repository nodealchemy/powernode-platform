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
    # read_counter, not read: increment stores a raw counter on RedisCacheStore,
    # which a plain read returns as nil.
    current_count = Rails.cache.read_counter(key).to_i

    if current_count >= rate_limit_max_attempts
      render_error(
        "Rate limit exceeded. Too many attempts. Please try again later.",
        status: :too_many_requests,
        details: { retry_after: rate_limit_window_seconds }
      )
      return
    end
    # Store the current count for potential increment after request
    @rate_limit_key = key
    @rate_limit_current_count = current_count
  end

  # Atomic, and the window is fixed from the first attempt: increment keeps an
  # existing entry's expiry and only a new entry takes expires_in. Writing
  # "count read earlier + 1" lost attempts when two requests read the same count
  # on a shared store, and restarted the window on every attempt.
  def increment_rate_limit_count
    return unless @rate_limit_key

    Rails.cache.increment(@rate_limit_key, 1, expires_in: rate_limit_window_seconds.seconds)
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
