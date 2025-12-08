# frozen_string_literal: true

class ApplicationController < ActionController::API
  include Authentication
  include ApiResponse

  # JWT error handling (DecodeError is parent, so list it first for correct priority)
  rescue_from JWT::DecodeError, with: :handle_invalid_token
  rescue_from JWT::VerificationError, with: :handle_invalid_signature
  rescue_from JWT::ExpiredSignature, with: :handle_expired_token

  # Standard pagination parameters helper
  def pagination_params
    {
      page: [ params[:page]&.to_i || 1, 1 ].max,
      per_page: [ [ params[:per_page]&.to_i || 20, 1 ].max, 100 ].min
    }
  end

  private

  def handle_expired_token
    render json: { success: false, error: 'Token has expired' }, status: :unauthorized
  end

  def handle_invalid_signature
    render json: { success: false, error: 'Invalid token signature' }, status: :unauthorized
  end

  def handle_invalid_token
    render json: { success: false, error: 'Invalid token format' }, status: :unauthorized
  end
end
