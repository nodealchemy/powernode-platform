class Api::V1::ReconciliationController < ApplicationController
  before_action :authenticate_service_request
  
  # Get Stripe payments for reconciliation
  def stripe_payments
    start_date = Time.parse(params[:start_date])
    end_date = Time.parse(params[:end_date])
    
    payments = Payment.joins(invoice: :subscription)
                     .where(payment_method: ['stripe_card', 'stripe_bank'])
                     .where(created_at: start_date..end_date)
                     .where(status: 'succeeded')
                     .includes(invoice: [:subscription, :account])
    
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
    
    render json: payments_data
  end
  
  # Get PayPal payments for reconciliation
  def paypal_payments
    start_date = Time.parse(params[:start_date])
    end_date = Time.parse(params[:end_date])
    
    payments = Payment.joins(invoice: :subscription)
                     .where(payment_method: 'paypal')
                     .where(created_at: start_date..end_date)
                     .where(status: 'succeeded')
                     .includes(invoice: [:subscription, :account])
    
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
    
    render json: payments_data
  end
  
  # Receive reconciliation reports
  def report
    reconciliation_report = ReconciliationReport.create!(
      reconciliation_date: Date.parse(params[:reconciliation_date]),
      reconciliation_type: params[:reconciliation_type],
      date_range_start: Time.parse(params[:date_range][:start]),
      date_range_end: Time.parse(params[:date_range][:end]),
      summary: params[:summary],
      discrepancies_count: params[:discrepancies_count],
      high_severity_count: params[:high_severity_count],
      medium_severity_count: params[:medium_severity_count]
    )
    
    # Log the reconciliation report
    AuditLog.log_action(
      action: 'reconciliation_report_created',
      resource: reconciliation_report,
      source: 'worker_service',
      metadata: {
        reconciliation_type: params[:reconciliation_type],
        discrepancies_found: params[:discrepancies_count]
      }
    )
    
    render json: { success: true, report_id: reconciliation_report.id }
  end
  
  # Handle reconciliation corrections
  def corrections
    correction_type = params[:type]
    
    case correction_type
    when 'create_missing_payment'
      handle_create_missing_payment(params)
    else
      render json: { success: false, error: "Unknown correction type: #{correction_type}" }
    end
  end
  
  # Handle reconciliation flags for manual review
  def flags
    reconciliation_flag = ReconciliationFlag.create!(
      flag_type: params[:type],
      provider: params[:provider],
      local_payment_id: params[:local_payment_id],
      external_id: params[:external_id],
      requires_manual_review: params[:requires_manual_review],
      metadata: params.except(:type, :provider, :local_payment_id, :external_id, :requires_manual_review),
      status: 'pending'
    )
    
    render json: { success: true, flag_id: reconciliation_flag.id }
  end
  
  # Handle reconciliation investigations
  def investigations
    reconciliation_investigation = ReconciliationInvestigation.create!(
      investigation_type: params[:type],
      local_payment_id: params[:local_payment_id],
      provider_payment_id: params[:provider_payment_id],
      local_amount: params[:local_amount],
      provider_amount: params[:provider_amount],
      amount_difference: params[:difference],
      requires_investigation: params[:requires_investigation],
      status: 'pending'
    )
    
    render json: { success: true, investigation_id: reconciliation_investigation.id }
  end
  
  private
  
  def handle_create_missing_payment(params)
    # Find the associated invoice/account for this payment
    # This would require looking up by provider payment ID
    provider_payment_id = params[:provider_payment_id]
    provider = params[:provider]
    
    # For now, log the missing payment for manual review
    missing_payment_log = MissingPaymentLog.create!(
      provider: provider,
      provider_payment_id: provider_payment_id,
      amount_cents: params[:amount],
      currency: params[:currency],
      status: 'pending_creation',
      discovered_at: Time.current
    )
    
    render json: { 
      success: true, 
      message: 'Missing payment logged for manual review',
      log_id: missing_payment_log.id
    }
  end
  
  def authenticate_service_request
    service_token = request.headers['X-Service-Token']
    expected_token = Rails.application.credentials.dig(:worker_service, :api_token)
    
    unless service_token == expected_token
      render json: { error: 'Unauthorized service request' }, status: 401
    end
  end
end