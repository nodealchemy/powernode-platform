# frozen_string_literal: true

# External webhook controller for PayPal payment events.
# Note: Uses raw JSON responses instead of ApiResponse concern methods because
# PayPal expects specific response formats for webhook acknowledgment.
# See: https://developer.paypal.com/docs/api-basics/notifications/webhooks/
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

    # Process webhook asynchronously via worker service
    webhook_data = {
      provider: 'paypal',
      event_type: @event_data["event_type"],
      payload: @event_data,
      webhook_event_id: webhook_event.id,
      account_id: webhook_event.account_id
    }
    
    begin
      WorkerJobService.enqueue_webhook_processing(webhook_data)
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to enqueue webhook processing: #{e.message}"
      # Fallback: could implement local processing or retry logic here
    end

    render json: { received: true }, status: 200
  rescue JSON::ParserError, StandardError => e
    Rails.logger.error "PayPal webhook processing error: #{e.message}"
    render json: { error: "Webhook processing failed" }, status: 500
  end

  private

  def verify_paypal_signature
    payload = request.body.read
    @event_data = JSON.parse(payload)

    webhook_id = Rails.application.config.paypal[:webhook_id]
    
    # Use proper PayPal webhook signature verification
    verifier = PaypalWebhookVerifier.new(
      webhook_id: webhook_id,
      event_body: payload,
      headers: extract_paypal_headers
    )
    
    verification_result = verifier.verify_signature
    
    unless verification_result[:success] && verification_result[:verified]
      Rails.logger.error "PayPal webhook signature verification failed: #{verification_result[:error]}"
      raise StandardError, "PayPal webhook signature verification failed"
    end

    unless @event_data["id"] && @event_data["event_type"]
      raise StandardError, "Invalid PayPal webhook payload structure"
    end
    
    Rails.logger.info "PayPal webhook signature verified for event: #{@event_data['event_type']}"
  rescue JSON::ParserError => e
    Rails.logger.error "PayPal webhook payload parsing failed: #{e.message}"
    raise e
  end
  
  def extract_paypal_headers
    {
      'PAYPAL-AUTH-ALGO' => request.headers['PAYPAL-AUTH-ALGO'],
      'PAYPAL-CERT-ID' => request.headers['PAYPAL-CERT-ID'],
      'PAYPAL-TRANSMISSION-ID' => request.headers['PAYPAL-TRANSMISSION-ID'],
      'PAYPAL-TRANSMISSION-SIG' => request.headers['PAYPAL-TRANSMISSION-SIG'],
      'PAYPAL-TRANSMISSION-TIME' => request.headers['PAYPAL-TRANSMISSION-TIME']
    }
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
