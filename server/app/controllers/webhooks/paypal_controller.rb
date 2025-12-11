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
    event_type = @event_data["event_type"]
    event_id = @event_data["id"]
    account_id = nil
    resource_id = nil

    case event_type
    when /^BILLING\.SUBSCRIPTION\./
      resource_id = @event_data.dig("resource", "id")
      if resource_id.present?
        subscription = Subscription.find_by(paypal_subscription_id: resource_id)
        if subscription.nil?
          Rails.logger.warn(
            "PayPal webhook received for unknown subscription: " \
            "event_type=#{event_type} " \
            "event_id=#{event_id} " \
            "paypal_subscription_id=#{resource_id} " \
            "- webhook will be recorded without account association"
          )
        else
          account_id = subscription.account_id
        end
      else
        Rails.logger.debug "PayPal subscription webhook missing resource.id"
      end
    when /^PAYMENT\./
      # Extract from payment resource
      custom_id = @event_data.dig("resource", "custom_id")
      if custom_id.present?
        # Validate custom_id looks like a UUID before using it
        if custom_id.match?(/\A[0-9a-f-]{36}\z/i)
          # Verify the account exists
          account = Account.find_by(id: custom_id)
          if account.nil?
            Rails.logger.warn(
              "PayPal payment webhook references unknown account: " \
              "event_type=#{event_type} " \
              "event_id=#{event_id} " \
              "custom_id=#{custom_id} " \
              "- webhook will be recorded without account association"
            )
          else
            account_id = custom_id
          end
        else
          Rails.logger.warn(
            "PayPal payment webhook has invalid custom_id format: " \
            "event_type=#{event_type} " \
            "event_id=#{event_id} " \
            "custom_id=#{custom_id}"
          )
        end
      else
        Rails.logger.debug "PayPal payment webhook missing resource.custom_id"
      end
    else
      Rails.logger.debug "PayPal webhook event type '#{event_type}' not mapped for account extraction"
    end

    account_id
  end
end
