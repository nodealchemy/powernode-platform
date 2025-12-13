# frozen_string_literal: true

class Api::V1::PaymentsController < ApplicationController
  before_action :set_payment, only: [ :show ]

  # GET /api/v1/payments
  def index
    payments = current_account.payments.includes(:invoice, :subscription).order(created_at: :desc)

    # Apply pagination
    page = params[:page] || 1
    per_page = [ params[:per_page]&.to_i || 25, 100 ].min
    payments = payments.offset((page.to_i - 1) * per_page).limit(per_page)

    render_success(
      data: {
        payments: payments.map { |payment| payment_data(payment) },
        pagination: {
          page: page.to_i,
          per_page: per_page,
          total: current_account.payments.count
        }
      }
    )
  end

  # GET /api/v1/payments/:id
  def show
    render_success(
      data: payment_data(@payment)
    )
  end

  private

  def set_payment
    @payment = current_account.payments.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Payment not found", status: :not_found)
  end

  def payment_data(payment)
    {
      id: payment.id,
      amount: payment.amount,
      currency: payment.currency,
      status: payment.status,
      provider: payment.provider,
      provider_payment_id: payment.provider_payment_id,
      payment_method_last4: payment.payment_method_last4,
      processed_at: payment.processed_at,
      failed_at: payment.failed_at,
      failure_reason: payment.failure_reason,
      created_at: payment.created_at,
      updated_at: payment.updated_at,
      invoice: payment.invoice ? {
        id: payment.invoice.id,
        invoice_number: payment.invoice.invoice_number,
        total_amount: payment.invoice.total_amount
      } : nil,
      subscription: payment.subscription ? {
        id: payment.subscription.id,
        plan_name: payment.subscription.plan.name
      } : nil
    }
  end
end
