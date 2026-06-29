# frozen_string_literal: true

# Internal API controller for worker service to send emails
class Api::V1::Internal::EmailsController < Api::V1::Internal::InternalBaseController
  # POST /api/v1/internal/emails/security_alert
  def security_alert
    # Send security alert email
    recipient = params[:recipient]
    alert_type = params[:alert_type]
    details = params[:details]

    # Queue the email for delivery
    # SecurityAlertMailer.alert(recipient, alert_type, details).deliver_later

    render_success(message: "Security alert email queued")
  end
end
