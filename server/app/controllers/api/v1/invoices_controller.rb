# frozen_string_literal: true

class Api::V1::InvoicesController < ApplicationController
  before_action :set_invoice, only: [ :show, :send_invoice, :mark_paid, :void, :retry_payment, :pdf ]
  before_action -> { require_permission("billing.read") }, only: [ :index, :show, :pdf, :statistics ]
  before_action -> { require_permission("billing.manage") }, only: [ :send_invoice, :mark_paid, :void, :retry_payment ]

  # GET /api/v1/invoices
  def index
    invoices = current_account.invoices.includes(:subscription, :payment).order(created_at: :desc)

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
      @invoice.update!(status: "sent", sent_at: Time.current)

      # Queue email delivery
      # InvoiceMailer.invoice_notification(@invoice).deliver_later

      render_success(
        message: "Invoice sent successfully",
        data: invoice_data(@invoice)
      )
    else
      render_error("Invoice has already been sent", status: :unprocessable_entity)
    end
  rescue StandardError => e
    render_error("Failed to send invoice: #{e.message}", status: :internal_server_error)
  end

  # POST /api/v1/invoices/:id/mark_paid
  def mark_paid
    if @invoice.status.in?(%w[sent overdue])
      @invoice.update!(
        status: "paid",
        paid_at: params[:paid_at] || Time.current,
        payment_method: params[:payment_method] || "manual"
      )

      render_success(
        message: "Invoice marked as paid",
        data: invoice_data(@invoice)
      )
    else
      render_error("Invoice cannot be marked as paid (current status: #{@invoice.status})", status: :unprocessable_entity)
    end
  rescue StandardError => e
    render_error("Failed to mark invoice as paid: #{e.message}", status: :internal_server_error)
  end

  # POST /api/v1/invoices/:id/void
  def void
    if @invoice.status.in?(%w[draft sent overdue])
      @invoice.update!(
        status: "void",
        voided_at: Time.current,
        void_reason: params[:reason]
      )

      render_success(
        message: "Invoice voided successfully",
        data: invoice_data(@invoice)
      )
    else
      render_error("Invoice cannot be voided (current status: #{@invoice.status})", status: :unprocessable_entity)
    end
  rescue StandardError => e
    render_error("Failed to void invoice: #{e.message}", status: :internal_server_error)
  end

  # POST /api/v1/invoices/:id/retry_payment
  def retry_payment
    unless @invoice.status.in?(%w[sent overdue payment_failed])
      return render_error("Invoice is not eligible for payment retry", status: :unprocessable_entity)
    end

    # Queue payment retry job
    # PaymentRetryJob.perform_later(@invoice.id)

    @invoice.update!(
      last_payment_attempt: Time.current,
      payment_attempts: (@invoice.payment_attempts || 0) + 1
    )

    render_success(
      message: "Payment retry initiated",
      data: invoice_data(@invoice)
    )
  rescue StandardError => e
    render_error("Failed to retry payment: #{e.message}", status: :internal_server_error)
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
    render_error("Failed to generate PDF: #{e.message}", status: :internal_server_error)
  end

  # GET /api/v1/invoices/statistics
  def statistics
    invoices = current_account.invoices

    # Time range filter
    if params[:start_date].present?
      invoices = invoices.where("created_at >= ?", params[:start_date].to_date)
    end
    if params[:end_date].present?
      invoices = invoices.where("created_at <= ?", params[:end_date].to_date.end_of_day)
    end

    total_amount = invoices.sum(:total_amount)
    paid_amount = invoices.where(status: "paid").sum(:total_amount)
    pending_amount = invoices.where(status: %w[sent overdue]).sum(:total_amount)

    render_success(
      data: {
        summary: {
          total_invoices: invoices.count,
          total_amount: total_amount,
          paid_amount: paid_amount,
          pending_amount: pending_amount,
          overdue_amount: invoices.where(status: "overdue").sum(:total_amount),
          average_invoice_amount: invoices.count > 0 ? (total_amount / invoices.count).round(2) : 0
        },
        by_status: invoices.group(:status).count,
        by_status_amount: invoices.group(:status).sum(:total_amount),
        monthly_trend: invoices.group_by_month(:created_at, last: 12).sum(:total_amount),
        payment_rate: invoices.count > 0 ? (invoices.where(status: "paid").count.to_f / invoices.count * 100).round(2) : 0,
        average_days_to_payment: calculate_average_days_to_payment(invoices),
        overdue_invoices: invoices.where(status: "overdue").count,
        currency_breakdown: invoices.group(:currency).sum(:total_amount)
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

  def generate_invoice_pdf(invoice)
    # Basic PDF generation - in production, use a proper PDF library like Prawn
    # This returns a placeholder that can be replaced with actual PDF generation
    pdf_content = <<~PDF
      %PDF-1.4
      Invoice: #{invoice.invoice_number}
      Account: #{current_account.name}
      Amount: #{invoice.currency} #{invoice.total_amount}
      Status: #{invoice.status}
      Due Date: #{invoice.due_date}
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
