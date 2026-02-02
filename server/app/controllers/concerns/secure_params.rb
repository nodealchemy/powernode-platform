# frozen_string_literal: true

module SecureParams
  extend ActiveSupport::Concern

  included do
    rescue_from Security::InputValidationService::ValidationError do |e|
      render_error("Validation error: #{e.message}", status: :bad_request)
    end

    rescue_from Security::RateLimiter::RateLimitExceeded do |e|
      response.headers["Retry-After"] = e.retry_after.to_s
      response.headers["X-RateLimit-Limit"] = e.limit.to_s
      response.headers["X-RateLimit-Remaining"] = "0"
      render_error(e.message, status: :too_many_requests)
    end
  end

  protected

  # Validate and sanitize text input
  def validate_text(value, field:, max_length: 10_000, allow_html: false)
    Security::InputValidationService.validate_text!(value, field: field, max_length: max_length, allow_html: allow_html)
  end

  # Validate path/filename
  def validate_path(value, field:)
    Security::InputValidationService.validate_path!(value, field: field)
  end

  # Validate command input
  def validate_command(value, field:)
    Security::InputValidationService.validate_command_input!(value, field: field)
  end

  # Validate and sanitize AI prompt input
  def validate_prompt(value, field:)
    Security::InputValidationService.validate_prompt!(value, field: field)
  end

  # Sanitize external message for AI
  def sanitize_message(content, source: "external")
    Security::InputValidationService.sanitize_external_message(content, source: source)
  end

  # Validate UUID
  def validate_uuid(value, field:)
    Security::InputValidationService.validate_uuid!(value, field: field)
  end

  # Validate URL
  def validate_url(value, field:, allowed_schemes: %w[http https])
    Security::InputValidationService.validate_url!(value, field: field, allowed_schemes: allowed_schemes)
  end

  # Validate domain
  def validate_domain(value, field:)
    Security::InputValidationService.validate_domain!(value, field: field)
  end

  # Validate JSON
  def validate_json(value, field:)
    Security::InputValidationService.validate_json!(value, field: field)
  end

  # Validate execution ID
  def validate_execution_id(value, field:)
    Security::InputValidationService.validate_execution_id!(value, field: field)
  end

  # Apply rate limiting
  def check_rate_limit!(category: :api_default, key: nil)
    rate_key = key || rate_limit_key
    result = Security::RateLimiter.check!(
      key: rate_key,
      category: category,
      account_id: current_user&.account_id
    )

    response.headers["X-RateLimit-Limit"] = result[:limit].to_s
    response.headers["X-RateLimit-Remaining"] = result[:remaining].to_s
    response.headers["X-RateLimit-Reset"] = result[:reset_at].to_i.to_s
  end

  # Get rate limit status
  def rate_limit_status(category: :api_default, key: nil)
    rate_key = key || rate_limit_key
    Security::RateLimiter.usage(
      key: rate_key,
      category: category,
      account_id: current_user&.account_id
    )
  end

  private

  def rate_limit_key
    # Default: IP address or user ID
    if current_user.present?
      "user:#{current_user.id}"
    else
      "ip:#{request.remote_ip}"
    end
  end
end
