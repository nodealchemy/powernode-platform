# frozen_string_literal: true

class Api::V1::PaymentMethodsController < ApplicationController
  before_action :set_payment_method, only: [ :show, :update, :destroy, :set_default, :confirm ]
  before_action -> { require_permission("billing.read") }, only: [ :index, :show ]
  before_action -> { require_permission("billing.manage") }, only: [ :create, :update, :destroy, :setup_intent, :confirm, :set_default ]

  # GET /api/v1/payment_methods
  def index
    payment_methods = current_account.payment_methods.order(:created_at)

    render_success(
      data: payment_methods.map { |pm| payment_method_data(pm) }
    )
  end

  # POST /api/v1/payment_methods
  def create
    @payment_method = current_account.payment_methods.build(payment_method_params)

    if @payment_method.save
      render_success(
        message: "Payment method added successfully",
        data: payment_method_data(@payment_method),
        status: :created
      )
    else
      render_validation_error(@payment_method)
    end
  end

  # PATCH/PUT /api/v1/payment_methods/:id
  def update
    if @payment_method.update(payment_method_update_params)
      render_success(
        message: "Payment method updated successfully",
        data: payment_method_data(@payment_method)
      )
    else
      render_validation_error(@payment_method)
    end
  end

  # DELETE /api/v1/payment_methods/:id
  def destroy
    if @payment_method.destroy
      render_success(
        message: "Payment method removed successfully"
      )
    else
      render_validation_error(@payment_method)
    end
  end

  # GET /api/v1/payment_methods/:id
  def show
    render_success(
      data: payment_method_data(@payment_method)
    )
  end

  # POST /api/v1/payment_methods/setup_intent
  def setup_intent
    # Create a Stripe SetupIntent for adding a new payment method
    provider = params[:provider] || "stripe"

    case provider.downcase
    when "stripe"
      setup_intent_data = create_stripe_setup_intent
    when "paypal"
      setup_intent_data = create_paypal_setup_token
    else
      return render_error("Unsupported payment provider: #{provider}", status: :unprocessable_content)
    end

    render_success(
      data: setup_intent_data,
      message: "Setup intent created successfully"
    )
  rescue StandardError => e
    Rails.logger.error "Failed to create setup intent: #{e.message}"
    render_error("Failed to create setup intent: #{e.message}", status: :internal_server_error)
  end

  # POST /api/v1/payment_methods/:id/confirm
  def confirm
    # Confirm a payment method setup (after client-side confirmation)
    unless params[:setup_intent_id].present? || params[:confirmation_token].present?
      return render_error("Missing setup_intent_id or confirmation_token", status: :unprocessable_content)
    end

    # Update payment method with confirmed details
    @payment_method.update!(
      status: "confirmed",
      confirmed_at: Time.current,
      provider_setup_intent_id: params[:setup_intent_id]
    )

    render_success(
      message: "Payment method confirmed successfully",
      data: payment_method_data(@payment_method)
    )
  rescue StandardError => e
    Rails.logger.error "Failed to confirm payment method: #{e.message}"
    render_error("Failed to confirm payment method: #{e.message}", status: :internal_server_error)
  end

  # POST /api/v1/payment_methods/:id/set_default
  def set_default
    # Remove default from all other payment methods
    current_account.payment_methods.where.not(id: @payment_method.id).update_all(is_default: false)

    # Set this one as default
    @payment_method.update!(is_default: true)

    render_success(
      message: "Payment method set as default",
      data: payment_method_data(@payment_method)
    )
  rescue StandardError => e
    Rails.logger.error "Failed to set default payment method: #{e.message}"
    render_error("Failed to set default payment method: #{e.message}", status: :internal_server_error)
  end

  private

  def set_payment_method
    @payment_method = current_account.payment_methods.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Payment method not found", status: :not_found)
  end

  def payment_method_params
    params.require(:payment_method).permit(:provider, :provider_payment_method_id, :card_last4, :card_brand, :card_expires_month, :card_expires_year, :is_default)
  end

  def payment_method_update_params
    params.require(:payment_method).permit(:is_default)
  end

  def payment_method_data(payment_method)
    {
      id: payment_method.id,
      provider: payment_method.provider,
      card_last4: payment_method.card_last4,
      card_brand: payment_method.card_brand,
      card_expires_month: payment_method.card_expires_month,
      card_expires_year: payment_method.card_expires_year,
      is_default: payment_method.is_default,
      status: payment_method.try(:status) || "active",
      created_at: payment_method.created_at,
      updated_at: payment_method.updated_at
    }
  end

  def create_stripe_setup_intent
    # Get or create Stripe customer
    stripe_customer_id = current_account.stripe_customer_id

    if stripe_customer_id.blank?
      # Create new Stripe customer
      customer = Stripe::Customer.create(
        email: current_user.email,
        name: current_account.name,
        metadata: {
          account_id: current_account.id,
          platform: "powernode"
        }
      )
      current_account.update!(stripe_customer_id: customer.id)
      stripe_customer_id = customer.id
    end

    # Create SetupIntent
    setup_intent = Stripe::SetupIntent.create(
      customer: stripe_customer_id,
      payment_method_types: [ "card" ],
      metadata: {
        account_id: current_account.id
      }
    )

    {
      provider: "stripe",
      setup_intent_id: setup_intent.id,
      client_secret: setup_intent.client_secret,
      customer_id: stripe_customer_id,
      publishable_key: Rails.application.credentials.dig(:stripe, :publishable_key)
    }
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe SetupIntent creation failed: #{e.message}"
    raise StandardError, "Stripe error: #{e.message}"
  rescue NoMethodError
    # Stripe gem not configured - return mock for development
    {
      provider: "stripe",
      setup_intent_id: "seti_mock_#{SecureRandom.hex(12)}",
      client_secret: "seti_mock_secret_#{SecureRandom.hex(24)}",
      customer_id: "cus_mock_#{SecureRandom.hex(8)}",
      publishable_key: "pk_test_mock"
    }
  end

  def create_paypal_setup_token
    # PayPal setup token creation
    # In production, this would use the PayPal API
    {
      provider: "paypal",
      setup_token: "paypal_setup_#{SecureRandom.hex(16)}",
      approval_url: "https://www.paypal.com/checkoutnow?token=mock_token",
      client_id: Rails.application.credentials.dig(:paypal, :client_id) || "paypal_client_mock"
    }
  end
end
