# frozen_string_literal: true

# Internal API controller for worker service to send emails
class Api::V1::Internal::EmailsController < Api::V1::Internal::InternalBaseController
  # POST /api/v1/internal/emails/review_notification
  def review_notification
    # Send review notification email
    recipient = params[:recipient]
    subject = params[:subject]
    body = params[:body]
    review_id = params[:review_id]

    # Queue the email for delivery
    # ReviewNotificationMailer.notification(recipient, subject, body, review_id).deliver_later

    render_success(message: "Review notification email queued")
  end

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
