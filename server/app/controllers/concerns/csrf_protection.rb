# frozen_string_literal: true

module CsrfProtection
  extend ActiveSupport::Concern

  included do
    # Only apply CSRF protection for write operations when enabled
    before_action :verify_csrf_token, if: :csrf_protection_enabled?
  end

  private

  def csrf_protection_enabled?
    # Check if CSRF protection is enabled in settings
    # For write operations (POST, PUT, PATCH, DELETE)
    request.method_symbol.in?([ :post, :put, :patch, :delete ]) &&
      Rails.configuration.x.csrf_protection_enabled == true
  end

  def verify_csrf_token
    token = extract_csrf_token

    unless token && valid_csrf_token?(token)
      render_csrf_error
      return false
    end

    true
  end

  def extract_csrf_token
    # Check for CSRF token in header (preferred method for APIs)
    token = request.headers["X-CSRF-Token"]

    # Fall back to parameter if header is not present
    token ||= params[:_csrf_token] if Rails.configuration.x.csrf_allow_parameter

    token
  end

  def valid_csrf_token?(token)
    return false unless token.present?

    # For API-only applications, we use a simple secure random token approach
    # This token should be obtained via a GET request to /api/v1/csrf_token
    stored_token = Rails.cache.read("csrf_token_#{current_user&.id}")

    return false unless stored_token.present?

    # Use secure comparison to prevent timing attacks
    ActiveSupport::SecurityUtils.secure_compare(token, stored_token)
  end

  def render_csrf_error
    render_error("CSRF token verification failed", status: :forbidden, code: "CSRF_INVALID")
  end

  def generate_csrf_token
    # Generate a new CSRF token for the current user
    return nil unless current_user

    token = SecureRandom.base64(32)
    Rails.cache.write(
      "csrf_token_#{current_user.id}",
      token,
      expires_in: Rails.configuration.x.csrf_token_expiry || 2.hours
    )

    token
  end
end
