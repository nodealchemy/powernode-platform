class Webhooks::PaypalController < ApplicationController
  skip_before_action :authenticate_request
  before_action :verify_paypal_signature

  def handle
    webhook_event = WebhookEvent.create!(
      provider: "paypal",
      event_type: @event_data["event_type"],
      provider_event_id: @event_data["id"],
      event_data: @event_data.to_json,
      account_id: extract_account_id_from_event
    )

    # Process webhook asynchronously
    ProcessWebhookEventJob.perform_later(webhook_event.id)

    render json: { received: true }, status: 200
  rescue JSON::ParserError, StandardError => e
    Rails.logger.error "PayPal webhook processing error: #{e.message}"
    render json: { error: "Webhook processing failed" }, status: 500
  end

  private

  def verify_paypal_signature
    payload = request.body.read
    @event_data = JSON.parse(payload)

    # PayPal webhook signature verification would go here
    # This is a simplified version - in production you'd verify the signature
    # using PayPal's webhook signature verification process

    webhook_id = Rails.application.config.paypal[:webhook_id]
    # In a real implementation, you would verify the signature here
    # For now, we'll just parse and validate the basic structure

    unless @event_data["id"] && @event_data["event_type"]
      raise StandardError, "Invalid PayPal webhook payload"
    end
  rescue JSON::ParserError => e
    Rails.logger.error "PayPal webhook payload parsing failed: #{e.message}"
    raise e
  end

  def extract_account_id_from_event
    # Try to extract account ID from PayPal event
    case @event_data["event_type"]
    when /^BILLING\.SUBSCRIPTION\./
      subscription_id = @event_data.dig("resource", "id")
      subscription = Subscription.find_by(paypal_subscription_id: subscription_id)
      subscription&.account_id
    when /^PAYMENT\./
      # Extract from payment resource
      custom_id = @event_data.dig("resource", "custom_id")
      # Assuming custom_id contains account_id
      custom_id
    else
      nil
    end
  end
end
