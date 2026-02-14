# frozen_string_literal: true

require_relative '../base_job'

# Payment Reconciliation Job
# Detects discrepancies between local payment records and payment provider data
class Billing::PaymentReconciliationJob < BaseJob
  include Billing::PaymentProviderFetchingConcern
  include Billing::ReconciliationAnalysisConcern

  sidekiq_options queue: 'billing',
                  retry: 2

  def execute(reconciliation_type = 'daily', date_range = nil)
    log_info("Starting payment reconciliation: #{reconciliation_type}")

    date_range ||= case reconciliation_type
                   when 'daily'
                     1.day.ago.beginning_of_day..1.day.ago.end_of_day
                   when 'weekly'
                     1.week.ago.beginning_of_week..1.week.ago.end_of_week
                   when 'monthly'
                     1.month.ago.beginning_of_month..1.month.ago.end_of_month
                   else
                     1.day.ago.beginning_of_day..1.day.ago.end_of_day
                   end

    reconciliation_results = {
      date_range: date_range,
      reconciliation_type: reconciliation_type,
      discrepancies: [],
      summary: {
        local_payments: 0,
        stripe_payments: 0,
        paypal_payments: 0,
        discrepancies_found: 0,
        total_amount_variance: 0
      }
    }

    # Reconcile Stripe payments
    stripe_reconciliation = reconcile_stripe_payments(date_range)
    reconciliation_results[:stripe_reconciliation] = stripe_reconciliation
    reconciliation_results[:discrepancies].concat(stripe_reconciliation[:discrepancies] || [])

    # Reconcile PayPal payments
    paypal_reconciliation = reconcile_paypal_payments(date_range)
    reconciliation_results[:paypal_reconciliation] = paypal_reconciliation
    reconciliation_results[:discrepancies].concat(paypal_reconciliation[:discrepancies] || [])

    # Generate summary
    reconciliation_results[:summary] = calculate_summary(reconciliation_results)

    # Report results
    report_reconciliation_results(reconciliation_results)

    # Take corrective actions if needed
    if reconciliation_results[:discrepancies].any?
      handle_discrepancies(reconciliation_results[:discrepancies])
    end

    reconciliation_results
  end

  private

  def reconcile_stripe_payments(date_range)
    log_info("Reconciling Stripe payments for #{date_range}")

    # Get local Stripe payments
    local_payments = get_local_stripe_payments(date_range)

    # Get Stripe payments from API
    stripe_payments = get_stripe_api_payments(date_range)

    # Compare and find discrepancies
    discrepancies = find_payment_discrepancies(local_payments, stripe_payments, 'stripe')

    {
      local_count: local_payments.count,
      stripe_api_count: stripe_payments.count,
      discrepancies: discrepancies,
      total_local_amount: local_payments.sum { |p| p['amount_cents'] },
      total_stripe_amount: stripe_payments.sum { |p| p['amount'] }
    }
  end

  def reconcile_paypal_payments(date_range)
    log_info("Reconciling PayPal payments for #{date_range}")

    # Get local PayPal payments
    local_payments = get_local_paypal_payments(date_range)

    # Get PayPal payments from API
    paypal_payments = get_paypal_api_payments(date_range)

    # Compare and find discrepancies
    discrepancies = find_payment_discrepancies(local_payments, paypal_payments, 'paypal')

    {
      local_count: local_payments.count,
      paypal_api_count: paypal_payments.count,
      discrepancies: discrepancies,
      total_local_amount: local_payments.sum { |p| p['amount_cents'] },
      total_paypal_amount: paypal_payments.sum { |p| p['amount_cents'] }
    }
  end
end
