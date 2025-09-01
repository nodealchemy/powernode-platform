# frozen_string_literal: true

class Api::V1::PaymentGatewaysController < ApplicationController
  # Admin operations require admin.settings.payment permission
  before_action -> { require_permission('admin.settings.payment') }, except: [:index]
  # index method is public for dashboard overview - no authentication required
  skip_before_action :authenticate_request, only: [:index]
  
  def index
    begin
      render_success({
        gateways: gateway_configurations,
        status: gateway_configuration_statuses, # Use configuration-based status only
        recent_transactions: recent_transactions_data,
        statistics: gateway_statistics
      })
    rescue => e
      Rails.logger.error "Payment gateways overview error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      
      render json: { success: false, error: "Failed to load payment gateways overview" }, status: :internal_server_error
    end
  end

  def show
    gateway = params[:id]
    unless valid_gateway?(gateway)
      render_error("Invalid gateway", status: :not_found)
      return
    end

    render_success({
      gateway: gateway,
      configuration: gateway_configuration_for(gateway),
      status: gateway_status_for(gateway),
      transactions: transactions_for_gateway(gateway),
      webhooks: webhooks_for_gateway(gateway),
      statistics: statistics_for_gateway(gateway)
    })
  end

  def update
    gateway = params[:id]
    unless valid_gateway?(gateway)
      render_error("Invalid gateway", status: :not_found)
      return
    end

    begin
      update_gateway_configuration(gateway, gateway_params)
      
      render json: {
        message: "Gateway configuration updated successfully",
        gateway: gateway,
        configuration: gateway_configuration_for(gateway)
      }
    rescue => e
      render_error(e.message, status: :unprocessable_content)
    end
  end

  def test_connection
    gateway = params[:id]
    unless valid_gateway?(gateway)
      render_error("Invalid gateway", status: :not_found)
      return
    end

    begin
      # Create a job record to track the async test
      job = GatewayConnectionJob.create!(
        gateway: gateway,
        status: 'pending',
        config_data: build_config_data_for_gateway(gateway)
      )

      # Delegate to worker service for async processing
      enqueue_gateway_test_job(job.id, gateway, job.config_data)

      render_success({
        job_id: job.id,
        status: 'pending',
        message: 'Gateway connection test started',
        poll_url: "/api/v1/gateway_connection_jobs/#{job.id}"
      })
    rescue => e
      Rails.logger.error "Failed to start gateway connection test: #{e.message}"
      render_error("Failed to start connection test: #{e.message}", status: :internal_server_error)
    end
  end

  def webhook_events
    gateway = params[:id]
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 20, 100].min
    
    events_query = WebhookEvent.includes(:payment)
                                  .where(provider: gateway)
                                  .order(created_at: :desc)
    
    total_count = events_query.count
    events = events_query.limit(per_page).offset((page - 1) * per_page)

    render json: {
      events: events.map do |event|
        {
          id: event.id,
          event_type: event.event_type,
          status: event.status,
          payment_id: event.payment_id,
          external_id: event.external_id,
          processed_at: event.processed_at,
          created_at: event.created_at,
          error_message: event.error_message
        }
      end,
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count / per_page.to_f).ceil
      }
    }
  end

  def transactions
    gateway = params[:id]
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 20, 100].min
    
    payments_query = Payment.joins(:invoice)
                           .where(payment_method: gateway_payment_methods(gateway))
                           .order(created_at: :desc)
    
    total_count = payments_query.count
    payments = payments_query.limit(per_page).offset((page - 1) * per_page)

    render json: {
      transactions: payments.map do |payment|
        {
          id: payment.id,
          invoice_id: payment.invoice_id,
          amount: payment.amount.to_s,
          currency: payment.currency,
          status: payment.status,
          payment_method: payment.payment_method,
          gateway_transaction_id: payment.gateway_transaction_id,
          created_at: payment.created_at,
          processed_at: payment.processed_at,
          gateway_fee: payment.gateway_fee.to_s,
          net_amount: payment.net_amount.to_s
        }
      end,
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count / per_page.to_f).ceil
      }
    }
  end

  private

  def gateway_params
    case params[:id]
    when 'stripe'
      params.require(:configuration).permit(
        :publishable_key, :secret_key, :endpoint_secret, 
        :webhook_tolerance, :enabled, :test_mode
      )
    when 'paypal'
      params.require(:configuration).permit(
        :client_id, :client_secret, :webhook_id,
        :mode, :enabled, :test_mode
      )
    else
      {}
    end
  end

  def valid_gateway?(gateway)
    %w[stripe paypal].include?(gateway)
  end

  def gateway_configurations
    {
      stripe: gateway_configuration_for('stripe'),
      paypal: gateway_configuration_for('paypal')
    }
  end

  def gateway_configuration_for(gateway)
    case gateway
    when 'stripe'
      stored_config = GatewayConfiguration.stripe_config
      env_config = safe_config(:stripe)
      
      enabled_stored = stored_config[:enabled]
      enabled_env = env_config[:secret_key].present?
      test_mode_stored = stored_config[:test_mode]
      
      {
        provider: 'stripe',
        name: 'Stripe',
        enabled: (enabled_stored == 'true') || enabled_env,
        test_mode: (test_mode_stored == 'true') || !Rails.env.production?,
        publishable_key_present: stored_config[:publishable_key].present? || is_real_config_value?(env_config[:publishable_key]),
        secret_key_present: stored_config[:secret_key].present? || is_real_config_value?(env_config[:secret_key]),
        endpoint_secret_present: stored_config[:endpoint_secret].present? || is_real_config_value?(env_config[:endpoint_secret]),
        webhook_tolerance: stored_config[:webhook_tolerance] || env_config[:webhook_tolerance] || 300,
        api_version: get_stripe_api_version,
        supported_methods: %w[card bank apple_pay google_pay]
      }
    when 'paypal'
      stored_config = GatewayConfiguration.paypal_config
      env_config = safe_config(:paypal)
      
      enabled_stored = stored_config[:enabled]
      enabled_env = env_config[:client_id].present?
      mode = stored_config[:mode] || env_config[:mode] || 'sandbox'
      test_mode_stored = stored_config[:test_mode]
      
      {
        provider: 'paypal',
        name: 'PayPal',
        enabled: (enabled_stored == 'true') || enabled_env,
        test_mode: (test_mode_stored == 'true') || mode == 'sandbox',
        client_id_present: stored_config[:client_id].present? || is_real_config_value?(env_config[:client_id]),
        client_secret_present: stored_config[:client_secret].present? || is_real_config_value?(env_config[:client_secret]),
        webhook_id_present: stored_config[:webhook_id].present? || is_real_config_value?(env_config[:webhook_id]),
        mode: mode,
        supported_methods: %w[paypal]
      }
    else
      {
        provider: gateway,
        name: gateway.capitalize,
        enabled: false,
        error: 'Unsupported gateway'
      }
    end
  end

  def gateway_statuses
    {
      stripe: gateway_status_for('stripe'),
      paypal: gateway_status_for('paypal')
    }
  end

  def gateway_configuration_statuses
    # Configuration-based status without external API calls (for dashboard)
    {
      stripe: gateway_config_status_for('stripe'),
      paypal: gateway_config_status_for('paypal')
    }
  end

  def gateway_status_for(gateway)
    begin
      case gateway
      when 'stripe'
        stored_config = GatewayConfiguration.stripe_config
        env_config = safe_config(:stripe)
        
        # Use same placeholder detection logic
        secret_key_present = stored_config[:secret_key].present? || is_real_config_value?(env_config[:secret_key])
        secret_key = stored_config[:secret_key] || env_config[:secret_key]
        
        if secret_key_present
          # Quick Stripe API test
          begin
            Stripe.api_key = secret_key
            account = Stripe::Account.retrieve
            { 
              status: 'connected', 
              message: 'Connected and operational', 
              last_checked: Time.current,
              account_id: account.id
            }
          rescue Stripe::AuthenticationError
            { status: 'authentication_failed', message: 'Invalid API key', last_checked: Time.current }
          rescue Stripe::StripeError => e
            { status: 'error', message: e.message, last_checked: Time.current }
          end
        else
          { status: 'not_configured', message: 'Secret key not configured', last_checked: Time.current }
        end
      when 'paypal'
        stored_config = GatewayConfiguration.paypal_config
        env_config = safe_config(:paypal)
        
        # Use same logic as configuration presence flags
        client_id_present = stored_config[:client_id].present? || is_real_config_value?(env_config[:client_id])
        client_secret_present = stored_config[:client_secret].present? || is_real_config_value?(env_config[:client_secret])
        
        if client_id_present && client_secret_present
          { status: 'configured', message: 'Configuration present', last_checked: Time.current }
        elsif client_id_present
          { status: 'partial', message: 'Client ID configured, secret missing', last_checked: Time.current }
        else
          { status: 'not_configured', message: 'Client credentials not configured', last_checked: Time.current }
        end
      else
        { status: 'unsupported', message: 'Gateway not supported', last_checked: Time.current }
      end
    rescue => e
      Rails.logger.error "Gateway status check failed for #{gateway}: #{e.message}"
      { status: 'error', message: 'Status check failed', last_checked: Time.current }
    end
  end

  def gateway_config_status_for(gateway)
    # Status based only on configuration presence - no external API calls
    case gateway
    when 'stripe'
      stored_config = GatewayConfiguration.stripe_config
      env_config = safe_config(:stripe)
      
      secret_key_present = stored_config[:secret_key].present? || is_real_config_value?(env_config[:secret_key])
      publishable_key_present = stored_config[:publishable_key].present? || is_real_config_value?(env_config[:publishable_key])
      
      if secret_key_present && publishable_key_present
        { status: 'configured', message: 'Keys configured', last_checked: Time.current }
      elsif secret_key_present || publishable_key_present
        { status: 'partial', message: 'Partially configured', last_checked: Time.current }
      else
        { status: 'not_configured', message: 'Keys not configured', last_checked: Time.current }
      end
    when 'paypal'
      stored_config = GatewayConfiguration.paypal_config
      env_config = safe_config(:paypal)
      
      client_id_present = stored_config[:client_id].present? || is_real_config_value?(env_config[:client_id])
      client_secret_present = stored_config[:client_secret].present? || is_real_config_value?(env_config[:client_secret])
      
      if client_id_present && client_secret_present
        { status: 'configured', message: 'Credentials configured', last_checked: Time.current }
      elsif client_id_present
        { status: 'partial', message: 'Client ID configured, secret missing', last_checked: Time.current }
      else
        { status: 'not_configured', message: 'Credentials not configured', last_checked: Time.current }
      end
    else
      { status: 'unsupported', message: 'Gateway not supported', last_checked: Time.current }
    end
  end

  def recent_transactions_data
    begin
      unless defined?(Payment) && Payment.respond_to?(:includes)
        return []
      end
      
      query = Payment.order(created_at: :desc).limit(10)
      
      # Only include invoice if the association exists
      if Payment.reflect_on_association(:invoice)
        query = query.includes(:invoice)
      end
      
      query.map do |payment|
        {
          id: payment.id,
          amount: safe_get_amount(payment),
          currency: payment.respond_to?(:currency) ? payment.currency : 'USD',
          status: payment.status,
          provider: payment.respond_to?(:provider) ? payment.provider : 'unknown',
          created_at: payment.created_at
        }
      end
    rescue => e
      Rails.logger.error "Recent transactions error: #{e.message}"
      []
    end
  end

  def gateway_statistics
    {
      stripe: statistics_for_gateway('stripe'),
      paypal: statistics_for_gateway('paypal'),
      overall: overall_statistics
    }
  end

  def statistics_for_gateway(gateway)
    begin
      methods = gateway_payment_methods(gateway)
      return empty_statistics if methods.empty?
      
      # Check if Payment model exists and has required methods
      unless defined?(Payment) && Payment.respond_to?(:where)
        return empty_statistics
      end
      
      payments = Payment.where(payment_method: methods)
      
      {
        total_transactions: payments.count,
        successful_transactions: count_by_status(payments, 'succeeded'),
        failed_transactions: count_by_status(payments, 'failed'),
        total_volume: sum_amount_for_status(payments, 'succeeded'),
        total_fees: sum_fees_for_status(payments, 'succeeded'),
        success_rate: calculate_success_rate(payments),
        last_30_days: {
          transactions: payments.where(created_at: 30.days.ago..Time.current).count,
          volume: sum_amount_for_status(payments.where(created_at: 30.days.ago..Time.current), 'succeeded')
        }
      }
    rescue => e
      Rails.logger.error "Statistics error for #{gateway}: #{e.message}"
      empty_statistics
    end
  end

  def overall_statistics
    begin
      unless defined?(Payment) && Payment.respond_to?(:all)
        return empty_statistics
      end
      
      payments = Payment.all
      {
        total_transactions: payments.count,
        successful_transactions: count_by_status(payments, 'succeeded'),
        failed_transactions: count_by_status(payments, 'failed'),
        total_volume: sum_amount_for_status(payments, 'succeeded'),
        success_rate: calculate_success_rate(payments)
      }
    rescue => e
      Rails.logger.error "Overall statistics error: #{e.message}"
      empty_statistics
    end
  end

  def transactions_for_gateway(gateway)
    begin
      methods = gateway_payment_methods(gateway)
      return [] if methods.empty?
      
      unless defined?(Payment) && Payment.respond_to?(:where)
        return []
      end
      
      Payment.where(payment_method: methods)
             .order(created_at: :desc)
             .limit(20)
             .map do |payment|
        {
          id: payment.id,
          amount: safe_get_amount(payment),
          currency: payment.respond_to?(:currency) ? payment.currency : 'USD',
          status: payment.status,
          created_at: payment.created_at,
          gateway_transaction_id: payment.respond_to?(:gateway_transaction_id) ? payment.gateway_transaction_id : nil
        }
      end
    rescue => e
      Rails.logger.error "Transactions error for #{gateway}: #{e.message}"
      []
    end
  end

  def webhooks_for_gateway(gateway)
    begin
      unless defined?(WebhookEvent) && WebhookEvent.respond_to?(:where)
        return []
      end
      
      WebhookEvent.where(provider: gateway)
                  .order(created_at: :desc)
                  .limit(20)
                  .map do |event|
        {
          id: event.id,
          event_type: event.respond_to?(:event_type) ? event.event_type : 'unknown',
          status: event.respond_to?(:status) ? event.status : 'unknown',
          created_at: event.created_at,
          processed_at: event.respond_to?(:processed_at) ? event.processed_at : nil
        }
      end
    rescue => e
      Rails.logger.error "Webhooks error for #{gateway}: #{e.message}"
      []
    end
  end

  def gateway_payment_methods(gateway)
    case gateway
    when 'stripe'
      %w[stripe_card stripe_bank]
    when 'paypal'
      %w[paypal]
    else
      []
    end
  end

  def calculate_success_rate(payments)
    total = payments.count
    return 0 if total.zero?
    
    successful = payments.succeeded.count
    (successful.to_f / total * 100).round(2)
  end

  def build_config_data_for_gateway(gateway)
    case gateway
    when 'stripe'
      stored_config = GatewayConfiguration.stripe_config
      env_config = safe_config(:stripe)
      {
        'secret_key' => stored_config[:secret_key] || env_config[:secret_key]
      }
    when 'paypal'
      stored_config = GatewayConfiguration.paypal_config
      env_config = safe_config(:paypal)
      {
        'client_id' => stored_config[:client_id] || env_config[:client_id],
        'client_secret' => stored_config[:client_secret] || env_config[:client_secret],
        'mode' => stored_config[:mode] || env_config[:mode] || 'sandbox',
        'webhook_id' => stored_config[:webhook_id] || env_config[:webhook_id]
      }
    else
      {}
    end
  end

  def enqueue_gateway_test_job(job_id, gateway, config_data)
    # Use HTTP client to call worker service via jobs endpoint
    worker_client = build_worker_client
    
    response = worker_client.post('/api/v1/jobs', {
      job_class: 'Services::TestPaymentGatewayConnectionJob',
      args: [job_id, gateway, config_data],
      queue: 'high'
    })
    
    unless response.code.to_i == 200
      raise "Failed to enqueue worker job: #{response.body}"
    end
    
    Rails.logger.info "Enqueued gateway test job #{job_id} for #{gateway}"
  rescue => e
    Rails.logger.error "Failed to enqueue gateway test job: #{e.message}"
    raise
  end

  def build_worker_client
    require 'net/http'
    require 'json'
    
    @worker_client ||= begin
      worker_url = ENV.fetch('WORKER_API_URL', 'http://localhost:4567')
      worker_token = ENV.fetch('WORKER_TOKEN', '')
      
      WorkerHttpClient.new(worker_url, worker_token)
    end
  end

  def update_gateway_configuration(gateway, config_params)
    case gateway
    when 'stripe'
      validate_stripe_config(config_params)
      save_stripe_configuration(config_params)
    when 'paypal'
      validate_paypal_config(config_params)
      save_paypal_configuration(config_params)
    end
  end

  def save_stripe_configuration(config)
    GatewayConfiguration.set_config('stripe', 'publishable_key', config[:publishable_key]) if config[:publishable_key].present?
    GatewayConfiguration.set_config('stripe', 'secret_key', config[:secret_key]) if config[:secret_key].present?
    GatewayConfiguration.set_config('stripe', 'endpoint_secret', config[:endpoint_secret]) if config[:endpoint_secret].present?
    GatewayConfiguration.set_config('stripe', 'webhook_tolerance', config[:webhook_tolerance].to_s) if config[:webhook_tolerance].present?
    GatewayConfiguration.set_config('stripe', 'enabled', config[:enabled].to_s)
    GatewayConfiguration.set_config('stripe', 'test_mode', config[:test_mode].to_s)
  end

  def save_paypal_configuration(config)
    GatewayConfiguration.set_config('paypal', 'client_id', config[:client_id]) if config[:client_id].present?
    GatewayConfiguration.set_config('paypal', 'client_secret', config[:client_secret]) if config[:client_secret].present?
    GatewayConfiguration.set_config('paypal', 'webhook_id', config[:webhook_id]) if config[:webhook_id].present?
    GatewayConfiguration.set_config('paypal', 'mode', config[:mode]) if config[:mode].present?
    GatewayConfiguration.set_config('paypal', 'enabled', config[:enabled].to_s)
    GatewayConfiguration.set_config('paypal', 'test_mode', config[:test_mode].to_s)
  end

  def validate_stripe_config(config)
    errors = []
    
    # Only validate format if secret key is provided (now optional)
    if config[:secret_key].present?
      unless config[:secret_key].match(/^sk_(test_|live_)?[a-zA-Z0-9_]{20,}$/)
        errors << "Secret key format is invalid (must start with sk_test_ or sk_live_)"
      end
    end
    
    # Only validate format if publishable key is provided (now optional)
    if config[:publishable_key].present?
      unless config[:publishable_key].match(/^pk_(test_|live_)?[a-zA-Z0-9_]{20,}$/)
        errors << "Publishable key format is invalid (must start with pk_test_ or pk_live_)"
      end
    end
    
    if config[:endpoint_secret].present?
      unless config[:endpoint_secret].match(/^whsec_[a-zA-Z0-9]+$/)
        errors << "Webhook endpoint secret format is invalid"
      end
    end
    
    if config[:webhook_tolerance].present?
      tolerance = config[:webhook_tolerance].to_i
      unless tolerance.between?(1, 3600)
        errors << "Webhook tolerance must be between 1 and 3600 seconds"
      end
    end
    
    raise errors.join(", ") unless errors.empty?
  end

  def validate_paypal_config(config)
    errors = []
    
    # Only validate format if client ID is provided (now optional)
    if config[:client_id].present? && config[:client_id].length < 10
      errors << "Client ID must be at least 10 characters"
    end
    
    # Only validate format if client secret is provided (now optional)
    if config[:client_secret].present? && config[:client_secret].length < 10
      errors << "Client secret must be at least 10 characters"
    end
    
    if config[:mode].present?
      unless %w[sandbox live].include?(config[:mode])
        errors << "Mode must be either 'sandbox' or 'live'"
      end
    end
    
    raise errors.join(", ") unless errors.empty?
  end
  
  # Helper methods for safe configuration access
  def safe_config(provider)
    case provider
    when :stripe
      Rails.application.config.respond_to?(:stripe) ? Rails.application.config.stripe : {}
    when :paypal
      Rails.application.config.respond_to?(:paypal) ? Rails.application.config.paypal : {}
    else
      {}
    end
  rescue => e
    Rails.logger.warn "Failed to access #{provider} config: #{e.message}"
    {}
  end
  
  def get_stripe_api_version
    defined?(Stripe) ? Stripe.api_version : 'unknown'
  rescue => e
    Rails.logger.warn "Failed to get Stripe API version: #{e.message}"
    'unknown'
  end
  
  # Statistics helper methods
  def empty_statistics
    {
      total_transactions: 0,
      successful_transactions: 0,
      failed_transactions: 0,
      total_volume: 0,
      total_fees: 0,
      success_rate: 0.0,
      last_30_days: {
        transactions: 0,
        volume: 0
      }
    }
  end
  
  def count_by_status(payments, status)
    if payments.respond_to?(status.to_sym)
      payments.public_send(status.to_sym).count
    else
      payments.where(status: status).count
    end
  rescue => e
    Rails.logger.warn "Failed to count payments by status #{status}: #{e.message}"
    0
  end
  
  def sum_amount_for_status(payments, status)
    target_payments = if payments.respond_to?(status.to_sym)
      payments.public_send(status.to_sym)
    else
      payments.where(status: status)
    end
    
    # Try different amount column names
    %w[amount_cents amount].each do |column|
      if target_payments.column_names.include?(column)
        return target_payments.sum(column) || 0
      end
    end
    
    0
  rescue => e
    Rails.logger.warn "Failed to sum amounts for status #{status}: #{e.message}"
    0
  end
  
  def sum_fees_for_status(payments, status)
    target_payments = if payments.respond_to?(status.to_sym)
      payments.public_send(status.to_sym)
    else
      payments.where(status: status)
    end
    
    # Try different fee column names
    %w[gateway_fee_cents gateway_fee fee_cents fee].each do |column|
      if target_payments.column_names.include?(column)
        return target_payments.sum(column) || 0
      end
    end
    
    0
  rescue => e
    Rails.logger.warn "Failed to sum fees for status #{status}: #{e.message}"
    0
  end
  
  def safe_get_amount(payment)
    # Try different amount attribute names and methods
    %w[amount amount_cents].each do |attr|
      if payment.respond_to?(attr)
        value = payment.public_send(attr)
        return value.respond_to?(:to_s) ? value.to_s : value.to_i.to_s
      end
    end
    
    # Try accessing as Money object
    if payment.respond_to?(:amount) && payment.amount.respond_to?(:cents)
      return payment.amount.cents.to_s
    end
    
    '0'
  rescue => e
    Rails.logger.warn "Failed to get amount for payment #{payment.id}: #{e.message}"
    '0'
  end

  # Check if a configuration value is real vs placeholder
  def is_real_config_value?(value)
    return false unless value.present?
    
    # Common placeholder values that shouldn't be considered "configured"
    placeholder_values = [
      'your_paypal_client_id',
      'your_paypal_client_secret', 
      'your_paypal_webhook_id',
      'your_stripe_publishable_key',
      'your_stripe_secret_key',
      'your_stripe_webhook_secret',
      'placeholder',
      'change_me',
      'update_this',
      'your_key_here',
      'sk_test_placeholder',
      'pk_test_placeholder'
    ]
    
    # Check if the value is a known placeholder
    return false if placeholder_values.include?(value.to_s.downcase)
    
    # Check for generic placeholder patterns
    return false if value.to_s.match?(/^your_\w+|placeholder|change.?me|update.?this|key.?here$/i)
    
    # If it passes all checks, consider it a real configuration value
    true
  end
end

class WorkerHttpClient
  def initialize(base_url, token)
    @base_url = base_url
    @token = token
  end
  
  def post(path, data)
    uri = URI.parse("#{@base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{@token}"
    request.body = data.to_json
    
    http.request(request)
  end
end