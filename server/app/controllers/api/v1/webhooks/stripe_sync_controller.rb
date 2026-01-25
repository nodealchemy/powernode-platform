# frozen_string_literal: true

class Api::V1::Webhooks::StripeSyncController < ApplicationController
  before_action :authenticate_service_request

  # Handle invoice payment success
  def invoice_paid
    invoice = find_invoice_by_stripe_id(params[:stripe_invoice_id])
    return render_not_found("Invoice not found") unless invoice

    ActiveRecord::Base.transaction do
      # Create payment record
      payment = invoice.payments.build(
        amount_cents: params[:amount_paid],
        currency: invoice.currency,
        payment_method: "stripe_card",
        status: "succeeded",
        processed_at: Time.current,
        metadata: {
          stripe_payment_intent_id: params[:payment_intent_id],
          webhook_processed_at: Time.current.iso8601
        }.merge(params[:metadata] || {})
      )

      payment.save!

      # Update invoice status
      invoice.mark_paid! if invoice.may_mark_paid?

      # Update subscription if needed
      if invoice.subscription.may_activate?
        invoice.subscription.activate!
      end

      log_webhook_processing("stripe_invoice_paid", invoice.account, {
        invoice_id: invoice.id,
        payment_id: payment.id,
        amount: params[:amount_paid]
      })
    end

    render_success(message: "Invoice payment processed")
  rescue StandardError => e
    Rails.logger.error "Stripe invoice payment processing failed: #{e.message}"
    render_error(e.message, status: :internal_server_error)
  end

  # Handle invoice payment failure
  def invoice_failed
    invoice = find_invoice_by_stripe_id(params[:stripe_invoice_id])
    return render_not_found("Invoice not found") unless invoice

    ActiveRecord::Base.transaction do
      # Update invoice status
      invoice.update!(
        metadata: (invoice.metadata || {}).merge(
          last_payment_failure: {
            code: params[:failure_code],
            message: params[:failure_message],
            failed_at: Time.current.iso8601
          }
        )
      )

      # Update subscription status
      if invoice.subscription && params[:subscription_id]
        subscription = invoice.subscription

        if subscription.may_mark_past_due?
          subscription.mark_past_due!

          # Add dunning metadata
          subscription.update!(
            metadata: (subscription.metadata || {}).merge(
              dunning_level: "payment_failure",
              last_failure_at: Time.current.iso8601,
              failure_count: (subscription.metadata["failure_count"] || 0) + 1
            )
          )
        end
      end

      log_webhook_processing("stripe_invoice_failed", invoice.account, {
        invoice_id: invoice.id,
        failure_code: params[:failure_code],
        failure_message: params[:failure_message]
      })
    end

    render_success(message: "Invoice payment failure processed")
  rescue StandardError => e
    Rails.logger.error "Stripe invoice failure processing failed: #{e.message}"
    render_error(e.message, status: :internal_server_error)
  end

  # Handle subscription updates from Stripe
  def subscription_updated
    subscription = find_subscription_by_stripe_id(params[:stripe_subscription_id])
    return render_not_found("Subscription not found") unless subscription

    ActiveRecord::Base.transaction do
      # Map Stripe status to local status
      local_status = map_stripe_subscription_status(params[:status])

      subscription.update!(
        status: local_status,
        current_period_start: params[:current_period_start],
        current_period_end: params[:current_period_end],
        trial_end: params[:trial_end],
        canceled_at: params[:canceled_at],
        metadata: (subscription.metadata || {}).merge(
          cancel_at_period_end: params[:cancel_at_period_end],
          stripe_sync_at: Time.current.iso8601,
          stripe_webhook_data: params[:metadata]
        )
      )

      log_webhook_processing("stripe_subscription_updated", subscription.account, {
        subscription_id: subscription.id,
        old_status: subscription.status_was,
        new_status: local_status
      })
    end

    render_success(message: "Subscription synchronized")
  rescue StandardError => e
    Rails.logger.error "Stripe subscription update failed: #{e.message}"
    render_error(e.message, status: :internal_server_error)
  end

  # Handle subscription cancellation
  def subscription_canceled
    subscription = find_subscription_by_stripe_id(params[:stripe_subscription_id])
    return render_not_found("Subscription not found") unless subscription

    ActiveRecord::Base.transaction do
      if subscription.may_cancel?
        subscription.cancel!

        subscription.update!(
          canceled_at: params[:canceled_at],
          ended_at: params[:canceled_at],
          metadata: (subscription.metadata || {}).merge(
            cancellation_reason: params[:cancellation_reason],
            canceled_via: "stripe_webhook"
          )
        )
      end

      log_webhook_processing("stripe_subscription_canceled", subscription.account, {
        subscription_id: subscription.id,
        canceled_at: params[:canceled_at]
      })
    end

    render_success(message: "Subscription cancellation processed")
  rescue StandardError => e
    Rails.logger.error "Stripe subscription cancellation failed: #{e.message}"
    render_error(e.message, status: :internal_server_error)
  end

  # Handle successful payments
  def payment_succeeded
    payment = find_payment_by_stripe_intent(params[:payment_intent_id])

    if payment
      update_existing_payment_success(payment, params)
    else
      create_standalone_payment_success(params)
    end

    render_success(message: "Payment success processed")
  rescue StandardError => e
    Rails.logger.error "Stripe payment success processing failed: #{e.message}"
    render_error(e.message, status: :internal_server_error)
  end

  # Handle failed payments
  def payment_failed
    payment = find_payment_by_stripe_intent(params[:payment_intent_id])

    if payment
      update_existing_payment_failure(payment, params)
    else
      log_standalone_payment_failure(params)
    end

    render_success(message: "Payment failure processed")
  rescue StandardError => e
    Rails.logger.error "Stripe payment failure processing failed: #{e.message}"
    render_error(e.message, status: :internal_server_error)
  end

  # Handle successful setup intents
  def setup_intent_succeeded
    account = Account.find(params[:account_id])

    # Log successful setup for payment method attachment
    log_webhook_processing("stripe_setup_intent_succeeded", account, {
      setup_intent_id: params[:setup_intent_id],
      payment_method: params[:payment_method]
    })

    render_success(message: "Setup intent success processed")
  end

  # Handle payment method attachment
  def payment_method_attached
    account = Account.find(params[:account_id])

    # Update local payment method record if exists
    payment_method = account.payment_methods.find_by(
      provider_payment_method_id: params[:payment_method_id]
    )

    if payment_method
      payment_method.update!(
        metadata: (payment_method.metadata || {}).merge(
          stripe_attached_at: Time.current.iso8601,
          stripe_data: params[:metadata]
        )
      )
    end

    log_webhook_processing("stripe_payment_method_attached", account, {
      payment_method_id: params[:payment_method_id],
      customer: params[:customer]
    })

    render_success(message: "Payment method attachment processed")
  end

  # Handle payment method detachment
  def payment_method_detached
    account = Account.find(params[:account_id])

    # Update or deactivate local payment method
    payment_method = account.payment_methods.find_by(
      provider_payment_method_id: params[:payment_method_id]
    )

    if payment_method
      payment_method.deactivate!
    end

    log_webhook_processing("stripe_payment_method_detached", account, {
      payment_method_id: params[:payment_method_id]
    })

    render_success(message: "Payment method detachment processed")
  end

  # Handle unhandled events
  def unhandled_event
    account = Account.find(params[:account_id]) if params[:account_id]

    log_webhook_processing("stripe_unhandled_event", account, {
      event_type: params[:event_type],
      payload_summary: params[:payload_summary]
    })

    render_success(message: "Unhandled event logged")
  end

  # Activate subscription after successful payment
  def activate_subscription
    subscription = find_subscription_by_stripe_id(params[:stripe_subscription_id])
    return render_not_found("Subscription not found") unless subscription

    if subscription.may_activate?
      subscription.activate!

      log_webhook_processing("stripe_subscription_activated", subscription.account, {
        subscription_id: subscription.id
      })
    end

    render_success(message: "Subscription activation processed")
  end

  private

  def find_invoice_by_stripe_id(stripe_invoice_id)
    Invoice.joins(:subscription)
           .where(stripe_invoice_id: stripe_invoice_id)
           .includes(:subscription, :account)
           .first
  end

  def find_subscription_by_stripe_id(stripe_subscription_id)
    Subscription.joins(:account)
                .where(stripe_subscription_id: stripe_subscription_id)
                .includes(:account)
                .first
  end

  def find_payment_by_stripe_intent(payment_intent_id)
    Payment.joins(invoice: :subscription)
           .where("payments.metadata->>'stripe_payment_intent_id' = ?", payment_intent_id)
           .includes(invoice: [ :subscription, :account ])
           .first
  end

  def map_stripe_subscription_status(stripe_status)
    case stripe_status
    when "active" then "active"
    when "trialing" then "trialing"
    when "past_due" then "past_due"
    when "canceled" then "canceled"
    when "unpaid" then "unpaid"
    when "incomplete" then "incomplete"
    when "incomplete_expired" then "incomplete_expired"
    when "paused" then "paused"
    else "active" # Default fallback
    end
  end

  def update_existing_payment_success(payment, params)
    payment.update!(
      status: "succeeded",
      processed_at: Time.current,
      metadata: (payment.metadata || {}).merge(
        stripe_charges: params[:charges],
        webhook_processed_at: Time.current.iso8601
      )
    )
  end

  def create_standalone_payment_success(params)
    # Log standalone payment success for tracking
    Rails.logger.info "Standalone Stripe payment succeeded: #{params[:payment_intent_id]}"
  end

  def update_existing_payment_failure(payment, params)
    payment.update!(
      status: "failed",
      failed_at: Time.current,
      error_message: params[:failure_message],
      metadata: (payment.metadata || {}).merge(
        failure_code: params[:failure_code],
        failure_message: params[:failure_message],
        webhook_processed_at: Time.current.iso8601
      )
    )
  end

  def log_standalone_payment_failure(params)
    Rails.logger.error "Standalone Stripe payment failed: #{params[:payment_intent_id]} - #{params[:failure_message]}"
  end

  def log_webhook_processing(event_type, account, data)
    AuditLog.log_action(
      action: "webhook_processed",
      resource_type: "WebhookEvent",
      account: account,
      new_values: data,
      source: "stripe_webhook",
      metadata: {
        event_type: event_type,
        processed_at: Time.current.iso8601
      }
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log webhook processing: #{e.message}"
  end

  def render_not_found(message)
    render_error(message, status: :internal_server_error)
  end

  def authenticate_service_request
    # Implement service-to-service authentication
    # This should verify that the request is coming from the worker service
    service_token = request.headers["X-Service-Token"]
    expected_token = Rails.application.credentials.dig(:worker_service, :api_token)

    unless service_token == expected_token
      render_error("Unauthorized service request", status: :unauthorized)
    end
  end
end
