# frozen_string_literal: true

class Api::V1::Auth::PasswordsController < ApplicationController
  include RateLimiting
  
  skip_before_action :authenticate_request, only: [ :forgot, :reset ]
  after_action :increment_rate_limit_count, only: [:forgot, :reset], if: -> { response.status >= 400 }

  # POST /api/v1/passwords/forgot
  def forgot
    return render json: { success: false, error: "Email is required" }, status: :bad_request if params[:email].blank?

    user = User.find_by(email: params[:email]&.downcase)

    if user&.active? && user.email_verified?
      # Generate and save password reset token
      user.generate_reset_token!

      # Send password reset email
      UserMailer.password_reset(user).deliver_now
    end

    # Always return success to prevent email enumeration
    render json: {
      success: true,
      message: "If an account with that email exists, password reset instructions have been sent."
    }, status: :ok
  rescue => e
    Rails.logger.error "Password reset error: #{e.message}"
    render json: {
      success: false,
      error: "An error occurred. Please try again later."
    }, status: :internal_server_error
  end

  # POST /api/v1/passwords/reset
  def reset
    return render json: { success: false, error: "Reset token is required" }, status: :bad_request if params[:token].blank?
    return render json: { success: false, error: "New password is required" }, status: :bad_request if params[:password].blank?

    begin
      payload = JWT.decode(params[:token], Rails.application.config.jwt_secret_key, true, algorithm: "HS256").first
      user_id = payload["user_id"]
      token_type = payload["type"]

      unless token_type == "password_reset"
        return render json: {
          success: false,
          error: "Invalid reset token"
        }, status: :unauthorized
      end

      user = User.find_by(id: user_id)
      unless user
        return render json: {
          success: false,
          error: "Invalid reset token"
        }, status: :unauthorized
      end

      if user.reset_password!(params[:password], params[:token])
        render json: {
          success: true,
          message: "Password has been reset successfully"
        }, status: :ok
      else
        render json: {
          success: false,
          error: "Failed to reset password",
          details: user.errors.full_messages
        }, status: :unprocessable_content
      end
    rescue JWT::ExpiredSignature
      render json: {
        success: false,
        error: "Reset token has expired"
      }, status: :unauthorized
    rescue JWT::DecodeError
      render json: {
        success: false,
        error: "Invalid reset token"
      }, status: :unauthorized
    rescue => e
      Rails.logger.error "Password reset error: #{e.message}"
      render json: {
        success: false,
        error: "An error occurred. Please try again later."
      }, status: :internal_server_error
    end
  end

  # PUT /api/v1/passwords/change
  def change
    if current_user.authenticate(change_params[:current_password])
      current_user.update!(
        password: change_params[:new_password],
        password_confirmation: change_params[:password_confirmation]
      )

      render json: {
        success: true,
        message: "Password changed successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Current password is incorrect"
      }, status: :unauthorized
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      error: "Password change failed",
      details: e.record.errors.full_messages
    }, status: :unprocessable_content
  end

  private

  def should_rate_limit?
    true # Always rate limit password reset attempts
  end

  def rate_limit_max_attempts
    3 # Allow only 3 password reset attempts per IP per 15 minutes
  end

  def rate_limit_window_seconds
    900 # 15 minutes
  end

  def change_params
    params.require(:password).permit(:current_password, :new_password, :password_confirmation)
  end
end
