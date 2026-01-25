# frozen_string_literal: true

class Api::V1::InvoicesController < ApplicationController
  before_action :set_invoice, only: [ :show, :send_invoice, :mark_paid, :void, :retry_payment, :pdf ]
  before_action -> { require_permission("billing.read") }, only: [ :index, :show, :pdf, :statistics ]
  before_action -> { require_permission("billing.manage") }, only: [ :send_invoice, :mark_paid, :void, :retry_payment ]

  # GET /api/v1/invoices
  def index
    invoices = current_account.invoices.includes(:subscription, :payments).order(created_at: :desc)

    # Pagination using Kaminari
    page = params[:page] || 1
    per_page = [ params[:per_page]&.to_i || 25, 100 ].min # Default 25, max 100

    paginated_invoices = invoices.page(page).per(per_page)

    render_success(
      data: paginated_invoices.map { |invoice| invoice_data(invoice) },
      meta: {
        pagination: {
          current_page: paginated_invoices.current_page,
          per_page: paginated_invoices.limit_value,
          total_pages: paginated_invoices.total_pages,
          total_count: paginated_invoices.total_count
        }
      }
    )
  end

  # GET /api/v1/invoices/:id
  def show
    render_success(
      data: invoice_data(@invoice, include_line_items: true)
    )
  end

  # POST /api/v1/invoices/:id/send
  def send_invoice
    if @invoice.status == "draft"
      @invoice.finalize! # Uses AASM state machine to transition from draft to open

      # Queue email delivery
      # InvoiceMailer.invoice_notification(@invoice).deliver_later

      render_success(
        message: "Invoice sent successfully",
        data: invoice_data(@invoice)
      )
    else
      render_error("Invoice has already been sent", status: :unprocessable_content)
    end
  rescue StandardError => e
    render_internal_error("Failed to send invoice", exception: e)
  end

  # POST /api/v1/invoices/:id/mark_paid
  def mark_paid
    if @invoice.status.in?(%w[open uncollectible])
      @invoice.mark_paid! # Uses AASM state machine - paid_at is set in before callback

      render_success(
        message: "Invoice marked as paid",
        data: invoice_data(@invoice)
      )
    else
      render_error("Invoice cannot be marked as paid (current status: #{@invoice.status})", status: :unprocessable_content)
    end
  rescue StandardError => e
    render_internal_error("Failed to mark invoice as paid", exception: e)
  end

  # POST /api/v1/invoices/:id/void
  def void
    if @invoice.status.in?(%w[draft open])
      @invoice.void! # Uses AASM state machine

      render_success(
        message: "Invoice voided successfully",
        data: invoice_data(@invoice)
      )
    else
      render_error("Invoice cannot be voided (current status: #{@invoice.status})", status: :unprocessable_content)
    end
  rescue StandardError => e
    render_internal_error("Failed to void invoice", exception: e)
  end

  # POST /api/v1/invoices/:id/retry_payment
  def retry_payment
    # Only open or uncollectible invoices can have payment retried
    unless @invoice.status.in?(%w[open uncollectible])
      return render_error("Invoice is not eligible for payment retry", status: :unprocessable_content)
    end

    # Queue payment retry job via worker service
    begin
      WorkerJobService.enqueue_job(
        "Billing::PaymentRetryJob",
        args: [@invoice.id],
        queue: "billing_high"
      )
      job_queued = true
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.warn "Worker service unavailable for payment retry: #{e.message}"
      job_queued = false
    end

    render_success(
      message: job_queued ? "Payment retry initiated" : "Retry recorded but worker unavailable",
      data: invoice_data(@invoice)
    )
  rescue StandardError => e
    render_internal_error("Failed to retry payment", exception: e)
  end

  # GET /api/v1/invoices/:id/pdf
  def pdf
    # Generate PDF content
    pdf_content = generate_invoice_pdf(@invoice)

    render_success(
      data: {
        invoice_id: @invoice.id,
        invoice_number: @invoice.invoice_number,
        filename: "invoice_#{@invoice.invoice_number}.pdf",
        content_type: "application/pdf",
        content: Base64.strict_encode64(pdf_content),
        generated_at: Time.current.iso8601
      }
    )
  rescue StandardError => e
    render_internal_error("Failed to generate PDF", exception: e)
  end

  # GET /api/v1/invoices/statistics
  def statistics
    invoices = current_account.invoices

    # Time range filter
    if params[:start_date].present?
      invoices = invoices.where("invoices.created_at >= ?", params[:start_date].to_date)
    end
    if params[:end_date].present?
      invoices = invoices.where("invoices.created_at <= ?", params[:end_date].to_date.end_of_day)
    end

    total_amount = invoices.sum(:total_cents)
    paid_amount = invoices.where(status: "paid").sum(:total_cents)
    pending_amount = invoices.where(status: "open").sum(:total_cents)

    render_success(
      data: {
        summary: {
          total_invoices: invoices.count,
          total_amount: total_amount,
          paid_amount: paid_amount,
          pending_amount: pending_amount,
          overdue_amount: invoices.overdue.sum(:total_cents),
          average_invoice_amount: invoices.count > 0 ? (total_amount / invoices.count).round(2) : 0
        },
        by_status: invoices.group(:status).count,
        by_status_amount: invoices.group(:status).sum(:total_cents),
        monthly_trend: invoices.group_by_month(:created_at, last: 12).sum(:total_cents),
        payment_rate: invoices.count > 0 ? (invoices.where(status: "paid").count.to_f / invoices.count * 100).round(2) : 0,
        average_days_to_payment: calculate_average_days_to_payment(invoices),
        overdue_invoices: invoices.overdue.count,
        currency_breakdown: invoices.group(:currency).sum(:total_cents)
      }
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
      subtotal: invoice.subtotal.to_f,
      tax_amount: invoice.tax_amount.to_f,
      total_amount: invoice.total.to_f,
      currency: invoice.currency,
      due_date: invoice.due_at,
      paid_at: invoice.paid_at,
      created_at: invoice.created_at,
      updated_at: invoice.updated_at,
      subscription: invoice.subscription ? {
        id: invoice.subscription.id,
        plan_name: invoice.subscription.plan&.name
      } : nil,
      payment: invoice.payments.last ? {
        id: invoice.payments.last.id,
        status: invoice.payments.last.status,
        amount: invoice.payments.last.amount_cents
      } : nil
    }

    if include_line_items
      data[:line_items] = invoice.invoice_line_items.map do |item|
        {
          id: item.id,
          description: item.description,
          quantity: item.quantity,
          unit_price: item.unit_amount_cents,
          amount: item.total_amount_cents
        }
      end
    end

    data
  end

  def generate_invoice_pdf(invoice)
    # Basic PDF generation - in production, use a proper PDF library like Prawn
    # This returns a placeholder that can be replaced with actual PDF generation
    pdf_content = <<~PDF
      %PDF-1.4
      Invoice: #{invoice.invoice_number}
      Account: #{current_account.name}
      Amount: #{invoice.currency} #{invoice.total.to_f}
      Status: #{invoice.status}
      Due Date: #{invoice.due_at}
      Generated: #{Time.current}
    PDF
    pdf_content
  end

  def calculate_average_days_to_payment(invoices)
    paid_invoices = invoices.where(status: "paid").where.not(paid_at: nil)
    return 0 if paid_invoices.empty?

    total_days = paid_invoices.sum do |invoice|
      (invoice.paid_at.to_date - invoice.created_at.to_date).to_i
    end

    (total_days.to_f / paid_invoices.count).round(1)
  end
end
