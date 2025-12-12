# frozen_string_literal: true

class Api::V1::InvoicesController < ApplicationController
  before_action :set_invoice, only: [ :show ]

  # GET /api/v1/invoices
  def index
    invoices = current_account.invoices.includes(:subscription, :payment).order(created_at: :desc)

    # Pagination using Kaminari
    page = params[:page] || 1
    per_page = [ params[:per_page]&.to_i || 25, 100 ].min # Default 25, max 100

    paginated_invoices = invoices.page(page).per(per_page)

    render_success(
      data: paginated_invoices.map { |invoice| invoice_data(invoice) },
      pagination: {
        current_page: paginated_invoices.current_page,
        per_page: paginated_invoices.limit_value,
        total_pages: paginated_invoices.total_pages,
        total_count: paginated_invoices.total_count
      }
    )
  end

  # GET /api/v1/invoices/:id
  def show
    render_success(
      data: invoice_data(@invoice, include_line_items: true)
    )
  end

  private

  def set_invoice
    @invoice = current_account.invoices.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Invoice not found", status: :not_found)
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
