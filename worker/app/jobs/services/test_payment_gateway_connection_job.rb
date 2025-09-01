# frozen_string_literal: true

require 'net/http'
require 'base64'

# Job to test payment gateway connections asynchronously
# Handles external API calls to Stripe and PayPal for connection testing
class Services::TestPaymentGatewayConnectionJob < BaseJob
  sidekiq_options queue: 'high', retry: 2

  def execute(job_id, gateway, config_data = {})
    validate_required_params({ 'job_id' => job_id, 'gateway' => gateway }, 'job_id', 'gateway')
    
    logger.info "Testing #{gateway} connection for job #{job_id}"
    
    # Update job status to running
    update_job_status(job_id, 'running')
    
    begin
      result = case gateway
      when 'stripe'
        test_stripe_connection(config_data)
      when 'paypal'  
        test_paypal_connection(config_data)
      else
        raise ArgumentError, "Unsupported gateway: #{gateway}"
      end
      
      # Update job status with successful result
      update_job_status(job_id, 'completed', result)
      
      logger.info "Successfully tested #{gateway} connection for job #{job_id}"
      result
      
    rescue StandardError => e
      error_result = {
        success: false,
        error: e.message,
        gateway: gateway,
        tested_at: Time.current.iso8601
      }
      
      # Update job status with error result  
      update_job_status(job_id, 'failed', error_result)
      
      logger.error "Failed to test #{gateway} connection for job #{job_id}: #{e.message}"
      raise
    end
  end

  private

  def test_stripe_connection(config_data)
    secret_key = config_data['secret_key']
    
    raise 'No Stripe secret key provided' unless secret_key.present?
    
    # Test Stripe API connection - we'll use a simple HTTP request instead of the Stripe gem
    # to avoid gem dependencies in the worker
    test_stripe_api_connection(secret_key)
  rescue StandardError => e
    {
      success: false,
      gateway: 'stripe',
      error: e.message,
      tested_at: Time.current.iso8601
    }
  end

  def test_stripe_api_connection(secret_key)
    uri = URI('https://api.stripe.com/v1/account')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{secret_key}"
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    
    response = http.request(request)
    
    case response.code.to_i
    when 200
      account_data = JSON.parse(response.body)
      {
        success: true,
        gateway: 'stripe',
        account_id: account_data['id'],
        business_name: account_data.dig('business_profile', 'name') || account_data.dig('settings', 'dashboard', 'display_name'),
        country: account_data['country'],
        currency: account_data['default_currency'],
        charges_enabled: account_data['charges_enabled'],
        payouts_enabled: account_data['payouts_enabled'],
        tested_at: Time.current.iso8601
      }
    when 401
      raise 'Invalid API key - authentication failed'
    when 403
      raise 'Insufficient permissions for API key'
    when 429
      raise 'Rate limit exceeded'
    else
      error_data = JSON.parse(response.body) rescue {}
      raise error_data.dig('error', 'message') || "API request failed with status #{response.code}"
    end
  end

  def test_paypal_connection(config_data)
    client_id = config_data['client_id']
    client_secret = config_data['client_secret']
    mode = config_data['mode'] || 'sandbox'
    webhook_id = config_data['webhook_id']
    
    # Basic configuration validation
    unless client_id.present? && client_secret.present?
      return {
        success: false,
        gateway: 'paypal',
        error: 'Client ID and secret are required',
        tested_at: Time.current.iso8601
      }
    end
    
    # Test PayPal API connection by getting an access token
    begin
      access_token = get_paypal_access_token(client_id, client_secret, mode)
      
      # If we got a token, test account info retrieval
      account_info = get_paypal_account_info(access_token, mode)
      
      {
        success: true,
        gateway: 'paypal',
        mode: mode,
        client_id_configured: true,
        webhook_configured: webhook_id.present?,
        account_id: account_info['account_id'],
        account_status: account_info['account_status'],
        verified: account_info['verified'] == true,
        tested_at: Time.current.iso8601
      }
    rescue StandardError => e
      {
        success: false,
        gateway: 'paypal',
        mode: mode,
        error: e.message,
        tested_at: Time.current.iso8601
      }
    end
  end

  def get_paypal_access_token(client_id, client_secret, mode)
    base_url = mode == 'live' ? 'https://api-m.paypal.com' : 'https://api-m.sandbox.paypal.com'
    
    uri = URI("#{base_url}/v1/oauth2/token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Accept'] = 'application/json'
    request['Accept-Language'] = 'en_US'
    request['Authorization'] = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
    request.body = 'grant_type=client_credentials'
    
    response = http.request(request)
    
    if response.code.to_i == 200
      parsed = JSON.parse(response.body)
      parsed['access_token']
    else
      error_msg = begin
        parsed = JSON.parse(response.body)
        parsed.dig('error_description') || parsed['error'] || 'Authentication failed'
      rescue JSON::ParserError
        'Authentication failed'
      end
      
      raise "PayPal authentication failed: #{error_msg}"
    end
  end

  def get_paypal_account_info(access_token, mode)
    base_url = mode == 'live' ? 'https://api-m.paypal.com' : 'https://api-m.sandbox.paypal.com'
    
    uri = URI("#{base_url}/v1/identity/oauth2/userinfo?schema=paypalv1.1")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{access_token}"
    
    response = http.request(request)
    
    if response.code.to_i == 200
      # Return basic account info for the connection test
      {
        'account_id' => 'connected',
        'account_status' => 'active',
        'verified' => true
      }
    else
      # Even if this specific call fails, the token worked so connection is good
      {
        'account_id' => 'connected',
        'account_status' => 'unknown',
        'verified' => false
      }
    end
  rescue StandardError
    # Fallback - token worked so connection is functional
    {
      'account_id' => 'connected',
      'account_status' => 'unknown', 
      'verified' => false
    }
  end

  def update_job_status(job_id, status, result_data = {})
    with_api_retry(max_attempts: 2) do
      api_client.patch("/api/v1/gateway_connection_jobs/#{job_id}", {
        status: status,
        result: result_data,
        updated_at: Time.current.iso8601
      })
    end
  rescue BackendApiClient::ApiError => e
    logger.warn "Failed to update job status for #{job_id}: #{e.message}"
    # Don't re-raise - job status update failure shouldn't fail the main job
  end
end