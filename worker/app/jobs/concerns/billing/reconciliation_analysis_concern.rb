# frozen_string_literal: true

module Billing
  module ReconciliationAnalysisConcern
    extend ActiveSupport::Concern

    private

    def find_payment_discrepancies(local_payments, provider_payments, provider)
      discrepancies = []

      local_by_external_id = local_payments.group_by do |payment|
        case provider
        when 'stripe'
          payment['metadata']&.dig('stripe_charge_id') || payment['metadata']&.dig('stripe_payment_intent_id')
        when 'paypal'
          payment['metadata']&.dig('paypal_transaction_id') || payment['metadata']&.dig('paypal_order_id')
        end
      end

      provider_by_id = provider_payments.group_by { |p| p['id'] }

      # Check for payments in provider but not locally
      provider_payments.each do |provider_payment|
        local_matches = local_by_external_id[provider_payment['id']] || []

        if local_matches.empty?
          discrepancies << {
            type: 'missing_local_payment',
            provider: provider,
            provider_payment_id: provider_payment['id'],
            provider_amount: provider_payment['amount'],
            provider_currency: provider_payment['currency'],
            created_at: provider_payment['created'],
            severity: 'high'
          }
        else
          # Check for amount discrepancies
          local_payment = local_matches.first
          local_amount = local_payment['amount_cents']
          provider_amount = provider == 'stripe' ? provider_payment['amount'] : provider_payment['amount_cents']

          if local_amount != provider_amount
            discrepancies << {
              type: 'amount_mismatch',
              provider: provider,
              local_payment_id: local_payment['id'],
              provider_payment_id: provider_payment['id'],
              local_amount: local_amount,
              provider_amount: provider_amount,
              amount_difference: local_amount - provider_amount,
              severity: 'medium'
            }
          end
        end
      end

      # Check for local payments not found in provider
      local_payments.each do |local_payment|
        external_id = case provider
                     when 'stripe'
                       local_payment['metadata']&.dig('stripe_charge_id') || local_payment['metadata']&.dig('stripe_payment_intent_id')
                     when 'paypal'
                       local_payment['metadata']&.dig('paypal_transaction_id') || local_payment['metadata']&.dig('paypal_order_id')
                     end

        next unless external_id

        provider_matches = provider_by_id[external_id] || []

        if provider_matches.empty?
          discrepancies << {
            type: 'missing_provider_payment',
            provider: provider,
            local_payment_id: local_payment['id'],
            local_amount: local_payment['amount_cents'],
            external_id: external_id,
            severity: 'high'
          }
        end
      end

      discrepancies
    end

    def calculate_summary(reconciliation_results)
      summary = {
        local_payments: 0,
        stripe_payments: 0,
        paypal_payments: 0,
        discrepancies_found: reconciliation_results[:discrepancies].count,
        total_amount_variance: 0
      }

      if reconciliation_results[:stripe_reconciliation]
        summary[:local_payments] += reconciliation_results[:stripe_reconciliation][:local_count]
        summary[:stripe_payments] = reconciliation_results[:stripe_reconciliation][:stripe_api_count]
      end

      if reconciliation_results[:paypal_reconciliation]
        summary[:local_payments] += reconciliation_results[:paypal_reconciliation][:local_count]
        summary[:paypal_payments] = reconciliation_results[:paypal_reconciliation][:paypal_api_count]
      end

      # Calculate total amount variance
      reconciliation_results[:discrepancies].each do |discrepancy|
        if discrepancy[:amount_difference]
          summary[:total_amount_variance] += discrepancy[:amount_difference]
        end
      end

      summary
    end

    def report_reconciliation_results(results)
      report_data = {
        reconciliation_date: Date.current.iso8601,
        reconciliation_type: results[:reconciliation_type],
        date_range: {
          start: results[:date_range].begin.iso8601,
          end: results[:date_range].end.iso8601
        },
        summary: results[:summary],
        discrepancies_count: results[:discrepancies].count,
        high_severity_count: results[:discrepancies].count { |d| d[:severity] == 'high' },
        medium_severity_count: results[:discrepancies].count { |d| d[:severity] == 'medium' }
      }

      with_api_retry do
        api_client.post('/api/v1/reconciliation/report', report_data)
      end

      if results[:summary][:discrepancies_found] > 10 ||
         results[:discrepancies].any? { |d| d[:severity] == 'high' }

        send_reconciliation_alert(results)
      end

      log_info("Reconciliation completed: #{results[:summary][:discrepancies_found]} discrepancies found")
    end

    def handle_discrepancies(discrepancies)
      discrepancies.each do |discrepancy|
        case discrepancy[:type]
        when 'missing_local_payment'
          handle_missing_local_payment(discrepancy)
        when 'missing_provider_payment'
          handle_missing_provider_payment(discrepancy)
        when 'amount_mismatch'
          handle_amount_mismatch(discrepancy)
        end
      end
    end

    def handle_missing_local_payment(discrepancy)
      log_warn("Missing local payment: #{discrepancy[:provider_payment_id]}")

      correction_data = {
        type: 'create_missing_payment',
        provider: discrepancy[:provider],
        provider_payment_id: discrepancy[:provider_payment_id],
        amount: discrepancy[:provider_amount],
        currency: discrepancy[:provider_currency]
      }

      with_api_retry do
        api_client.post('/api/v1/reconciliation/corrections', correction_data)
      end
    end

    def handle_missing_provider_payment(discrepancy)
      log_warn("Missing provider payment: #{discrepancy[:external_id]}")

      flag_data = {
        type: 'missing_provider_payment',
        local_payment_id: discrepancy[:local_payment_id],
        external_id: discrepancy[:external_id],
        provider: discrepancy[:provider],
        requires_manual_review: true
      }

      with_api_retry do
        api_client.post('/api/v1/reconciliation/flags', flag_data)
      end
    end

    def handle_amount_mismatch(discrepancy)
      log_warn("Amount mismatch: Local=#{discrepancy[:local_amount]}, Provider=#{discrepancy[:provider_amount]}")

      investigation_data = {
        type: 'amount_mismatch',
        local_payment_id: discrepancy[:local_payment_id],
        provider_payment_id: discrepancy[:provider_payment_id],
        local_amount: discrepancy[:local_amount],
        provider_amount: discrepancy[:provider_amount],
        difference: discrepancy[:amount_difference],
        requires_investigation: true
      }

      with_api_retry do
        api_client.post('/api/v1/reconciliation/investigations', investigation_data)
      end
    end

    def send_reconciliation_alert(results)
      alert_data = {
        type: 'payment_reconciliation_alert',
        severity: 'high',
        summary: results[:summary],
        discrepancies_found: results[:discrepancies].count,
        high_priority_count: results[:discrepancies].count { |d| d[:severity] == 'high' },
        date_range: {
          start: results[:date_range].begin.iso8601,
          end: results[:date_range].end.iso8601
        }
      }

      with_api_retry do
        api_client.post('/api/v1/alerts', alert_data)
      end

      log_warn("Sent reconciliation alert: #{results[:discrepancies].count} discrepancies found")
    end
  end
end
