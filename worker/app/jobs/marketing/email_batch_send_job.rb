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

      # Report batch results back to server. Idempotency: the per-recipient sends above already
      # completed (each is individually guarded, so the loop never aborts). This report is
      # telemetry only — its failure must NOT raise, or the whole job retries (retry: 5) and
      # re-sends every email in the batch (up to 5×). Record-and-swallow instead.
      report_batch_result(campaign_id, batch_number, sent, failed)

      log_info("Email batch completed",
               campaign_id: campaign_id,
               batch: batch_number,
               sent: sent,
               failed: failed)
    end

    private

    def report_batch_result(campaign_id, batch_number, sent, failed)
      with_api_retry do
        api_client.post("/api/v1/internal/marketing/batch_result", {
          campaign_id: campaign_id,
          batch_number: batch_number,
          sent: sent,
          failed: failed
        })
      end
    rescue StandardError => e
      log_error("Failed to report email batch result (emails already sent; not retrying to avoid re-send)",
                e, campaign_id: campaign_id, batch_number: batch_number, sent: sent, failed: failed)
    end

    def send_email(campaign_id, recipient_id)
      api_client.post('/api/v1/internal/notifications/send', {
        template: 'marketing_campaign', user_id: recipient_id,
        data: { campaign_id: campaign_id }
      })
    end
  end
end
