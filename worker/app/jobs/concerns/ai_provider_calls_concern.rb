# frozen_string_literal: true

module AiProviderCallsConcern
  extend ActiveSupport::Concern

  private

  def call_ollama_provider(credentials, prompt, context)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    # Use provider's api_endpoint if available, otherwise use base_url from credentials
    provider = @agent_execution&.dig('ai_provider')
    base_url = if provider && provider['api_endpoint'].present?
                 # Extract base URL from provider endpoint (remove path)
                 uri = URI.parse(provider['api_endpoint'])
                 "#{uri.scheme}://#{uri.host}:#{uri.port}"
               else
                 decrypted_creds['base_url'] || 'http://localhost:11434'
               end

    # Use agent-specific model configuration, fall back to credentials, then default
    agent = @agent_execution&.dig('ai_agent')
    model = agent&.dig('configuration', 'model') ||
            decrypted_creds['model'] ||
            ENV.fetch('DEFAULT_AI_MODEL', 'deepseek-r1:1.5b')

    # Build messages array
    messages = context.dup
    messages << { role: 'user', content: prompt }

    # Implement adaptive retry for Ollama timeout issues
    max_retries = 2
    retry_count = 0

    begin
      request_url = "#{base_url}/api/chat"
      request_body = {
        model: model,
        messages: messages,
        stream: false
      }

      # Adaptive timeout: increase timeout on retries
      timeout = 300 + (retry_count * 120) # Start at 5min, add 2min per retry

      log_info("Calling Ollama API",
        url: request_url,
        model: model,
        attempt: retry_count + 1,
        timeout: timeout
      )

      response = make_http_request(
        request_url,
        method: :post,
        headers: { 'Content-Type' => 'application/json' },
        body: request_body.to_json,
        timeout: timeout
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        content = data.dig('message', 'content')

        if content && !content.empty?
          {
            success: true,
            response: content,
            model: model,
            metadata: {
              tokens_used: data.dig('eval_count') || 0,
              prompt_tokens: data.dig('prompt_eval_count') || 0,
              response_time_ms: response_time
            },
            cost: calculate_ollama_cost(data)
          }
        else
          { success: false, error: 'Empty response from Ollama' }
        end
      else
        { success: false, error: "Ollama API error: #{response.code} - #{response.body}" }
      end

    rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
      if retry_count < max_retries
        retry_count += 1
        wait_time = retry_count * 10 # Wait 10s, 20s between retries
        log_info("Ollama timeout, retrying",
          attempt: retry_count,
          wait_time: wait_time,
          error: e.message
        )
        sleep(wait_time)
        retry
      else
        log_error("Ollama timeout after #{max_retries} retries", e)
        { success: false, error: "Ollama connection timeout after #{max_retries} retries: #{e.message}" }
      end
    rescue StandardError => e
      { success: false, error: "Ollama connection failed: #{e.message}" }
    end
  end

  def call_openai_provider(credentials, prompt, context)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    api_key = decrypted_creds['api_key']

    # Use agent-specific model configuration, fall back to credentials, then default
    agent = @agent_execution&.dig('ai_agent')
    model = agent&.dig('configuration', 'model') ||
            decrypted_creds['model'] || 'gpt-4o'

    return { success: false, error: 'OpenAI API key not configured' } unless api_key

    # Build messages array
    messages = context + [{ role: 'user', content: prompt }]

    begin
      response = make_http_request(
        'https://api.openai.com/v1/chat/completions',
        method: :post,
        headers: {
          'Authorization' => "Bearer #{api_key}",
          'Content-Type' => 'application/json'
        },
        body: {
          model: model,
          messages: messages,
          max_tokens: 2000
        }.to_json,
        timeout: 90
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        {
          success: true,
          response: data.dig('choices', 0, 'message', 'content') || 'No response generated',
          model: model,
          metadata: {
            tokens_used: data.dig('usage', 'total_tokens') || 0,
            prompt_tokens: data.dig('usage', 'prompt_tokens') || 0,
            response_time_ms: response_time
          },
          cost: calculate_openai_cost(data, model)
        }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false, error: "OpenAI API error: #{error_data.dig('error', 'message') || response.body}" }
      end

    rescue StandardError => e
      { success: false, error: "OpenAI connection failed: #{e.message}" }
    end
  end

  def call_anthropic_provider(credentials, prompt, context)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    api_key = decrypted_creds['api_key']

    # Use agent-specific model configuration, fall back to credentials, then default
    agent = @agent_execution&.dig('ai_agent')
    model = agent&.dig('configuration', 'model') ||
            decrypted_creds['model'] || 'claude-sonnet-4-5-20241022'

    return { success: false, error: 'Anthropic API key not configured' } unless api_key

    # Format for Anthropic API
    system_message = context.find { |m| m[:role] == 'system' }&.dig(:content) || "You are a helpful AI assistant."
    user_messages = context.reject { |m| m[:role] == 'system' } + [{ role: 'user', content: prompt }]

    begin
      response = make_http_request(
        'https://api.anthropic.com/v1/messages',
        method: :post,
        headers: {
          'x-api-key' => api_key,
          'Content-Type' => 'application/json',
          'anthropic-version' => '2023-06-01'
        },
        body: {
          model: model,
          max_tokens: 2000,
          system: system_message,
          messages: user_messages
        }.to_json,
        timeout: 90
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        content = data.dig('content', 0, 'text') || 'No response generated'

        {
          success: true,
          response: content,
          model: model,
          metadata: {
            tokens_used: data.dig('usage', 'output_tokens') || 0,
            prompt_tokens: data.dig('usage', 'input_tokens') || 0,
            response_time_ms: response_time
          },
          cost: calculate_anthropic_cost(data, model)
        }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false, error: "Anthropic API error: #{error_data.dig('error', 'message') || response.body}" }
      end

    rescue StandardError => e
      { success: false, error: "Anthropic connection failed: #{e.message}" }
    end
  end

  # Helper methods for provider detection
  def ollama_compatible_provider?(provider, credentials)
    provider_name = provider['name']&.downcase || ''
    provider_slug = provider['slug']&.downcase || ''

    # Check if name or slug suggests Ollama
    return true if provider_name.include?('ollama') || provider_slug.include?('ollama')

    # Check credentials for Ollama-specific configuration
    has_ollama_config?(credentials)
  end

  def has_ollama_config?(credentials)
    return false unless credentials

    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return false unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    base_url = decrypted_creds['base_url'] || ''

    # Ollama typically uses local URLs with port 11434
    base_url.include?(':11434') || (base_url.include?('localhost') && decrypted_creds['model'])
  rescue StandardError
    false
  end
end
