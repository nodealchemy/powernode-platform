# frozen_string_literal: true

class Api::V1::InvoicesController < ApplicationController
  before_action :set_invoice, only: [ :show ]

  # GET /api/v1/invoices
  def index
    invoices = current_account.invoices.includes(:subscription, :payment).order(created_at: :desc)

    # Apply pagination
    page = params[:page] || 1
    per_page = [ params[:per_page]&.to_i || 25, 100 ].min
    invoices = invoices.offset((page.to_i - 1) * per_page).limit(per_page)

    render json: {
      success: true,
      data: invoices.map { |invoice| invoice_data(invoice) },
      pagination: {
        page: page.to_i,
        per_page: per_page,
        total: current_account.invoices.count
      }
    }, status: :ok
  end

  # GET /api/v1/invoices/:id
  def show
    render json: {
      success: true,
      data: invoice_data(@invoice, include_line_items: true)
    }, status: :ok
  end

  private

  def set_invoice
    @invoice = current_account.invoices.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: "Invoice not found"
    }, status: :not_found
  end

  def invoice_data(invoice, include_line_items: false)
    data = {
      id: invoice.id,
      invoice_number: invoice.invoice_number,
      status: invoice.status,
      subtotal: invoice.subtotal,
      tax_amount: invoice.tax_amount,
      total_amount: invoice.total_amount,
      currency: invoice.currency,
      due_date: invoice.due_date,
      paid_at: invoice.paid_at,
      created_at: invoice.created_at,
      updated_at: invoice.updated_at,
      subscription: invoice.subscription ? {
        id: invoice.subscription.id,
        plan_name: invoice.subscription.plan.name
      } : nil,
      payment: invoice.payment ? {
        id: invoice.payment.id,
        status: invoice.payment.status,
        amount: invoice.payment.amount
      } : nil
    }

    if include_line_items
      data[:line_items] = invoice.line_items.map do |item|
        {
          id: item.id,
          description: item.description,
          quantity: item.quantity,
          unit_price: item.unit_price,
          amount: item.amount
        }
      end
    end

    data
  end
end
