# frozen_string_literal: true

class Api::V1::PaypalController < ApplicationController
  before_action :set_paypal_service

  # POST /api/v1/paypal/payments
  def create_payment
    result = @paypal_service.create_payment_order(
      amount_cents: params[:amount_cents].to_i,
      currency: params[:currency] || "USD",
      return_url: params[:return_url],
      cancel_url: params[:cancel_url],
      description: params[:description],
      invoice_number: params[:invoice_number]
    )

    if result[:success]
      # Create local payment record
      payment = current_account.payments.create!(
        user: current_user,
        amount_cents: params[:amount_cents].to_i,
        currency: params[:currency] || "USD",
        payment_method: "paypal",
        status: "pending",
        paypal_payment_id: result[:payment_id],
        metadata: {
          description: params[:description],
          invoice_number: params[:invoice_number]
        }
      )

      render_success(
        data: {
          payment_id: payment.id,
          paypal_payment_id: result[:payment_id],
          approval_url: result[:approval_url],
          status: result[:status]
        },
        status: :created
      )
    else
      render_error(result[:error], :unprocessable_content, details: result[:details])
    end
  rescue => e
    Rails.logger.error "PayPal payment creation error: #{e.message}"
    render_error("Failed to create PayPal payment", status: :internal_server_error)
  end

  # POST /api/v1/paypal/payments/:id/execute
  def execute_payment
    payment = current_account.payments.find(params[:id])
    payer_id = params[:payer_id]

    return render_error("PayPal payer ID required", status: :bad_request) unless payer_id
    return render_error("Payment already processed", status: :bad_request) unless payment.pending?

    # Store payer_id for processing
    payment.add_metadata("payer_id", payer_id)

    # Execute payment through service
    processing_service = Billing::PaymentProcessingService.new(account: current_account, user: current_user)
    result = processing_service.process_payment(payment: payment)

    if result[:success]
      render_success(
        data: {
          payment_id: payment.id,
          status: payment.status,
          amount: payment.amount.to_s
        }
      )
    else
      render_error(result[:error], status: :unprocessable_content)
    end
  rescue => e
    Rails.logger.error "PayPal payment execution error: #{e.message}"
    render_error("Failed to execute PayPal payment", status: :internal_server_error)
  end

  # POST /api/v1/paypal/subscriptions/plans
  def create_subscription_plan
    plan = current_account.plans.find(params[:plan_id]) if params[:plan_id]

    unless plan
      return render_error("Plan not found", status: :not_found)
    end

    result = @paypal_service.create_subscription_plan(plan: plan)

    if result[:success]
      # Update plan with PayPal plan ID
      plan.update!(paypal_plan_id: result[:plan_id])

      render_success(
        data: {
          plan_id: plan.id,
          paypal_plan_id: result[:plan_id],
          status: result[:status]
        },
        status: :created
      )
    else
      render_error(result[:error], :unprocessable_content, details: result[:details])
    end
  rescue => e
    Rails.logger.error "PayPal subscription plan creation error: #{e.message}"
    render_error("Failed to create PayPal subscription plan", status: :internal_server_error)
  end

  # POST /api/v1/paypal/subscriptions
  def create_subscription
    plan = current_account.plans.find(params[:plan_id]) if params[:plan_id]

    unless plan&.paypal_plan_id
      return render_error("PayPal plan not found", status: :not_found)
    end

    result = @paypal_service.create_subscription_agreement(
      plan_id: plan.paypal_plan_id,
      name: "Subscription for #{current_account.name}",
      description: "#{plan.name} subscription",
      start_date: params[:start_date]
    )

    if result[:success]
      # Create local subscription record
      subscription = current_account.build_subscription(
        user: current_user,
        plan: plan,
        status: "pending",
        paypal_agreement_id: result[:agreement_id],
        current_period_start: Date.current,
        current_period_end: 1.send(plan.billing_cycle.singularize).from_now.to_date
      )

      if subscription.save
        render_success(
          data: {
            subscription_id: subscription.id,
            paypal_agreement_id: result[:agreement_id],
            approval_url: result[:approval_url],
            status: result[:status]
          },
          status: :created
        )
      else
        render_validation_error(subscription)
      end
    else
      render_error(result[:error], :unprocessable_content, details: result[:details])
    end
  rescue => e
    Rails.logger.error "PayPal subscription creation error: #{e.message}"
    render_error("Failed to create PayPal subscription", status: :internal_server_error)
  end

  # POST /api/v1/paypal/subscriptions/:id/execute
  def execute_subscription
    subscription = current_account.subscription

    unless subscription&.paypal_agreement_id
      return render_error("PayPal subscription not found", status: :not_found)
    end

    result = @paypal_service.execute_subscription_agreement(
      agreement_id: subscription.paypal_agreement_id
    )

    if result[:success]
      subscription.update!(
        status: result[:status] == "Active" ? "active" : result[:status].downcase,
        activated_at: Time.current
      )

      render_success(
        data: {
          subscription_id: subscription.id,
          status: subscription.status
        }
      )
    else
      render_error(result[:error], :unprocessable_content, details: result[:details])
    end
  rescue => e
    Rails.logger.error "PayPal subscription execution error: #{e.message}"
    render_error("Failed to execute PayPal subscription", status: :internal_server_error)
  end

  # DELETE /api/v1/paypal/subscriptions/:id
  def cancel_subscription
    subscription = current_account.subscription

    unless subscription&.paypal_agreement_id
      return render_error("PayPal subscription not found", status: :not_found)
    end

    result = @paypal_service.cancel_subscription(
      agreement_id: subscription.paypal_agreement_id,
      reason: params[:reason] || "Cancelled by user"
    )

    if result[:success]
      subscription.update!(
        status: "cancelled",
        canceled_at: Time.current,
        cancellation_reason: params[:reason]
      )

      render_success(
        data: {
          subscription_id: subscription.id,
          status: subscription.status
        }
      )
    else
      render_error(result[:error], :unprocessable_content, details: result[:details])
    end
  rescue => e
    Rails.logger.error "PayPal subscription cancellation error: #{e.message}"
    render_error("Failed to cancel PayPal subscription", status: :internal_server_error)
  end

  # POST /api/v1/paypal/payments/:id/refund
  def create_refund
    payment = current_account.payments.find(params[:id])

    unless payment.paypal_transaction_id
      return render_error("PayPal transaction ID not found", status: :not_found)
    end

    processing_service = Billing::PaymentProcessingService.new(account: current_account, user: current_user)
    result = processing_service.create_refund(
      payment: payment,
      amount_cents: params[:amount_cents]&.to_i,
      reason: params[:reason]
    )

    if result[:success]
      render_success(
        data: {
          payment_id: payment.id,
          refund_id: result[:refund_id],
          amount_refunded: result[:amount_refunded],
          status: payment.reload.status
        }
      )
    else
      render_error(result[:error], :unprocessable_content, details: result[:details])
    end
  rescue => e
    Rails.logger.error "PayPal refund creation error: #{e.message}"
    render_error("Failed to create PayPal refund", status: :internal_server_error)
  end

  private

  def set_paypal_service
    @paypal_service = PaypalService.new(account: current_account, user: current_user)
  end
end
