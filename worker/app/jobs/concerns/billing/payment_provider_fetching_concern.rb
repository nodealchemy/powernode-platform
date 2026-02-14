# frozen_string_literal: true

module Billing
  module PaymentProviderFetchingConcern
    extend ActiveSupport::Concern

    private

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

        access_token = get_paypal_access_token

        return payments unless access_token

        start_date = date_range.begin.utc.iso8601
        end_date = date_range.end.utc.iso8601

        page = 1
        total_pages = 1

        while page <= total_pages
          response = fetch_paypal_transactions(access_token, start_date, end_date, page)

          break unless response && response['transaction_details']

          response['transaction_details'].each do |transaction|
            transaction_info = transaction['transaction_info']
            next unless transaction_info
            next unless transaction_info['transaction_status'] == 'S'
            next unless %w[T0006 T0007 T0011].include?(transaction_info['transaction_event_code'])

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
      return 0 unless amount_string

      (BigDecimal(amount_string) * 100).to_i
    end
  end
end
