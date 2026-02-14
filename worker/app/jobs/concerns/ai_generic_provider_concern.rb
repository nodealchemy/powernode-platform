# frozen_string_literal: true

module AiGenericProviderConcern
  extend ActiveSupport::Concern

  private

  # Add provider-specific standardization instructions
  def add_provider_standardization_context(context, provider_type)
    enhanced_context = context.dup

    provider_instructions = case provider_type
    when 'ollama', 'custom'
      build_ollama_standardization_prompt
    when 'openai'
      build_openai_standardization_prompt
    when 'anthropic'
      build_anthropic_standardization_prompt
    else
      build_generic_standardization_prompt
    end

    if provider_instructions.present?
      log_info("Adding standardization instructions", provider_type: provider_type)
      enhanced_context << {
        role: 'system',
        content: provider_instructions
      }
    end

    enhanced_context
  end

  def build_ollama_standardization_prompt
    <<~PROMPT
      OLLAMA PROVIDER STANDARDIZATION:
      - Provide direct, factual responses without unnecessary preambles
      - Do not include phrases like "I'm ready to help" or "I can assist you"
      - Focus on delivering the specific content or analysis requested
      - Use clear, structured formatting when presenting information
      - Avoid meta-commentary about your capabilities or limitations
      - If the request is for research, provide actual research findings
      - If the request is for content creation, provide the actual content
      - Be concise but comprehensive in your responses
      - Use bullet points or numbered lists for multiple items when appropriate
    PROMPT
  end

  def build_openai_standardization_prompt
    <<~PROMPT
      OPENAI PROVIDER STANDARDIZATION:
      - Provide direct, actionable responses to the specific request
      - Focus on delivering concrete results rather than explanations of what you could do
      - Use structured formatting to organize complex information
      - Be thorough but avoid unnecessary verbosity
      - When asked for research, provide specific facts and data points
      - When asked for content, deliver complete, ready-to-use material
    PROMPT
  end

  def build_anthropic_standardization_prompt
    <<~PROMPT
      ANTHROPIC PROVIDER STANDARDIZATION:
      - Deliver comprehensive, well-structured responses
      - Provide specific, actionable information based on the request
      - Use clear organization and formatting for complex topics
      - Focus on practical, useful output rather than theoretical possibilities
      - When generating content, ensure it's complete and immediately usable
    PROMPT
  end

  def build_generic_standardization_prompt
    <<~PROMPT
      PROVIDER STANDARDIZATION:
      - Respond directly to the specific request without unnecessary introductions
      - Provide concrete, actionable information
      - Use clear formatting and structure
      - Focus on delivering the requested content or analysis
      - Be comprehensive but concise
    PROMPT
  end

  def call_generic_provider(provider, credentials, prompt, context)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']

    # Extract provider configuration
    api_endpoint = provider['api_endpoint'] || decrypted_creds['api_endpoint'] || decrypted_creds['base_url']
    return { success: false, error: "No API endpoint configured for provider #{provider['name']}" } unless api_endpoint.present?

    # Determine auth method and headers
    headers = build_generic_auth_headers(provider, decrypted_creds)
    headers['Content-Type'] = 'application/json'
    headers['Accept'] = 'application/json'

    # Build request body based on provider configuration
    request_body = build_generic_request_body(provider, decrypted_creds, prompt, context)

    # Determine model
    agent = @agent_execution&.dig('ai_agent')
    model = agent&.dig('configuration', 'model') ||
            decrypted_creds['model'] ||
            provider.dig('configuration', 'default_model') ||
            'default'

    log_info("Calling generic AI provider",
      provider_name: provider['name'],
      api_endpoint: api_endpoint,
      model: model
    )

    begin
      # Make the API request
      timeout = provider.dig('configuration', 'timeout') || 120
      response = make_http_request(
        api_endpoint,
        method: :post,
        headers: headers,
        body: request_body.to_json,
        timeout: timeout
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i >= 200 && response.code.to_i < 300
        data = JSON.parse(response.body)

        # Extract response based on provider's response mapping
        extracted_response = extract_generic_response(provider, data)

        if extracted_response[:content].present?
          {
            success: true,
            response: extracted_response[:content],
            model: model,
            metadata: {
              tokens_used: extracted_response[:tokens_used] || 0,
              prompt_tokens: extracted_response[:prompt_tokens] || 0,
              response_time_ms: response_time,
              provider_response: data
            },
            cost: calculate_generic_cost(provider, decrypted_creds, extracted_response)
          }
        else
          { success: false, error: "Empty response from provider #{provider['name']}" }
        end
      else
        error_data = JSON.parse(response.body) rescue { 'message' => response.body }
        error_message = extract_generic_error(provider, error_data) || "API error: #{response.code}"
        { success: false, error: "#{provider['name']} API error: #{error_message}" }
      end

    rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
      log_error("Generic provider timeout", e)
      { success: false, error: "#{provider['name']} connection timeout: #{e.message}" }
    rescue JSON::ParserError => e
      log_error("Failed to parse provider response", e)
      { success: false, error: "Invalid JSON response from #{provider['name']}" }
    rescue StandardError => e
      log_error("Generic provider error", e)
      { success: false, error: "#{provider['name']} connection failed: #{e.message}" }
    end
  end

  def build_generic_auth_headers(provider, credentials)
    headers = {}
    auth_type = provider.dig('configuration', 'auth_type') || credentials['auth_type'] || 'api_key'

    case auth_type.to_s.downcase
    when 'api_key', 'apikey'
      api_key = credentials['api_key']
      header_name = provider.dig('configuration', 'api_key_header') || 'Authorization'
      header_prefix = provider.dig('configuration', 'api_key_prefix') || 'Bearer'

      if api_key.present?
        if header_prefix.present?
          headers[header_name] = "#{header_prefix} #{api_key}"
        else
          headers[header_name] = api_key
        end
      end

    when 'bearer', 'bearer_token'
      token = credentials['api_key'] || credentials['access_token'] || credentials['bearer_token']
      headers['Authorization'] = "Bearer #{token}" if token.present?

    when 'basic', 'basic_auth'
      username = credentials['username'] || credentials['api_key']
      password = credentials['password'] || credentials['api_secret']
      if username.present?
        encoded = Base64.strict_encode64("#{username}:#{password}")
        headers['Authorization'] = "Basic #{encoded}"
      end

    when 'custom_header'
      custom_header_name = provider.dig('configuration', 'custom_header_name')
      custom_header_value = credentials['api_key'] || credentials['custom_header_value']
      if custom_header_name.present? && custom_header_value.present?
        headers[custom_header_name] = custom_header_value
      end

    when 'oauth', 'oauth2'
      access_token = credentials['access_token']
      headers['Authorization'] = "Bearer #{access_token}" if access_token.present?
    end

    # Add any custom headers from provider configuration
    custom_headers = provider.dig('configuration', 'custom_headers') || {}
    headers.merge!(custom_headers)

    headers
  end

  def build_generic_request_body(provider, credentials, prompt, context)
    # Get the request format from provider configuration
    request_format = provider.dig('configuration', 'request_format') || 'openai'
    model = @agent_execution&.dig('ai_agent', 'configuration', 'model') ||
            credentials['model'] ||
            provider.dig('configuration', 'default_model')

    case request_format.to_s.downcase
    when 'openai', 'openai_compatible'
      messages = context.dup
      messages << { role: 'user', content: prompt }
      {
        model: model,
        messages: messages,
        max_tokens: provider.dig('configuration', 'max_tokens') || 2000,
        temperature: provider.dig('configuration', 'temperature') || 0.7
      }

    when 'anthropic', 'claude'
      system_message = context.find { |m| m[:role] == 'system' }&.dig(:content)
      user_messages = context.reject { |m| m[:role] == 'system' } + [{ role: 'user', content: prompt }]
      {
        model: model,
        max_tokens: provider.dig('configuration', 'max_tokens') || 2000,
        system: system_message,
        messages: user_messages
      }

    when 'ollama'
      messages = context.dup
      messages << { role: 'user', content: prompt }
      {
        model: model,
        messages: messages,
        stream: false
      }

    when 'simple', 'text'
      {
        prompt: prompt,
        model: model,
        max_tokens: provider.dig('configuration', 'max_tokens') || 2000
      }

    when 'custom'
      template = provider.dig('configuration', 'request_template') || {}
      deep_render_template(template, {
        'prompt' => prompt,
        'model' => model,
        'messages' => context + [{ role: 'user', content: prompt }],
        'system' => context.find { |m| m[:role] == 'system' }&.dig(:content) || ''
      })

    else
      messages = context.dup
      messages << { role: 'user', content: prompt }
      {
        model: model,
        messages: messages,
        max_tokens: 2000
      }
    end
  end

  def deep_render_template(template, variables)
    case template
    when Hash
      template.transform_values { |v| deep_render_template(v, variables) }
    when Array
      template.map { |v| deep_render_template(v, variables) }
    when String
      rendered = template.dup
      variables.each do |key, value|
        rendered.gsub!("{{#{key}}}", value.to_s)
        rendered.gsub!("{#{key}}", value.to_s)
      end
      rendered
    else
      template
    end
  end

  def extract_generic_response(provider, response_data)
    response_format = provider.dig('configuration', 'response_format') || 'openai'

    case response_format.to_s.downcase
    when 'openai', 'openai_compatible'
      {
        content: response_data.dig('choices', 0, 'message', 'content'),
        tokens_used: response_data.dig('usage', 'total_tokens'),
        prompt_tokens: response_data.dig('usage', 'prompt_tokens')
      }

    when 'anthropic', 'claude'
      {
        content: response_data.dig('content', 0, 'text'),
        tokens_used: response_data.dig('usage', 'output_tokens'),
        prompt_tokens: response_data.dig('usage', 'input_tokens')
      }

    when 'ollama'
      {
        content: response_data.dig('message', 'content'),
        tokens_used: response_data['eval_count'],
        prompt_tokens: response_data['prompt_eval_count']
      }

    when 'simple', 'text'
      {
        content: response_data['text'] || response_data['completion'] || response_data['response'] || response_data['output'],
        tokens_used: response_data['tokens_used'] || response_data['total_tokens'],
        prompt_tokens: response_data['prompt_tokens']
      }

    when 'custom'
      content_path = provider.dig('configuration', 'response_content_path') || 'choices.0.message.content'
      tokens_path = provider.dig('configuration', 'response_tokens_path') || 'usage.total_tokens'

      {
        content: dig_path(response_data, content_path),
        tokens_used: dig_path(response_data, tokens_path),
        prompt_tokens: dig_path(response_data, provider.dig('configuration', 'response_prompt_tokens_path'))
      }

    else
      content = response_data.dig('choices', 0, 'message', 'content') ||
                response_data.dig('message', 'content') ||
                response_data.dig('content', 0, 'text') ||
                response_data['text'] ||
                response_data['response'] ||
                response_data['output']

      {
        content: content,
        tokens_used: response_data.dig('usage', 'total_tokens') || response_data['tokens_used'],
        prompt_tokens: response_data.dig('usage', 'prompt_tokens')
      }
    end
  end

  def dig_path(data, path)
    return nil unless path.present? && data.is_a?(Hash)

    path.to_s.split('.').reduce(data) do |obj, key|
      return nil unless obj

      if key =~ /^\d+$/
        obj.is_a?(Array) ? obj[key.to_i] : nil
      else
        obj.is_a?(Hash) ? obj[key] : nil
      end
    end
  end

  def extract_generic_error(provider, error_data)
    error_path = provider.dig('configuration', 'error_message_path') || 'error.message'

    # Try common error paths
    dig_path(error_data, error_path) ||
      error_data.dig('error', 'message') ||
      error_data.dig('error') ||
      error_data['message'] ||
      error_data['detail']
  end
end
