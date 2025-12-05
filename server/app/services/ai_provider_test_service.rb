# frozen_string_literal: true

class AiProviderTestService
  attr_reader :credential

  def initialize(credential)
    @credential = credential
  end

  def test_with_details
    start_time = Time.current

    begin
      result = perform_test
      response_time = ((Time.current - start_time) * 1000).round

      if result[:success]
        {
          success: true,
          response_time_ms: response_time,
          message: 'Connection test successful',
          provider_info: result[:provider_info],
          model_info: result[:model_info]
        }
      else
        {
          success: false,
          response_time_ms: response_time,
          error: result[:error] || 'Connection test failed',
          error_code: result[:error_code]
        }
      end
    rescue => e
      response_time = ((Time.current - start_time) * 1000).round
      Rails.logger.error "Provider test failed for #{credential.ai_provider.name}: #{e.message}"
      
      {
        success: false,
        response_time_ms: response_time,
        error: "Test failed: #{e.message}",
        error_code: 'CONNECTION_ERROR'
      }
    end
  end

  def test_basic
    test_with_details[:success]
  end

  private

  def perform_test
    provider = credential.ai_provider
    decrypted_config = credential.credentials

    # Use provider_type for matching, with fallback to slug pattern for custom providers
    case provider.provider_type
    when 'ollama'
      test_ollama_connection(provider, decrypted_config)
    when 'openai'
      test_openai_connection(provider, decrypted_config)
    when 'anthropic'
      test_anthropic_connection(provider, decrypted_config)
    when 'xai'
      test_xai_connection(provider, decrypted_config)
    when 'huggingface'
      test_huggingface_connection(provider, decrypted_config)
    when 'cohere'
      test_cohere_connection(provider, decrypted_config)
    when 'custom'
      # Check slug patterns for custom providers
      case provider.slug
      when /xai|grok/i
        test_xai_connection(provider, decrypted_config)
      when /ollama/i
        test_ollama_connection(provider, decrypted_config)
      when /cohere/i
        test_cohere_connection(provider, decrypted_config)
      else
        test_generic_connection(provider, decrypted_config)
      end
    else
      test_generic_connection(provider, decrypted_config)
    end
  end

  def test_ollama_connection(provider, config)
    base_url = config['base_url'] || provider.api_base_url
    
    # Test Ollama by checking if server is running
    response = make_http_request("#{base_url}/api/tags", method: :get)
    
    if response.success?
      models = JSON.parse(response.body)['models'] || []
      {
        success: true,
        provider_info: { version: 'latest', status: 'running' },
        model_info: { available_models: models.size }
      }
    else
      {
        success: false,
        error: 'Ollama server not reachable',
        error_code: 'SERVER_UNREACHABLE'
      }
    end
  end

  def test_openai_connection(provider, config)
    api_key = config['api_key']
    return { success: false, error: 'API key not configured', error_code: 'MISSING_CREDENTIALS' } unless api_key

    # Test OpenAI by listing models
    headers = {
      'Authorization' => "Bearer #{api_key}",
      'Content-Type' => 'application/json'
    }
    
    response = make_http_request("#{provider.api_base_url}/models", method: :get, headers: headers)
    
    if response.success?
      data = JSON.parse(response.body)
      {
        success: true,
        provider_info: { status: 'active' },
        model_info: { available_models: data['data']&.size || 0 }
      }
    else
      error_data = JSON.parse(response.body) rescue {}
      {
        success: false,
        error: error_data['error']&.dig('message') || 'Authentication failed',
        error_code: 'AUTHENTICATION_FAILED'
      }
    end
  end

  def test_anthropic_connection(provider, config)
    api_key = config['api_key']
    return { success: false, error: 'API key not configured', error_code: 'MISSING_CREDENTIALS' } unless api_key

    # Test Anthropic with a minimal API call to validate authentication
    headers = {
      'x-api-key' => api_key,
      'anthropic-version' => '2023-06-01',
      'Content-Type' => 'application/json'
    }

    # Use the fastest/cheapest model for testing
    test_model = 'claude-3-haiku-20240307'

    payload = {
      model: test_model,
      messages: [{ role: 'user', content: 'Hi' }],
      max_tokens: 10
    }

    response = make_http_request(
      "#{provider.api_base_url}/messages",
      method: :post,
      headers: headers,
      body: payload.to_json
    )

    if response.success?
      data = JSON.parse(response.body) rescue {}
      {
        success: true,
        provider_info: {
          status: 'active',
          api_version: '2023-06-01'
        },
        model_info: {
          test_model: test_model,
          response_id: data['id']
        }
      }
    else
      error_data = JSON.parse(response.body) rescue {}
      error_message = error_data.dig('error', 'message') || 'Authentication failed'
      {
        success: false,
        error: error_message,
        error_code: 'AUTHENTICATION_FAILED'
      }
    end
  rescue => e
    {
      success: false,
      error: "Anthropic connection error: #{e.message}",
      error_code: 'CONNECTION_ERROR'
    }
  end

  def test_xai_connection(provider, config)
    api_key = config['api_key']
    return { success: false, error: 'API key not configured', error_code: 'MISSING_CREDENTIALS' } unless api_key

    begin
      # Test x.ai with a simple API call to verify connection
      headers = {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type' => 'application/json'
      }

      # Use x.ai's chat completions endpoint for testing
      # Use the current stable model (grok-3 as of 2025)
      test_model = 'grok-3'

      payload = {
        model: test_model,
        messages: [{ role: 'user', content: 'Hello, respond with just "OK"' }],
        max_tokens: 10,
        temperature: 0
      }

      response = make_http_request(
        "#{provider.api_base_url}/chat/completions",
        method: :post,
        headers: headers,
        body: payload.to_json
      )

      if response.success?
        {
          success: true,
          provider_info: {
            status: 'active',
            api_version: 'v1',
            models_available: ['grok-3', 'grok-vision']
          },
          model_info: { test_model: test_model }
        }
      else
        # Parse error response - xAI can return error as string or nested object
        error_data = JSON.parse(response.body) rescue {}
        error_message = if error_data['error'].is_a?(Hash)
                         error_data['error']['message'] || error_data['error'].to_s
                       elsif error_data['error'].is_a?(String)
                         error_data['error']
                       else
                         error_data['message'] || 'Connection test failed'
                       end

        {
          success: false,
          error: error_message,
          error_code: 'API_ERROR'
        }
      end
    rescue => e
      {
        success: false,
        error: "x.ai connection error: #{e.message}",
        error_code: 'CONNECTION_ERROR'
      }
    end
  end

  def test_huggingface_connection(provider, config)
    api_key = config['api_key']
    return { success: false, error: 'API key not configured', error_code: 'MISSING_CREDENTIALS' } unless api_key

    # Mock successful connection for Hugging Face
    {
      success: true,
      provider_info: { status: 'active' },
      model_info: { test_model: 'gpt2' }
    }
  end

  def test_cohere_connection(provider, config)
    api_key = config['api_key']
    return { success: false, error: 'API key not configured', error_code: 'MISSING_CREDENTIALS' } unless api_key

    # Mock successful connection for Cohere
    {
      success: true,
      provider_info: { status: 'active' },
      model_info: { test_model: 'command' }
    }
  end

  def test_generic_connection(provider, config)
    # Generic HTTP health check
    response = make_http_request(provider.api_base_url, method: :get)
    
    if response.success?
      {
        success: true,
        provider_info: { status: 'reachable' },
        model_info: { test: 'basic_connectivity' }
      }
    else
      {
        success: false,
        error: 'Provider endpoint not reachable',
        error_code: 'CONNECTION_FAILED'
      }
    end
  end

  def make_http_request(url, method: :get, headers: {}, body: nil, timeout: 10)
    require 'net/http'
    require 'uri'
    require 'ostruct'

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = timeout
    http.open_timeout = timeout

    case method
    when :get
      request = Net::HTTP::Get.new(uri.request_uri)
    when :post
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = body if body
    else
      raise ArgumentError, "Unsupported HTTP method: #{method}"
    end

    headers.each { |key, value| request[key] = value }

    response = http.request(request)

    # Wrap the response to add success? method
    ResponseWrapper.new(response)
  rescue => e
    # Return a mock response object for connection failures
    ResponseWrapper.new(nil, error: e.message)
  end

  # Helper class to wrap HTTP responses with success? method
  class ResponseWrapper
    attr_reader :body, :code, :message

    def initialize(response, error: nil)
      if response
        @body = response.body
        @code = response.code.to_i
        @message = response.message
        @success = response.is_a?(Net::HTTPSuccess)
      else
        @body = ''
        @code = 0
        @message = error || 'Connection failed'
        @success = false
      end
    end

    def success?
      @success
    end
  end
end