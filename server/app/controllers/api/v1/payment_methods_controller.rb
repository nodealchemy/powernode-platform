# frozen_string_literal: true

class Api::V1::PaymentMethodsController < ApplicationController
  before_action :set_payment_method, only: [ :update, :destroy ]

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
      created_at: payment_method.created_at,
      updated_at: payment_method.updated_at
    }
  end
end
