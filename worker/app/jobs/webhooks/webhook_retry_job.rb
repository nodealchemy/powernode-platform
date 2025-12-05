# frozen_string_literal: true

# Webhook retry job - delegates to WebhookDeliveryJob with incremented attempt
class Webhooks::WebhookRetryJob < BaseJob
  sidekiq_options queue: 'webhooks', retry: false # Don't retry the retry job itself

  def execute(delivery_id)
    log_info "Retrying webhook delivery: #{delivery_id}"

    # Increment attempt counter via API
    response = api_client.patch("/api/v1/internal/webhook_deliveries/#{delivery_id}/increment_attempt")

    unless response['success']
      log_error "Failed to increment attempt counter: #{response['error']}"
      return { success: false, error: response['error'] }
    end

    # Delegate to WebhookDeliveryJob
    Webhooks::WebhookDeliveryJob.perform_async(delivery_id)

    log_info "Webhook retry queued: #{delivery_id}"

    { success: true, delivery_id: delivery_id }
  rescue StandardError => e
    log_error "Webhook retry job failed: #{e.message}"
    { success: false, error: e.message }
  end
end
