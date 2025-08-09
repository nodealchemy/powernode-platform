class Api::V1::PaymentGatewaysController < ApplicationController
  before_action :require_admin!
  
  def index
    render json: {
      gateways: gateway_configurations,
      status: gateway_statuses,
      recent_transactions: recent_transactions_data,
      statistics: gateway_statistics
    }
  end

  def show
    gateway = params[:id]
    unless valid_gateway?(gateway)
      render json: { error: "Invalid gateway" }, status: :not_found
      return
    end

    render json: {
      gateway: gateway,
      configuration: gateway_configuration_for(gateway),
      status: gateway_status_for(gateway),
      transactions: transactions_for_gateway(gateway),
      webhooks: webhooks_for_gateway(gateway),
      statistics: statistics_for_gateway(gateway)
    }
  end

  def update
    gateway = params[:id]
    unless valid_gateway?(gateway)
      render json: { error: "Invalid gateway" }, status: :not_found
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
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def test_connection
    gateway = params[:id]
    unless valid_gateway?(gateway)
      render json: { error: "Invalid gateway" }, status: :not_found
      return
    end

    begin
      test_result = test_gateway_connection(gateway)
      render json: test_result
    rescue => e
      render json: { 
        success: false, 
        error: e.message,
        tested_at: Time.current.iso8601
      }, status: :service_unavailable
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
      env_config = Rails.application.config.stripe
      
      {
        provider: 'stripe',
        name: 'Stripe',
        enabled: (stored_config[:enabled] == 'true') || env_config[:secret_key].present?,
        test_mode: (stored_config[:test_mode] == 'true') || !Rails.env.production?,
        publishable_key_present: stored_config[:publishable_key].present? || env_config[:publishable_key].present?,
        secret_key_present: stored_config[:secret_key].present? || env_config[:secret_key].present?,
        endpoint_secret_present: stored_config[:endpoint_secret].present? || env_config[:endpoint_secret].present?,
        webhook_tolerance: stored_config[:webhook_tolerance] || env_config[:webhook_tolerance],
        api_version: Stripe.api_version,
        supported_methods: %w[card bank apple_pay google_pay]
      }
    when 'paypal'
      stored_config = GatewayConfiguration.paypal_config
      env_config = Rails.application.config.paypal
      
      {
        provider: 'paypal',
        name: 'PayPal',
        enabled: (stored_config[:enabled] == 'true') || env_config[:client_id].present?,
        test_mode: (stored_config[:test_mode] == 'true') || stored_config[:mode] == 'sandbox' || env_config[:mode] == 'sandbox',
        client_id_present: stored_config[:client_id].present? || env_config[:client_id].present?,
        client_secret_present: stored_config[:client_secret].present? || env_config[:client_secret].present?,
        webhook_id_present: stored_config[:webhook_id].present? || env_config[:webhook_id].present?,
        mode: stored_config[:mode] || env_config[:mode],
        supported_methods: %w[paypal]
      }
    end
  end

  def gateway_statuses
    {
      stripe: gateway_status_for('stripe'),
      paypal: gateway_status_for('paypal')
    }
  end

  def gateway_status_for(gateway)
    begin
      case gateway
      when 'stripe'
        stored_config = GatewayConfiguration.stripe_config
        env_config = Rails.application.config.stripe
        secret_key = stored_config[:secret_key] || env_config[:secret_key]
        
        if secret_key.present?
          # Quick Stripe API test
          Stripe.api_key = secret_key
          Stripe::Account.retrieve
          { status: 'connected', message: 'Connected and operational', last_checked: Time.current }
        else
          { status: 'not_configured', message: 'Secret key not configured', last_checked: Time.current }
        end
      when 'paypal'
        stored_config = GatewayConfiguration.paypal_config
        env_config = Rails.application.config.paypal
        client_id = stored_config[:client_id] || env_config[:client_id]
        
        if client_id.present?
          { status: 'configured', message: 'Configuration present', last_checked: Time.current }
        else
          { status: 'not_configured', message: 'Client ID not configured', last_checked: Time.current }
        end
      end
    rescue => e
      { status: 'error', message: e.message, last_checked: Time.current }
    end
  end

  def recent_transactions_data
    Payment.includes(:invoice)
           .order(created_at: :desc)
           .limit(10)
           .map do |payment|
      {
        id: payment.id,
        amount: payment.amount.to_s,
        currency: payment.currency,
        status: payment.status,
        provider: payment.provider,
        created_at: payment.created_at
      }
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
    methods = gateway_payment_methods(gateway)
    payments = Payment.where(payment_method: methods)
    
    {
      total_transactions: payments.count,
      successful_transactions: payments.succeeded.count,
      failed_transactions: payments.failed.count,
      total_volume: payments.succeeded.sum(:amount_cents),
      total_fees: payments.succeeded.sum(:gateway_fee_cents) || 0,
      success_rate: calculate_success_rate(payments),
      last_30_days: {
        transactions: payments.where(created_at: 30.days.ago..Time.current).count,
        volume: payments.succeeded.where(created_at: 30.days.ago..Time.current).sum(:amount_cents)
      }
    }
  end

  def overall_statistics
    payments = Payment.all
    {
      total_transactions: payments.count,
      successful_transactions: payments.succeeded.count,
      failed_transactions: payments.failed.count,
      total_volume: payments.succeeded.sum(:amount_cents),
      success_rate: calculate_success_rate(payments)
    }
  end

  def transactions_for_gateway(gateway)
    methods = gateway_payment_methods(gateway)
    Payment.where(payment_method: methods)
           .order(created_at: :desc)
           .limit(20)
           .map do |payment|
      {
        id: payment.id,
        amount: payment.amount.to_s,
        currency: payment.currency,
        status: payment.status,
        created_at: payment.created_at,
        gateway_transaction_id: payment.gateway_transaction_id
      }
    end
  end

  def webhooks_for_gateway(gateway)
    WebhookEvent.where(provider: gateway)
                .order(created_at: :desc)
                .limit(20)
                .map do |event|
      {
        id: event.id,
        event_type: event.event_type,
        status: event.status,
        created_at: event.created_at,
        processed_at: event.processed_at
      }
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

  def test_gateway_connection(gateway)
    case gateway
    when 'stripe'
      test_stripe_connection
    when 'paypal'
      test_paypal_connection
    end
  end

  def test_stripe_connection
    stored_config = GatewayConfiguration.stripe_config
    env_config = Rails.application.config.stripe
    secret_key = stored_config[:secret_key] || env_config[:secret_key]
    
    raise "No Stripe secret key configured" unless secret_key.present?
    
    Stripe.api_key = secret_key
    account = Stripe::Account.retrieve
    
    {
      success: true,
      gateway: 'stripe',
      account_id: account.id,
      business_name: account.business_profile&.name || account.settings&.dashboard&.display_name,
      country: account.country,
      currency: account.default_currency,
      charges_enabled: account.charges_enabled,
      payouts_enabled: account.payouts_enabled,
      tested_at: Time.current.iso8601
    }
  end

  def test_paypal_connection
    stored_config = GatewayConfiguration.paypal_config
    env_config = Rails.application.config.paypal
    
    client_id = stored_config[:client_id] || env_config[:client_id]
    client_secret = stored_config[:client_secret] || env_config[:client_secret]
    mode = stored_config[:mode] || env_config[:mode]
    webhook_id = stored_config[:webhook_id] || env_config[:webhook_id]
    
    {
      success: client_id.present? && client_secret.present?,
      gateway: 'paypal',
      mode: mode,
      client_id_configured: client_id.present?,
      webhook_configured: webhook_id.present?,
      tested_at: Time.current.iso8601
    }
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
    
    if config[:secret_key].present?
      unless config[:secret_key].match(/^sk_(test_|live_)?[a-zA-Z0-9_]{20,}$/)
        errors << "Secret key format is invalid (must start with sk_test_ or sk_live_)"
      end
    else
      errors << "Secret key is required"
    end
    
    if config[:publishable_key].present?
      unless config[:publishable_key].match(/^pk_(test_|live_)?[a-zA-Z0-9_]{20,}$/)
        errors << "Publishable key format is invalid (must start with pk_test_ or pk_live_)"
      end
    else
      errors << "Publishable key is required"
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
    
    if config[:client_id].blank?
      errors << "Client ID is required"
    end
    
    if config[:client_secret].blank?
      errors << "Client secret is required"
    end
    
    if config[:mode].present?
      unless %w[sandbox live].include?(config[:mode])
        errors << "Mode must be either 'sandbox' or 'live'"
      end
    end
    
    raise errors.join(", ") unless errors.empty?
  end
end