# frozen_string_literal: true

class Webhooks::StripeController < ApplicationController
  skip_before_action :authenticate_request
  before_action :verify_stripe_signature

  def handle
    webhook_event = WebhookEvent.create!(
      provider: "stripe",
      event_type: @event.type,
      provider_event_id: @event.id,
      event_data: @event.to_json,
      account_id: extract_account_id_from_event
    )

    # Process webhook asynchronously via worker service
    webhook_data = {
      provider: 'stripe',
      event_type: @event.type,
      payload: @event.data.to_hash,
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
  rescue JSON::ParserError, Stripe::SignatureVerificationError => e
    Rails.logger.error "Stripe webhook signature verification failed: #{e.message}"
    render json: { error: "Invalid signature" }, status: 400
  rescue => e
    Rails.logger.error "Stripe webhook processing error: #{e.message}"
    render json: { error: "Webhook processing failed" }, status: 500
  end

  private

  def verify_stripe_signature
    payload = request.body.read
    signature = request.env["HTTP_STRIPE_SIGNATURE"]
    endpoint_secret = Rails.application.config.stripe[:endpoint_secret]

    @event = Stripe::Webhook.construct_event(
      payload,
      signature,
      endpoint_secret
    )
  rescue Stripe::SignatureVerificationError => e
    Rails.logger.error "Stripe signature verification failed: #{e.message}"
    raise e
  end

  def extract_account_id_from_event
    # Try to extract account ID from various event object metadata
    case @event.type
    when /^customer\./
      customer_id = @event.data.object.id
      account = Account.find_by(stripe_customer_id: customer_id)
      account&.id
    when /^invoice\./
      invoice = @event.data.object
      customer_id = invoice.customer
      account = Account.find_by(stripe_customer_id: customer_id)
      account&.id
    when /^payment_intent\./
      payment_intent = @event.data.object
      customer_id = payment_intent.customer
      account = Account.find_by(stripe_customer_id: customer_id)
      account&.id
    when /^subscription\./
      subscription = @event.data.object
      customer_id = subscription.customer
      account = Account.find_by(stripe_customer_id: customer_id)
      account&.id
    else
      nil
    end
  end
end
