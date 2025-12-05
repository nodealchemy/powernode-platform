# frozen_string_literal: true

class AiConversationProcessingJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_conversations', retry: 3

  def execute(conversation_id, message_id, options = {})
    @conversation = find_conversation(conversation_id)
    return unless @conversation

    @user_message = find_message(message_id)
    return unless @user_message

    @realtime = options['realtime'] || false
    @channel_id = options['channel_id']

    # Create AI response message placeholder
    ai_message = create_ai_message_placeholder

    begin
      # Broadcast processing start
      broadcast_processing_status('processing')

      # Get AI response using provider service
      response = process_ai_response
      
      # Update AI message with response
      update_ai_message(ai_message, response)

      # Reload the message to get the updated content
      ai_message = find_message(ai_message['id']) if ai_message

      # Broadcast completion with updated content
      broadcast_ai_response(ai_message)
      broadcast_processing_status('complete')

      # Update conversation metadata
      update_conversation_metadata(response)

      # Record usage metrics
      record_usage_metrics(response)

    rescue StandardError => e
      handle_processing_error(ai_message, e)
    end
  end

  private

  def find_conversation(conversation_id)
    response = backend_api_get("/api/v1/ai/conversations/#{conversation_id}")
    return nil unless response['success']
    
    response['data']['conversation']
  end

  def find_message(message_id)
    response = backend_api_get("/api/v1/ai/conversations/#{@conversation['id']}/messages/#{message_id}")
    return nil unless response['success']

    response['data']['message']
  end

  def create_ai_message_placeholder
    payload = {
      message: {
        role: 'assistant',
        content: 'Processing your request...',
        message_type: 'text'
        # user_id deliberately omitted - should be nil for assistant messages
      }
    }

    response = backend_api_post("/api/v1/ai/conversations/#{@conversation['id']}/messages", payload)
    response['data']['message'] if response['success']
  end

  def process_ai_response
    agent = @conversation['ai_agent']
    provider = @conversation['ai_provider']

    log_info("[WORKER] [DEBUG] Starting AI response processing")
    log_info("[WORKER] [DEBUG] Agent present: #{agent.present?}")
    log_info("[WORKER] [DEBUG] Provider present: #{provider.present?}")
    log_info("[WORKER] [DEBUG] Provider ID: #{provider&.dig('id')}")

    # Validate required data
    if !agent
      log_error("[WORKER] [ERROR] Conversation missing AI agent data")
      return generate_error_response('Conversation missing AI agent data')
    end

    if !provider
      log_error("[WORKER] [ERROR] Conversation missing AI provider data")
      return generate_error_response('Conversation missing AI provider data')
    end

    if !provider&.dig('id')
      log_error("[WORKER] [ERROR] AI provider data incomplete - missing ID")
      return generate_error_response('AI provider data incomplete - missing ID')
    end

    # Get provider credentials
    log_info("[WORKER] [DEBUG] Fetching credentials for provider #{provider['id']}")
    credentials_response = backend_api_get("/api/v1/ai/credentials", {
      provider_id: provider['id'],
      default_only: true,
      active: true
    })

    log_info("[WORKER] [DEBUG] Credentials response success: #{credentials_response['success']}")
    return generate_error_response('No active credentials found') unless credentials_response['success']

    credentials = credentials_response['data']['credentials'].first
    log_info("[WORKER] [DEBUG] Credentials found: #{credentials ? 'Yes' : 'No'}")
    return generate_error_response('No default credential available') unless credentials

    # Build conversation context
    context = build_conversation_context

    # Call AI provider service
    log_info("[WORKER] [DEBUG] About to call AI provider service")
    ai_service_response = call_ai_provider_service(
      provider,
      credentials,
      context,
      @user_message['content']
    )

    log_info("[WORKER] [DEBUG] AI service response: #{ai_service_response.inspect}")
    return ai_service_response if ai_service_response['error']

    {
      content: ai_service_response[:response] || ai_service_response['response'],
      metadata: {
        provider_id: provider['id'],
        model_used: ai_service_response[:model] || ai_service_response['model'],
        tokens_used: (ai_service_response[:usage] || ai_service_response['usage'])&.dig('total_tokens') || 0,
        response_time_ms: ai_service_response[:response_time_ms] || ai_service_response['response_time_ms'] || 0,
        cost_estimate: calculate_cost_estimate(ai_service_response),
        processing_complete: true,
        completed_at: Time.current.iso8601
      }
    }
  end

  def build_conversation_context
    # Get recent messages for context
    messages_response = backend_api_get("/api/v1/ai/conversations/#{@conversation['id']}/messages", {
      limit: 20,
      order: 'desc'
    })

    return [] unless messages_response['success']

    messages = messages_response['data']['messages'].reverse
    
    # Format messages for AI context
    messages.map do |msg|
      {
        role: msg['sender_type'] == 'user' ? 'user' : 'assistant',
        content: msg['content'],
        timestamp: msg['created_at']
      }
    end
  end

  def call_ai_provider_service(provider, credentials, context, user_input)
    # Route based on provider_type for flexibility, with fallback to slug-based routing
    provider_type = provider['provider_type']&.downcase
    provider_slug = provider['slug']
    provider_name = provider['name']

    log_info("[WORKER] [DEBUG] Provider routing - Type: #{provider_type}, Slug: #{provider_slug}, Name: #{provider_name}")

    case provider_type
    when 'openai'
      log_info("[WORKER] [DEBUG] Routing to OpenAI service")
      call_openai_service(credentials, context, user_input)
    when 'anthropic'
      log_info("[WORKER] [DEBUG] Routing to Anthropic service")
      call_anthropic_service(credentials, context, user_input)
    when 'custom'
      # For custom providers, check if they have Ollama-like configuration
      log_info("[WORKER] [DEBUG] Custom provider detected, checking Ollama compatibility")
      if ollama_compatible_provider?(provider, credentials)
        log_info("[WORKER] [DEBUG] Custom provider is Ollama-compatible, routing to Ollama service")
        call_ollama_service(credentials, context, user_input)
      else
        log_info("[WORKER] [DEBUG] Custom provider is not Ollama-compatible, routing to generic service")
        call_generic_provider_service(provider, credentials, context, user_input)
      end
    when 'ollama'
      log_info("[WORKER] [DEBUG] Routing to Ollama service")
      call_ollama_service(credentials, context, user_input)
    else
      # Fallback: Try to determine provider type from configuration or slug
      log_info("[WORKER] [DEBUG] Unknown provider type '#{provider_type}', checking fallback routing")
      if provider['slug']&.include?('ollama') || has_ollama_config?(credentials)
        log_info("[WORKER] [DEBUG] Fallback routing to Ollama service")
        call_ollama_service(credentials, context, user_input)
      else
        log_info("[WORKER] [DEBUG] Fallback routing to generic service")
        call_generic_provider_service(provider, credentials, context, user_input)
      end
    end
  end

  def call_ollama_service(credentials, context, user_input)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return generate_error_response('Failed to decrypt credentials') unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    base_url = decrypted_creds['base_url'] || 'http://localhost:11434'
    model = decrypted_creds['model'] || 'deepseek-r1:latest'

    # Build messages array
    messages = context + [{ role: 'user', content: user_input }]

    # Make API call to Ollama
    begin
      request_url = "#{base_url}/api/chat"
      request_body = {
        model: model,
        messages: messages,
        stream: false
      }

      log_info("[WORKER] [Ollama] Making request to: #{request_url}")
      log_info("[WORKER] [Ollama] Model: #{model}")
      log_info("[WORKER] [Ollama] Messages: #{messages.length} messages")

      response = make_http_request(
        request_url,
        method: :post,
        headers: { 'Content-Type' => 'application/json' },
        body: request_body.to_json,
        timeout: 60
      )

      log_info("[WORKER] [Ollama] Response code: #{response.code}")

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        content = data.dig('message', 'content')
        log_info("[WORKER] [Ollama] Raw response data: #{data.inspect}")
        log_info("[WORKER] [Ollama] Extracted content: #{content ? content[0..100] + '...' : 'nil'}")

        if content && !content.empty?
          success_response = {
            response: content,
            model: model,
            usage: {
              total_tokens: data.dig('eval_count') || 0,
              prompt_tokens: data.dig('prompt_eval_count') || 0
            },
            response_time_ms: response_time
          }
          log_info("[WORKER] [Ollama] SUCCESS: Returning valid content (#{content.length} chars)")
          success_response
        else
          log_error("[WORKER] [Ollama] Content is nil or empty, treating as error")
          log_error("[WORKER] [Ollama] Full response body: #{response.body}")
          generate_error_response("Ollama API error: Content extraction failed - content was nil or empty")
        end
      else
        log_error("[WORKER] [Ollama] HTTP error response: #{response.code}")
        generate_error_response("Ollama API error: #{response.code} - #{response.body}")
      end

    rescue StandardError => e
      generate_error_response("Ollama connection failed: #{e.message}")
    end
  end

  def call_openai_service(credentials, context, user_input)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return generate_error_response('Failed to decrypt credentials') unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    api_key = decrypted_creds['api_key']
    model = decrypted_creds['model'] || 'gpt-3.5-turbo'

    return generate_error_response('OpenAI API key not configured') unless api_key

    # Build messages array
    messages = context + [{ role: 'user', content: user_input }]

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
          max_tokens: 1000
        }.to_json,
        timeout: 60
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        {
          response: data.dig('choices', 0, 'message', 'content') || 'No response generated',
          model: model,
          usage: data['usage'],
          response_time_ms: response_time
        }
      else
        error_data = JSON.parse(response.body) rescue {}
        generate_error_response("OpenAI API error: #{error_data.dig('error', 'message') || response.body}")
      end

    rescue StandardError => e
      generate_error_response("OpenAI connection failed: #{e.message}")
    end
  end

  def call_anthropic_service(credentials, context, user_input)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return generate_error_response('Failed to decrypt credentials') unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    api_key = decrypted_creds['api_key']
    model = decrypted_creds['model'] || 'claude-3-sonnet-20240229'

    return generate_error_response('Anthropic API key not configured') unless api_key

    # Convert context to Anthropic format
    system_message = "You are a helpful AI assistant."
    formatted_messages = format_messages_for_anthropic(context, user_input)

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
          max_tokens: 1000,
          system: system_message,
          messages: formatted_messages
        }.to_json,
        timeout: 60
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        content = data.dig('content', 0, 'text') || 'No response generated'
        
        {
          response: content,
          model: model,
          usage: data['usage'],
          response_time_ms: response_time
        }
      else
        error_data = JSON.parse(response.body) rescue {}
        generate_error_response("Anthropic API error: #{error_data.dig('error', 'message') || response.body}")
      end

    rescue StandardError => e
      generate_error_response("Anthropic connection failed: #{e.message}")
    end
  end

  def call_generic_provider_service(provider, credentials, context, user_input)
    # Generic provider implementation - can be extended for other providers
    generate_error_response("Provider #{provider['name']} not yet implemented")
  end

  def format_messages_for_anthropic(context, user_input)
    # Anthropic expects alternating user/assistant messages
    messages = context.dup
    messages << { role: 'user', content: user_input }
    
    # Ensure alternating pattern
    formatted = []
    messages.each_with_index do |msg, index|
      # Skip system messages or adjust as needed
      next if msg[:role] == 'system'
      
      formatted << {
        role: msg[:role],
        content: msg[:content]
      }
    end
    
    formatted
  end

  def update_ai_message(ai_message, response)
    return unless ai_message

    log_info("[WORKER] [DEBUG] Updating AI message with response: #{response.inspect}")

    # Ensure content is not empty to prevent validation errors
    content = response[:content].presence || response[:text].presence || "I apologize, but I'm unable to generate a response at this time. Please try again later."

    log_info("[WORKER] [DEBUG] Final content: #{content[0..100]}...")

    payload = {
      message: {
        content: content,
        processing_metadata: (ai_message['processing_metadata'] || {}).merge(response[:metadata] || {}),
        error_message: response[:success] == false ? response[:error] : nil
      }
    }

    backend_api_patch("/api/v1/ai/conversations/#{@conversation['id']}/messages/#{ai_message['id']}", payload)
  end

  def update_conversation_metadata(response)
    current_metadata = @conversation&.dig('metadata') || {}

    metadata_update = {
      last_ai_response_at: Time.current.iso8601,
      total_tokens: (current_metadata['total_tokens'] || 0) + (response&.dig(:metadata, :tokens_used) || 0),
      total_cost: (current_metadata['total_cost'] || 0) + (response&.dig(:metadata, :cost_estimate) || 0)
    }

    payload = {
      conversation: {
        metadata: current_metadata.merge(metadata_update)
      }
    }

    backend_api_patch("/api/v1/ai/conversations/#{@conversation['id']}", payload)
  end

  def record_usage_metrics(response)
    # Record usage for analytics - skip if conversation is nil
    return unless @conversation

    usage_data = {
      account_id: @conversation['account_id'],
      provider_id: @conversation&.dig('ai_agent', 'ai_provider', 'id'),
      agent_id: @conversation&.dig('ai_agent', 'id'),
      conversation_id: @conversation['id'],
      tokens_used: response&.dig(:metadata, :tokens_used) || 0,
      cost_estimate: response&.dig(:metadata, :cost_estimate) || 0,
      response_time_ms: response&.dig(:metadata, :response_time_ms) || 0,
      model_used: response&.dig(:metadata, :model_used),
      success: true
    }

    backend_api_post("/api/v1/ai/analytics/usage", { usage: usage_data })
  end

  def broadcast_processing_status(status)
    return unless @realtime && @conversation

    # Make API call to backend to trigger WebSocket broadcast
    backend_api_post("/api/v1/ai/conversations/#{@conversation['id']}/broadcast_status", {
      status: status,
      metadata: { realtime: true, channel_id: @channel_id }
    })
  rescue StandardError => e
    log_error("Failed to broadcast processing status: #{e.message}")
  end

  def broadcast_ai_response(ai_message)
    return unless @realtime && @conversation && ai_message

    # Make API call to backend to trigger WebSocket broadcast
    backend_api_post("/api/v1/ai/conversations/#{@conversation['id']}/broadcast_response", {
      message: ai_message,
      streaming: false,
      metadata: { realtime: true, channel_id: @channel_id }
    })
  rescue StandardError => e
    log_error("Failed to broadcast AI response: #{e.message}")
  end

  def handle_processing_error(ai_message, error)
    log_error("AI Conversation Processing failed: #{error.message}")
    log_error(error.backtrace.join("\n"))

    # Update AI message with error
    if ai_message
      error_payload = {
        message: {
          content: "I apologize, but I encountered an error while processing your message. Please try again.",
          processing_metadata: (ai_message['processing_metadata'] || {}).merge({
            error: true,
            error_message: error.message,
            processing_complete: true,
            failed_at: Time.current.iso8601
          })
        }
      }

      backend_api_patch("/api/v1/ai/conversations/#{@conversation['id']}/messages/#{ai_message['id']}", error_payload)
    end

    # Broadcast error status
    broadcast_processing_status('error')

    # Record error metrics
    usage_data = {
      account_id: @conversation['account_id'],
      provider_id: @conversation['ai_provider']&.dig('id'),
      agent_id: @conversation['ai_agent']&.dig('id'),
      conversation_id: @conversation['id'],
      error_message: error.message,
      success: false
    }

    backend_api_post("/api/v1/ai/analytics/usage", { usage: usage_data })

    # Re-raise for retry mechanism
    raise error
  end

  def calculate_cost_estimate(response)
    # Basic cost calculation - can be enhanced based on provider pricing
    tokens_used = response['usage']&.dig('total_tokens') || 0
    
    # Rough estimate: $0.002 per 1K tokens (adjust based on actual provider pricing)
    (tokens_used / 1000.0) * 0.002
  end

  def generate_error_response(message)
    log_error("AI processing error: #{message}")
    {
      error: true,
      message: message,
      response: "I apologize, but I'm currently unable to process your request due to a technical issue. Please try again later.",
      metadata: {
        error: true,
        error_message: message,
        tokens_used: 0,
        cost_estimate: 0,
        processing_complete: true,
        failed_at: Time.current.iso8601
      }
    }
  end

  # Helper methods for provider type detection
  def ollama_compatible_provider?(provider, credentials)
    # Check if provider has Ollama-like characteristics
    provider_name = provider['name']&.downcase || ''
    provider_slug = provider['slug']&.downcase || ''

    log_info("[WORKER] [DEBUG] Checking Ollama compatibility - Name: #{provider_name}, Slug: #{provider_slug}")

    # Check if name or slug suggests Ollama
    if provider_name.include?('ollama') || provider_slug.include?('ollama')
      log_info("[WORKER] [DEBUG] Provider name/slug indicates Ollama compatibility")
      return true
    end

    # Check credentials for Ollama-specific configuration
    config_check = has_ollama_config?(credentials)
    log_info("[WORKER] [DEBUG] Ollama config check result: #{config_check}")
    config_check
  end

  def has_ollama_config?(credentials)
    return false unless credentials

    # Decrypt and check for Ollama-specific configuration patterns
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return false unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']

    # Check for Ollama-specific configuration keys
    base_url = decrypted_creds['base_url'] || ''
    api_endpoint = decrypted_creds['api_endpoint'] || ''

    # Ollama typically uses local URLs with port 11434 or /api/chat endpoint
    return true if base_url.include?(':11434') || api_endpoint.include?('/api/chat')
    return true if base_url.include?('localhost') && decrypted_creds['model']

    false
  rescue StandardError => e
    log_warn("Failed to check Ollama configuration: #{e.message}")
    false
  end
end