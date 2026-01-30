# frozen_string_literal: true

class Api::V1::ReconciliationController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_request

  # Get Stripe payments for reconciliation
  def stripe_payments
    start_date = Time.parse(params[:start_date])
    end_date = Time.parse(params[:end_date])

    payments = Payment.joins(invoice: :subscription)
                     .joins(:payment_method)
                     .where(payment_methods: { gateway: "stripe" })
                     .where(created_at: start_date..end_date)
                     .where(status: "succeeded")
                     .includes(invoice: [ :subscription, :account ])

    payments_data = payments.map do |payment|
      {
        id: payment.id,
        amount_cents: payment.amount_cents,
        currency: payment.currency,
        created_at: payment.created_at,
        status: payment.status,
        metadata: payment.metadata,
        account_id: payment.account.id,
        invoice_id: payment.invoice.id
      }
    end

    render_success(payments_data)
  end

  # Get PayPal payments for reconciliation
  def paypal_payments
    start_date = Time.parse(params[:start_date])
    end_date = Time.parse(params[:end_date])

    payments = Payment.joins(invoice: :subscription)
                     .joins(:payment_method)
                     .where(payment_methods: { gateway: "paypal" })
                     .where(created_at: start_date..end_date)
                     .where(status: "succeeded")
                     .includes(invoice: [ :subscription, :account ])

    payments_data = payments.map do |payment|
      {
        id: payment.id,
        amount_cents: payment.amount_cents,
        currency: payment.currency,
        created_at: payment.created_at,
        status: payment.status,
        metadata: payment.metadata,
        account_id: payment.account.id,
        invoice_id: payment.invoice.id
      }
    end

    render_success(payments_data)
  end

  # Receive reconciliation reports
  def report
    reconciliation_report = ReconciliationReport.create!(
      reconciliation_date: Date.parse(params[:reconciliation_date]),
      reconciliation_type: params[:reconciliation_type],
      gateway: params[:gateway],
      report_date: Date.parse(params[:report_date]),
      report_type: params[:report_type],
      date_range_start: Time.parse(params[:date_range][:start]),
      date_range_end: Time.parse(params[:date_range][:end]),
      summary: params[:summary].to_json,
      discrepancies_count: params[:discrepancies_count],
      high_severity_count: params[:high_severity_count],
      medium_severity_count: params[:medium_severity_count]
    )

    render_success({ report_id: reconciliation_report.id })
  end

  # Handle reconciliation corrections
  def corrections
    correction_type = params[:type]

    case correction_type
    when "create_missing_payment"
      handle_create_missing_payment(params)
    else
      render_error("Unknown correction type: #{correction_type}", status: :bad_request)
    end
  end

  # Handle reconciliation flags for manual review
  def flags
    reconciliation_flag = ReconciliationFlag.create!(
      reconciliation_report_id: params[:reconciliation_report_id],
      flag_type: params[:type],
      description: params[:description] || "#{params[:type]} detected",
      severity: params[:severity] || "medium",
      transaction_id: params[:transaction_id],
      amount_cents: params[:amount_cents],
      metadata: params[:metadata] || {}
    )

    render_success({ flag_id: reconciliation_flag.id })
  end

  # Handle reconciliation investigations
  def investigations
    reconciliation_investigation = ReconciliationInvestigation.create!(
      reconciliation_flag_id: params[:reconciliation_flag_id],
      investigator_id: params[:investigator_id],
      started_at: params[:started_at] || Time.current,
      notes: params[:notes],
      findings: params[:findings] || {}
    )

    render_success({ investigation_id: reconciliation_investigation.id })
  end

  private

  def handle_create_missing_payment(params)
    provider_payment_id = params[:provider_payment_id]
    provider = params[:provider]

    # Try to find the account via existing payment with same provider ID
    account = find_account_for_missing_payment(provider, provider_payment_id, params[:account_id])

    unless account
      return render_error(
        "Cannot determine account for missing payment. Provide account_id or ensure a related payment exists.",
        status: :unprocessable_entity
      )
    end

    # Log the missing payment for manual review
    missing_payment_log = MissingPaymentLog.create!(
      account: account,
      gateway: provider,
      external_payment_id: provider_payment_id,
      amount_cents: params[:amount],
      currency: params[:currency],
      status: "pending",
      detected_at: Time.current
    )

    render_success(
      message: "Missing payment logged for manual review",
      data: { log_id: missing_payment_log.id }
    )
  end

  def find_account_for_missing_payment(provider, provider_payment_id, explicit_account_id)
    # First, try explicit account_id if provided
    if explicit_account_id.present?
      return Account.find_by(id: explicit_account_id)
    end

    # Try to find account via existing payment with same provider ID
    existing_payment = Payment.find_by_provider_payment_id(provider, provider_payment_id)
    return existing_payment.account if existing_payment

    # Try to find account via subscription ID in metadata if this is a recurring payment
    # PayPal and Stripe often include subscription references
    nil
  end

  def authenticate_service_request
    service_token = request.headers["X-Service-Token"]
    expected_token = Rails.application.credentials.dig(:worker_service, :api_token)

    unless service_token == expected_token
      render_error("Unauthorized service request", status: :unauthorized)
    end
  end
end
