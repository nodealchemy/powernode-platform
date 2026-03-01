# frozen_string_literal: true

class Api::V1::Auth::EmailVerificationsController < ApplicationController
  # Rate limiting is now included in ApplicationController

  skip_before_action :authenticate_request, only: [ :verify ]
  before_action :authenticate_request, only: [ :resend ]

  # POST /api/v1/auth/verify-email
  def verify
    token = params[:token]

    if token.blank?
      render_error("Verification token is required", status: :bad_request)
      return
    end

    user = User.find_by(email_verification_token: token)

    if user.nil?
      render_error("Invalid verification token", status: :not_found)
      return
    end

    if user.email_verification_expired?
      render_error("Verification token has expired. Please request a new one.", status: :unprocessable_content)
      return
    end

    if user.verified?
      render_success({ message: "Email is already verified" })
      return
    end

    # Verify the email
    user.transaction do
      user.update!(
        email_verified_at: Time.current,
        email_verification_token: nil,
        email_verification_sent_at: nil,
        email_verification_token_expires_at: nil
      )

      # Create audit log entry
      AuditLog.create!(
        user: user,
        account: user.account,
        action: "email_verified",
        resource_type: "User",
        resource_id: user.id,
        source: "api",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          verification_method: "email_token",
          email: user.email
        }
      )
    end

    render_success({
      message: "Email verified successfully",
      user: {
        id: user.id,
        email: user.email,
        email_verified: user.verified?
      }
    })
  rescue StandardError => e
    Rails.logger.error "Email verification failed: #{e.message}"
    render_error("Verification failed. Please try again.", status: :internal_server_error)
  end

  # POST /api/v1/auth/resend-verification
  def resend
    unless current_user
      render_error("Authentication required", status: :unauthorized)
      return
    end

    if current_user.verified?
      render_error("Email is already verified", status: :unprocessable_content)
      return
    end

    # Check if user recently requested verification
    if current_user.email_verification_sent_at &&
       current_user.email_verification_sent_at > 5.minutes.ago
      time_remaining = (5.minutes - (Time.current - current_user.email_verification_sent_at)).to_i
      render_error(
        "Please wait #{time_remaining} seconds before requesting another verification email",
        :too_many_requests,
        details: { retry_after: time_remaining }
      )
      return
    end

    # Generate new verification token
    current_user.generate_email_verification_token

    # Send verification email via worker service using system settings
    begin
      WorkerJobService.enqueue_notification_email(
        "email_verification",
        {
          user_id: current_user.id,
          email: current_user.email,
          verification_token: current_user.email_verification_token,
          user_name: current_user.full_name,
          smtp_settings: Rails.application.credentials.dig(:mail, :smtp)
        }
      )

      render_success({ message: "Verification email sent successfully" })
    rescue StandardError => e
      Rails.logger.error "Failed to send verification email: #{e.message}"
      render_error("Failed to send verification email. Please try again later.", status: :internal_server_error)
    end
  end

  private

  def should_rate_limit?
    action_name == "resend"
  end
end
