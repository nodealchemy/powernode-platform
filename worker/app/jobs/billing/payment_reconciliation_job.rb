# frozen_string_literal: true

require_relative '../base_job'

# Payment Reconciliation Job
# Detects discrepancies between local payment records and payment provider data
class Billing::PaymentReconciliationJob < BaseJob
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
  
  def get_local_stripe_payments(date_range)
    response = with_api_retry do
      api_client.get('/api/v1/reconciliation/stripe_payments', {
        start_date: date_range.begin.iso8601,
        end_date: date_range.end.iso8601
      })
    end

    unless response
      raise BillingExceptions::ReconciliationError.new(
        "Failed to fetch local Stripe payments from API",
        provider: 'stripe',
        discrepancy_type: 'fetch_failure',
        details: { date_range: date_range.to_s }
      )
    end

    response
  end

  def get_local_paypal_payments(date_range)
    response = with_api_retry do
      api_client.get('/api/v1/reconciliation/paypal_payments', {
        start_date: date_range.begin.iso8601,
        end_date: date_range.end.iso8601
      })
    end

    unless response
      raise BillingExceptions::ReconciliationError.new(
        "Failed to fetch local PayPal payments from API",
        provider: 'paypal',
        discrepancy_type: 'fetch_failure',
        details: { date_range: date_range.to_s }
      )
    end

    response
  end
  
  def get_stripe_api_payments(date_range)
    payments = []

    # Use Stripe API to get payments in the date range
    charges = Stripe::Charge.list(
      created: {
        gte: date_range.begin.to_i,
        lte: date_range.end.to_i
      },
      limit: 100
    )

    charges.auto_paging_each do |charge|
      next unless charge.status == 'succeeded'

      payments << {
        'id' => charge.id,
        'amount' => charge.amount,
        'currency' => charge.currency,
        'created' => Time.at(charge.created),
        'payment_intent' => charge.payment_intent,
        'customer' => charge.customer,
        'description' => charge.description
      }
    end

    payments
  rescue Stripe::RateLimitError => e
    log_error("Stripe rate limited during reconciliation: #{e.message}")
    raise BillingExceptions::RateLimitError.new(
      "Stripe API rate limited during reconciliation",
      provider: 'stripe',
      retry_after: 60
    )
  rescue Stripe::AuthenticationError => e
    log_error("Stripe authentication failed: #{e.message}")
    raise BillingExceptions::ConfigurationError.new(
      "Stripe authentication failed - check API keys",
      provider: 'stripe',
      missing_config: ['STRIPE_SECRET_KEY']
    )
  rescue Stripe::APIConnectionError => e
    log_error("Stripe connection failed: #{e.message}")
    raise BillingExceptions::GatewayError.new(
      "Failed to connect to Stripe API: #{e.message}",
      gateway: 'stripe',
      operation: 'fetch_charges'
    )
  rescue Stripe::StripeError => e
    log_error("Stripe API error during reconciliation: #{e.message}")
    raise BillingExceptions::ReconciliationError.new(
      "Failed to fetch Stripe payments: #{e.message}",
      provider: 'stripe',
      discrepancy_type: 'fetch_failure',
      details: { original_error: e.class.name }
    )
  end
  
  def get_paypal_api_payments(date_range)
    payments = []

    begin
      configure_paypal

      # Use PayPal Transaction Search API
      # API docs: https://developer.paypal.com/docs/api/transaction-search/v1/
      access_token = get_paypal_access_token

      return payments unless access_token

      # Format dates for PayPal API (ISO 8601)
      start_date = date_range.begin.utc.iso8601
      end_date = date_range.end.utc.iso8601

      # Paginate through results
      page = 1
      total_pages = 1

      while page <= total_pages
        response = fetch_paypal_transactions(access_token, start_date, end_date, page)

        break unless response && response['transaction_details']

        response['transaction_details'].each do |transaction|
          # Only include completed sale transactions
          transaction_info = transaction['transaction_info']
          next unless transaction_info
          next unless transaction_info['transaction_status'] == 'S' # S = Success
          next unless %w[T0006 T0007 T0011].include?(transaction_info['transaction_event_code'])
          # T0006 = PayPal Checkout, T0007 = Smart Payment Button, T0011 = Web Accept

          amount_info = transaction_info['transaction_amount']

          payments << {
            'id' => transaction_info['transaction_id'],
            'amount_cents' => parse_paypal_amount(amount_info['value']),
            'currency' => amount_info['currency_code'],
            'created' => Time.parse(transaction_info['transaction_initiation_date']),
            'payer_email' => transaction['payer_info']&.dig('email_address'),
            'payer_name' => transaction['payer_info']&.dig('payer_name', 'alternate_full_name'),
            'transaction_type' => transaction_info['transaction_event_code'],
            'paypal_reference_id' => transaction_info['paypal_reference_id']
          }
        end

        total_pages = response['total_pages'] || 1
        page += 1

        # Rate limiting - PayPal recommends max 30 requests per minute
        sleep(0.5) if page <= total_pages
      end

      log_info("Fetched #{payments.count} PayPal transactions for reconciliation")

    rescue PayPal::SDK::Core::Exceptions::UnauthorizedAccess => e
      log_error("PayPal authentication failed: #{e.message}")
      raise BillingExceptions::GatewayError.new(
        "PayPal authentication failed: #{e.message}",
        gateway: 'paypal',
        operation: 'fetch_transactions'
      )
    rescue StandardError => e
      log_error("Failed to fetch PayPal payments: #{e.message}")
      log_error(e.backtrace.first(5).join("\n")) if e.backtrace
      raise BillingExceptions::ReconciliationError.new(
        "Failed to fetch PayPal payments: #{e.message}",
        provider: 'paypal',
        discrepancy_type: 'fetch_failure',
        details: { original_error: e.class.name }
      )
    end

    payments
  end

  def configure_paypal
    client_id = ENV['PAYPAL_CLIENT_ID']
    client_secret = ENV['PAYPAL_CLIENT_SECRET']

    if client_id.blank? || client_secret.blank?
      raise BillingExceptions::ConfigurationError.new(
        "PayPal credentials not configured. PAYPAL_CLIENT_ID and PAYPAL_CLIENT_SECRET must be set.",
        provider: 'paypal',
        missing_config: [
          ('PAYPAL_CLIENT_ID' if client_id.blank?),
          ('PAYPAL_CLIENT_SECRET' if client_secret.blank?)
        ].compact
      )
    end

    PayPal::SDK.configure(
      mode: paypal_mode,
      client_id: client_id,
      client_secret: client_secret
    )
  end

  def paypal_mode
    ENV.fetch('PAYPAL_MODE', 'sandbox')
  end

  def get_paypal_access_token
    # Get OAuth2 access token from PayPal
    require 'net/http'
    require 'uri'

    base_url = paypal_mode == 'live' ?
      'https://api-m.paypal.com' :
      'https://api-m.sandbox.paypal.com'

    uri = URI("#{base_url}/v1/oauth2/token")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request.basic_auth(ENV['PAYPAL_CLIENT_ID'], ENV['PAYPAL_CLIENT_SECRET'])
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request.body = 'grant_type=client_credentials'

    response = http.request(request)

    if response.code.to_i == 200
      result = JSON.parse(response.body)
      result['access_token']
    else
      log_error("PayPal OAuth failed: #{response.code} - #{response.body}")
      nil
    end
  end

  def fetch_paypal_transactions(access_token, start_date, end_date, page)
    require 'net/http'
    require 'uri'

    base_url = paypal_mode == 'live' ?
      'https://api-m.paypal.com' :
      'https://api-m.sandbox.paypal.com'

    # Build query params
    params = {
      start_date: start_date,
      end_date: end_date,
      fields: 'all',
      page_size: 100,
      page: page
    }

    query_string = URI.encode_www_form(params)
    uri = URI("#{base_url}/v1/reporting/transactions?#{query_string}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'

    response = http.request(request)

    if response.code.to_i == 200
      JSON.parse(response.body)
    else
      log_error("PayPal transaction search failed: #{response.code} - #{response.body}")
      nil
    end
  end

  def parse_paypal_amount(amount_string)
    # PayPal returns amounts as strings like "10.00"
    # Convert to cents (integer)
    return 0 unless amount_string

    (BigDecimal(amount_string) * 100).to_i
  end
  
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
    # Send reconciliation report via API
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
    
    # If there are significant discrepancies, send alert
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
    
    # Create corrective action job
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
    
    # Flag for manual review
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
    
    # Flag for investigation
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