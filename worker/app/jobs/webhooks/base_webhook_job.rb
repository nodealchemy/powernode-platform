require_relative '../base_job'

# Webhooks module for webhook processing job classes
module Webhooks
  # Base class for webhook processing jobs
  class BaseWebhookJob < BaseJob
    # Common webhook processing functionality
    
    protected
    
    def validate_webhook_data(webhook_data)
      validate_required_params(webhook_data, 'event_type', 'payload')
    end
    
    def log_webhook_event(event_type, status, details = {})
      log_info("Webhook event processed", {
        event_type: event_type,
        status: status,
        details: details
      })
    end
  end
end