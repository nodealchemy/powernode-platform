# frozen_string_literal: true

class Api::V1::Auth::PasswordsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :forgot, :reset ]

  # POST /api/v1/passwords/forgot
  def forgot
    return render_error("Email is required", status: :bad_request) if params[:email].blank?

    user = User.find_by(email: params[:email]&.downcase)

    if user&.active? && user.email_verified?
      # Generate and save password reset token
      user.generate_reset_token!

      # Send password reset email via worker service
      WorkerJobService.enqueue_password_reset_email(user.id)
    end

    # Always return success to prevent email enumeration
    render_success(message: "If an account with that email exists, password reset instructions have been sent.")
  rescue => e
    Rails.logger.error "Password reset error: #{e.message}"
    render_error("An error occurred. Please try again later.", status: :internal_server_error)
  end

  # POST /api/v1/passwords/reset
  def reset
    return render_error("Reset token is required", status: :bad_request) if params[:token].blank?
    return render_error("New password is required", status: :bad_request) if params[:password].blank?

    # Find user by token hash, checking all candidates
    token = params[:token]
    user = User.joins(:account).where.not(reset_token_digest: nil).find do |u|
      u.reset_token_digest.present? && BCrypt::Password.new(u.reset_token_digest) == token
    end

    unless user
      return render_error("Invalid reset token", status: :unauthorized)
    end

    if user.reset_password!(params[:password], params[:token])
      render_success(message: "Password has been reset successfully")
    else
      render_validation_error(user)
    end
  rescue => e
    Rails.logger.error "Password reset error: #{e.message}"
    render_error("An error occurred. Please try again later.", status: :internal_server_error)
  end

  # PUT /api/v1/passwords/change
  def change
    if current_user.authenticate(change_params[:current_password])
      current_user.update!(
        password: change_params[:new_password],
        password_confirmation: change_params[:password_confirmation]
      )

      render_success(message: "Password changed successfully")
    else
      render_error("Current password is incorrect", status: :unauthorized)
    end
  rescue ActiveRecord::RecordInvalid => e
    render_error("Password change failed", :unprocessable_content, details: e.record.errors.full_messages)
  end

  private

  def change_params
    params.require(:password).permit(:current_password, :new_password, :password_confirmation)
  end
end
