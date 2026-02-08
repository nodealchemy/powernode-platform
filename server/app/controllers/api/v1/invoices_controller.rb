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
        args: [ @invoice.id ],
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
    require "prawn"
    require "prawn/table"

    pdf = Prawn::Document.new(page_size: "A4", margin: 50)

    # Header
    pdf.text "INVOICE", size: 28, style: :bold
    pdf.move_down 10
    pdf.text "Invoice ##{invoice.invoice_number}", size: 14
    pdf.text "Date: #{invoice.created_at.strftime('%B %d, %Y')}", size: 10, color: "666666"
    pdf.text "Due: #{invoice.due_at&.strftime('%B %d, %Y') || 'N/A'}", size: 10, color: "666666"
    pdf.text "Status: #{invoice.status.upcase}", size: 10, color: "666666"

    pdf.move_down 20

    # Bill To
    pdf.text "Bill To:", size: 10, style: :bold, color: "999999"
    pdf.text current_account.name, size: 12

    pdf.move_down 20

    # Subscription info
    if invoice.subscription&.plan
      pdf.text "Plan: #{invoice.subscription.plan.name}", size: 10, color: "666666"
      pdf.move_down 10
    end

    # Line items table
    line_items = invoice.invoice_line_items
    if line_items.any?
      table_data = [["Description", "Qty", "Unit Price", "Amount"]]
      line_items.each do |item|
        table_data << [
          item.description,
          item.quantity.to_s,
          format_currency_value(item.unit_amount_cents, invoice.currency),
          format_currency_value(item.total_amount_cents, invoice.currency)
        ]
      end

      pdf.table(table_data, width: pdf.bounds.width) do |t|
        t.row(0).font_style = :bold
        t.row(0).background_color = "F0F0F0"
        t.cells.padding = [8, 10]
        t.cells.border_width = 0.5
        t.cells.border_color = "DDDDDD"
        t.columns(1..3).align = :right
      end
    else
      pdf.text "No line items", color: "999999", style: :italic
    end

    pdf.move_down 20

    # Totals
    totals_data = [
      ["Subtotal", format_currency_value((invoice.subtotal.to_f * 100).to_i, invoice.currency)],
      ["Tax", format_currency_value((invoice.tax_amount.to_f * 100).to_i, invoice.currency)],
      ["Total", format_currency_value((invoice.total.to_f * 100).to_i, invoice.currency)]
    ]

    pdf.table(totals_data, position: :right, width: 200) do |t|
      t.cells.border_width = 0
      t.cells.padding = [4, 10]
      t.columns(1).align = :right
      t.row(-1).font_style = :bold
      t.row(-1).border_top_width = 1
      t.row(-1).border_color = "333333"
    end

    if invoice.paid_at
      pdf.move_down 20
      pdf.text "Paid on #{invoice.paid_at.strftime('%B %d, %Y')}", size: 10, color: "28A745", style: :bold
    end

    # Footer
    pdf.move_down 30
    pdf.text "Generated on #{Time.current.strftime('%B %d, %Y at %I:%M %p')}", size: 8, color: "999999", align: :center

    pdf.render
  end

  def format_currency_value(cents, currency = "USD")
    symbol = currency == "USD" ? "$" : currency
    "#{symbol}#{'%.2f' % (cents.to_f / 100)}"
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
