# frozen_string_literal: true

require_relative '../base_job'
require_relative '../../mailers/notification_mailer'

# Worker half of the alert / notification email path (Pattern B, mirrors
# Chat::AttachmentScanJob). The server owns the EmailDelivery ledger and hands
# us a pending row via email_delivery_id; we render + deliver the mail over
# SMTP, then POST the outcome back to the server's internal callback so the
# ledger moves to sent / failed.
#
# Triggered by Api::V1::Internal::EmailsController#security_alert and
# #review_notification (via WorkerJobService.enqueue_alert_email).
module Notifications
  class AlertEmailJob < BaseJob
    sidekiq_options queue: 'email', retry: 3, backtrace: true

    def execute(payload)
      validate_required_params(payload, 'email_delivery_id', 'recipient', 'subject')

      delivery_id = payload['email_delivery_id']
      recipient = payload['recipient']

      log_info("Processing alert email", email_delivery_id: delivery_id, to: recipient)

      begin
        message = NotificationMailer.alert_email(
          recipient: recipient,
          subject: payload['subject'],
          heading: payload['heading'].presence || payload['subject'],
          body: payload['body'].to_s,
          details: payload['details'] || {}
        ).deliver_now

        report_delivery(delivery_id, status: 'sent', message_id: message&.message_id)
        log_info("Alert email delivered", email_delivery_id: delivery_id, to: recipient)

        { success: true, email_delivery_id: delivery_id, message_id: message&.message_id }
      rescue StandardError => e
        # Record the real failure on the ledger, then re-raise so Sidekiq
        # retries (retry: 3). We never fabricate a 'sent' — the ledger reflects
        # the genuine attempt.
        log_error("Alert email delivery failed", e,
          email_delivery_id: delivery_id, to: recipient)
        report_delivery(delivery_id, status: 'failed', error: e.message)
        raise
      end
    end

    private

    # POST the SMTP outcome back to the server's internal ledger callback.
    # Its own failure must not mask the delivery outcome, so it is rescued.
    def report_delivery(delivery_id, status:, message_id: nil, error: nil)
      api_client.post("/api/v1/internal/emails/#{delivery_id}/delivered", {
        status: status,
        message_id: message_id,
        error: error
      }.compact)
    rescue StandardError => e
      log_error("Failed to report email delivery status", e, email_delivery_id: delivery_id)
    end
  end
end
