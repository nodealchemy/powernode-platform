# frozen_string_literal: true

module Marketing
  class EmailBatchSendJob < BaseJob
    sidekiq_options queue: "marketing_email", retry: 5

    BATCH_SIZE = 100

    protected

    def execute(campaign_id, batch_number, recipient_ids)
      log_info("Processing email batch",
               campaign_id: campaign_id,
               batch: batch_number,
               recipients: recipient_ids.size)

      sent = 0
      failed = 0

      recipient_ids.each do |recipient_id|
        send_email(campaign_id, recipient_id)
        sent += 1
      rescue StandardError => e
        failed += 1
        log_error("Failed to send email",
                  e,
                  campaign_id: campaign_id,
                  recipient_id: recipient_id)
      end

      # Report batch results back to server
      with_api_retry do
        api_client.post("/api/v1/internal/marketing/batch_result", {
          campaign_id: campaign_id,
          batch_number: batch_number,
          sent: sent,
          failed: failed
        })
      end

      log_info("Email batch completed",
               campaign_id: campaign_id,
               batch: batch_number,
               sent: sent,
               failed: failed)
    end

    private

    def send_email(campaign_id, recipient_id)
      # Email sending stub - would integrate with email provider (SendGrid, SES, etc.)
      log_info("Sending email", campaign_id: campaign_id, recipient_id: recipient_id)
    end
  end
end
