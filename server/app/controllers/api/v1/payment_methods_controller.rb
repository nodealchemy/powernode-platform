# frozen_string_literal: true

class Api::V1::PaymentMethodsController < ApplicationController
  before_action :set_payment_method, only: [ :update, :destroy ]

  # GET /api/v1/payment_methods
  def index
    payment_methods = current_account.payment_methods.order(:created_at)

    render json: {
      success: true,
      data: payment_methods.map { |pm| payment_method_data(pm) }
    }, status: :ok
  end

  # POST /api/v1/payment_methods
  def create
    @payment_method = current_account.payment_methods.build(payment_method_params)

    if @payment_method.save
      render json: {
        success: true,
        data: payment_method_data(@payment_method),
        message: "Payment method added successfully"
      }, status: :created
    else
      render json: {
        success: false,
        error: "Payment method creation failed",
        details: @payment_method.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # PATCH/PUT /api/v1/payment_methods/:id
  def update
    if @payment_method.update(payment_method_update_params)
      render json: {
        success: true,
        data: payment_method_data(@payment_method),
        message: "Payment method updated successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Payment method update failed",
        details: @payment_method.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # DELETE /api/v1/payment_methods/:id
  def destroy
    if @payment_method.destroy
      render json: {
        success: true,
        message: "Payment method removed successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Payment method deletion failed",
        details: @payment_method.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  private

  def set_payment_method
    @payment_method = current_account.payment_methods.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: "Payment method not found"
    }, status: :not_found
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
