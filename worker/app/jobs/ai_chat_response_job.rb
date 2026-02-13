# frozen_string_literal: true

# Async chat response generation with streaming broadcast
# Queue: ai_conversations (priority 2)
#
# Receives a conversation_id + message_id, fetches conversation history,
# calls the AI provider with streaming, and broadcasts each token chunk
# via the backend API → ActionCable.
class AiChatResponseJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_conversations', retry: 2

  # Minimum interval (seconds) between streaming chunk broadcasts
  STREAM_BROADCAST_INTERVAL = 0.15

  def execute(conversation_id, message_id, agent_id, account_id)
    validate_required_params(
      { 'conversation_id' => conversation_id, 'message_id' => message_id,
        'agent_id' => agent_id, 'account_id' => account_id },
      'conversation_id', 'message_id', 'agent_id', 'account_id'
    )

    # Idempotency check
    idempotency_key = "chat_response:#{message_id}"
    if already_processed?(idempotency_key)
      log_info("Chat response already processed", message_id: message_id)
      return
    end

    log_info("Starting chat response generation",
      conversation_id: conversation_id,
      message_id: message_id,
      agent_id: agent_id
    )

    @conversation_id = conversation_id
    @message_id = message_id
    start_time = Time.current

    begin
      # Fetch conversation + agent data from backend
      conv_response = backend_api_get("/api/v1/ai/conversations/#{conversation_id}")
      unless conv_response['success']
        broadcast_error(conversation_id, "Failed to fetch conversation")
        return
      end

      agent = fetch_agent(agent_id, account_id)
      return unless agent

      @agent_name = agent['name'] || 'AI Assistant'

      provider = agent['ai_provider'] || agent['provider']
      return broadcast_error(conversation_id, "Agent has no provider configured") unless provider

      # Fetch credentials
      credentials = fetch_credentials(provider['id'])
      return broadcast_error(conversation_id, "No active credentials for provider") unless credentials

      # Build message history
      messages = build_chat_messages(conversation_id, agent)

      # Call AI provider with streaming
      ai_result = call_provider_streaming(provider, credentials, agent, messages)

      duration_ms = ((Time.current - start_time) * 1000).to_i

      if ai_result[:success]
        # Broadcast completion with full message
        broadcast_complete(
          conversation_id,
          message_id,
          ai_result[:content],
          token_count: ai_result[:tokens_used] || 0,
          cost_usd: ai_result[:cost] || 0.0,
          model: ai_result[:model],
          duration_ms: duration_ms
        )

        mark_processed(idempotency_key, ttl: 3600)

        log_info("Chat response completed",
          conversation_id: conversation_id,
          duration_ms: duration_ms,
          tokens: ai_result[:tokens_used],
          cost: ai_result[:cost]
        )
      else
        broadcast_error(conversation_id, ai_result[:error] || "AI provider error")

        log_error("Chat response failed",
          conversation_id: conversation_id,
          error: ai_result[:error]
        )
      end
    rescue StandardError => e
      broadcast_error(conversation_id, "Internal error generating response")
      handle_ai_processing_error(e, {
        conversation_id: conversation_id,
        message_id: message_id,
        agent_id: agent_id
      })
    end
  end

  private

  def fetch_agent(agent_id, _account_id)
    response = backend_api_get("/api/v1/ai/agents/#{agent_id}")

    if response['success']
      response['data']['agent'] || response['data']
    else
      log_error("Failed to fetch agent", agent_id: agent_id)
      broadcast_error(nil, "Agent not found")
      nil
    end
  end

  def fetch_credentials(provider_id)
    response = backend_api_get("/api/v1/ai/credentials", {
      provider_id: provider_id,
      default_only: true,
      active: true
    })

    return nil unless response['success']

    creds = response['data']['credentials']
    creds.is_a?(Array) ? creds.first : creds
  end

  def build_chat_messages(conversation_id, agent)
    # Fetch recent message history
    response = backend_api_get("/api/v1/ai/conversations/#{conversation_id}", {})

    messages = []
    conversation = response['data']['conversation'] if response['success']

    # System prompt from agent
    system_prompt = agent['system_prompt']
    messages << { role: 'system', content: system_prompt } if system_prompt.present?

    # Add recent messages from conversation
    if conversation && conversation['recent_messages'].is_a?(Array)
      conversation['recent_messages'].each do |msg|
        next if msg['role'] == 'system'

        messages << { role: msg['role'], content: msg['content'] }
      end
    end

    messages
  end

  def call_provider_streaming(provider, credentials, agent, messages)
    provider_type = provider['provider_type']&.downcase || 'openai'
    model = agent['model'] || provider['default_model'] || 'gpt-4'
    temperature = agent['temperature'] || 0.7
    max_tokens = agent['max_tokens'] || 2048

    # Decrypt credentials
    decrypt_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    unless decrypt_response['success']
      return { success: false, error: 'Failed to decrypt credentials' }
    end

    api_key = decrypt_response['data']['api_key'] || decrypt_response['data']['decrypted_key']
    base_url = credentials['base_url'] || provider['base_url']

    case provider_type
    when 'openai', 'openai_compatible'
      call_openai_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    when 'anthropic'
      call_anthropic_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    when 'ollama'
      call_ollama_streaming(base_url, model, messages, temperature, max_tokens)
    else
      call_generic(api_key, base_url, model, messages, temperature, max_tokens)
    end
  end

  # =========================================================================
  # STREAMING PROVIDER CALLS
  # =========================================================================

  def call_openai_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    url = "#{base_url || 'https://api.openai.com/v1'}/chat/completions"
    uri = URI(url)

    body = {
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens,
      stream: true
    }.to_json

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{api_key}"
    }

    accumulated = ""
    token_count = 0

    success = stream_sse_request(uri, body, headers) do |event_data|
      # OpenAI streaming: {"choices":[{"delta":{"content":"token"}}]}
      delta = event_data.dig('choices', 0, 'delta', 'content')
      if delta
        accumulated += delta
        token_count += 1
      end

      # Check for usage in final chunk (OpenAI includes it with stream_options)
      if event_data['usage']
        token_count = (event_data['usage']['prompt_tokens'] || 0) +
                      (event_data['usage']['completion_tokens'] || 0)
      end

      accumulated
    end

    if success && accumulated.present?
      { success: true, content: accumulated, model: model, tokens_used: token_count, cost: 0.0 }
    elsif accumulated.present?
      # Partial content from interrupted stream — still return it
      { success: true, content: accumulated, model: model, tokens_used: token_count, cost: 0.0 }
    else
      # Fallback to non-streaming
      log_info("Streaming failed, falling back to non-streaming", model: model)
      call_openai_non_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    end
  rescue StandardError => e
    log_error("OpenAI streaming error, falling back", error: e.message)
    call_openai_non_streaming(api_key, base_url, model, messages, temperature, max_tokens)
  end

  def call_anthropic_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    url = "#{base_url || 'https://api.anthropic.com/v1'}/messages"
    uri = URI(url)

    system_content = messages.select { |m| m[:role] == 'system' }.map { |m| m[:content] }.join("\n")
    chat_messages = messages.reject { |m| m[:role] == 'system' }

    body_hash = {
      model: model,
      messages: chat_messages,
      max_tokens: max_tokens,
      temperature: temperature,
      stream: true
    }
    body_hash[:system] = system_content if system_content.present?
    body = body_hash.to_json

    headers = {
      'Content-Type' => 'application/json',
      'x-api-key' => api_key,
      'anthropic-version' => '2023-06-01'
    }

    accumulated = ""
    input_tokens = 0
    output_tokens = 0

    success = stream_sse_request(uri, body, headers) do |event_data|
      event_type = event_data['type']

      case event_type
      when 'content_block_delta'
        delta = event_data.dig('delta', 'text')
        if delta
          accumulated += delta
          output_tokens += 1
        end
      when 'message_delta'
        usage = event_data.dig('usage')
        output_tokens = usage['output_tokens'] if usage&.key?('output_tokens')
      when 'message_start'
        usage = event_data.dig('message', 'usage')
        input_tokens = usage['input_tokens'] if usage&.key?('input_tokens')
      end

      accumulated
    end

    total_tokens = input_tokens + output_tokens

    if success && accumulated.present?
      { success: true, content: accumulated, model: model, tokens_used: total_tokens, cost: 0.0 }
    elsif accumulated.present?
      { success: true, content: accumulated, model: model, tokens_used: total_tokens, cost: 0.0 }
    else
      log_info("Streaming failed, falling back to non-streaming", model: model)
      call_anthropic_non_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    end
  rescue StandardError => e
    log_error("Anthropic streaming error, falling back", error: e.message)
    call_anthropic_non_streaming(api_key, base_url, model, messages, temperature, max_tokens)
  end

  def call_ollama_streaming(base_url, model, messages, temperature, max_tokens)
    url = "#{base_url || 'http://localhost:11434'}/api/chat"
    uri = URI(url)

    body = {
      model: model,
      messages: messages,
      stream: true,
      options: {
        temperature: temperature,
        num_predict: max_tokens
      }
    }.to_json

    headers = { 'Content-Type' => 'application/json' }

    accumulated = ""
    token_count = 0

    # Ollama uses newline-delimited JSON, not SSE
    success = stream_ndjson_request(uri, body, headers) do |event_data|
      content = event_data.dig('message', 'content')
      if content
        accumulated += content
        token_count += 1
      end

      # Final message includes eval_count
      if event_data['done'] && event_data['eval_count']
        token_count = event_data['eval_count']
      end

      accumulated
    end

    if success && accumulated.present?
      { success: true, content: accumulated, model: model, tokens_used: token_count, cost: 0.0 }
    elsif accumulated.present?
      { success: true, content: accumulated, model: model, tokens_used: token_count, cost: 0.0 }
    else
      log_info("Streaming failed, falling back to non-streaming", model: model)
      call_ollama_non_streaming(base_url, model, messages, temperature, max_tokens)
    end
  rescue StandardError => e
    log_error("Ollama streaming error, falling back", error: e.message)
    call_ollama_non_streaming(base_url, model, messages, temperature, max_tokens)
  end

  # =========================================================================
  # STREAMING TRANSPORT
  # =========================================================================

  # Parse SSE (Server-Sent Events) stream from OpenAI/Anthropic
  # Yields parsed JSON for each data event. Block should return accumulated content.
  def stream_sse_request(uri, body, headers, &block)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 600
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri)
    headers.each { |k, v| request[k] = v }
    request.body = body

    last_broadcast = Time.current
    sequence = 0
    success = true

    http.request(request) do |response|
      unless response.code.to_i == 200
        log_error("SSE stream HTTP error", status: response.code)
        success = false
        break
      end

      buffer = ""
      response.read_body do |chunk|
        buffer += chunk

        # Process complete SSE events (separated by double newlines)
        while (event_end = buffer.index("\n\n"))
          event_text = buffer[0...event_end]
          buffer = buffer[(event_end + 2)..]

          # Extract data lines from SSE event
          data_lines = event_text.split("\n").select { |l| l.start_with?("data: ") }
          data_lines.each do |line|
            payload = line.sub("data: ", "")
            next if payload.strip == "[DONE]"

            event_data = safe_parse_json(payload)
            next unless event_data

            accumulated = block.call(event_data)

            # Throttled broadcast to avoid flooding ActionCable
            now = Time.current
            if (now - last_broadcast) >= STREAM_BROADCAST_INTERVAL
              sequence += 1
              broadcast_stream_chunk(accumulated, sequence)
              last_broadcast = now
            end
          end
        end
      end
    end

    success
  end

  # Parse newline-delimited JSON stream (Ollama format)
  def stream_ndjson_request(uri, body, headers, &block)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 600
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri)
    headers.each { |k, v| request[k] = v }
    request.body = body

    last_broadcast = Time.current
    sequence = 0
    success = true

    http.request(request) do |response|
      unless response.code.to_i == 200
        log_error("NDJSON stream HTTP error", status: response.code)
        success = false
        break
      end

      buffer = ""
      response.read_body do |chunk|
        buffer += chunk

        while (line_end = buffer.index("\n"))
          line = buffer[0...line_end].strip
          buffer = buffer[(line_end + 1)..]
          next if line.empty?

          event_data = safe_parse_json(line)
          next unless event_data

          accumulated = block.call(event_data)

          now = Time.current
          if (now - last_broadcast) >= STREAM_BROADCAST_INTERVAL
            sequence += 1
            broadcast_stream_chunk(accumulated, sequence)
            last_broadcast = now
          end
        end
      end
    end

    success
  end

  # =========================================================================
  # NON-STREAMING FALLBACKS
  # =========================================================================

  def call_openai_non_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    url = "#{base_url || 'https://api.openai.com/v1'}/chat/completions"

    body = {
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }.to_json

    response = make_http_request(url,
      method: :post,
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{api_key}"
      },
      body: body,
      timeout: 600
    )

    parse_openai_response(response, model)
  end

  def call_anthropic_non_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    url = "#{base_url || 'https://api.anthropic.com/v1'}/messages"

    system_content = messages.select { |m| m[:role] == 'system' }.map { |m| m[:content] }.join("\n")
    chat_messages = messages.reject { |m| m[:role] == 'system' }

    body_hash = {
      model: model,
      messages: chat_messages,
      max_tokens: max_tokens,
      temperature: temperature
    }
    body_hash[:system] = system_content if system_content.present?

    response = make_http_request(url,
      method: :post,
      headers: {
        'Content-Type' => 'application/json',
        'x-api-key' => api_key,
        'anthropic-version' => '2023-06-01'
      },
      body: body_hash.to_json,
      timeout: 600
    )

    parse_anthropic_response(response, model)
  end

  def call_ollama_non_streaming(base_url, model, messages, temperature, max_tokens)
    url = "#{base_url || 'http://localhost:11434'}/api/chat"

    body = {
      model: model,
      messages: messages,
      stream: false,
      options: {
        temperature: temperature,
        num_predict: max_tokens
      }
    }.to_json

    response = make_http_request(url,
      method: :post,
      headers: { 'Content-Type' => 'application/json' },
      body: body,
      timeout: 600
    )

    parse_ollama_response(response, model)
  end

  def call_generic(api_key, base_url, model, messages, temperature, max_tokens)
    url = "#{base_url}/chat/completions"

    body = {
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }.to_json

    headers = { 'Content-Type' => 'application/json' }
    headers['Authorization'] = "Bearer #{api_key}" if api_key.present?

    response = make_http_request(url,
      method: :post,
      headers: headers,
      body: body,
      timeout: 600
    )

    parse_openai_response(response, model)
  end

  # =========================================================================
  # RESPONSE PARSERS
  # =========================================================================

  def parse_openai_response(response, model)
    data = safe_parse_json(response.body)

    if response.code.to_i == 200 && data['choices']
      content = data.dig('choices', 0, 'message', 'content') || ''
      usage = data['usage'] || {}
      tokens = (usage['prompt_tokens'] || 0) + (usage['completion_tokens'] || 0)

      { success: true, content: content, model: model, tokens_used: tokens, cost: 0.0 }
    else
      { success: false, error: data['error']&.dig('message') || "OpenAI error: #{response.code}" }
    end
  end

  def parse_anthropic_response(response, model)
    data = safe_parse_json(response.body)

    if response.code.to_i == 200 && data['content']
      content = data['content'].map { |c| c['text'] }.compact.join("\n")
      usage = data['usage'] || {}
      tokens = (usage['input_tokens'] || 0) + (usage['output_tokens'] || 0)

      { success: true, content: content, model: model, tokens_used: tokens, cost: 0.0 }
    else
      { success: false, error: data.dig('error', 'message') || "Anthropic error: #{response.code}" }
    end
  end

  def parse_ollama_response(response, model)
    data = safe_parse_json(response.body)

    if response.code.to_i == 200 && data['message']
      content = data.dig('message', 'content') || ''
      tokens = data.dig('eval_count') || 0

      { success: true, content: content, model: model, tokens_used: tokens, cost: 0.0 }
    else
      { success: false, error: data['error'] || "Ollama error: #{response.code}" }
    end
  end

  # =========================================================================
  # BROADCAST HELPERS
  # =========================================================================

  def broadcast_stream_chunk(accumulated_content, sequence)
    return unless @conversation_id

    backend_api_post("/api/v1/ai/conversations/#{@conversation_id}/worker_stream_chunk", {
      message_id: "streaming-#{@message_id}",
      accumulated_content: accumulated_content,
      token_count: sequence,
      model: nil,
      agent_name: @agent_name,
      sequence: sequence
    })
  rescue StandardError => e
    log_error("Failed to broadcast stream chunk", error: e.message, sequence: sequence)
  end

  def broadcast_complete(conversation_id, message_id, content, token_count:, cost_usd:, model:, duration_ms:)
    backend_api_post("/api/v1/ai/conversations/#{conversation_id}/worker_complete", {
      message_id: message_id,
      content: content,
      token_count: token_count,
      cost_usd: cost_usd,
      model: model,
      duration_ms: duration_ms
    })
  rescue StandardError => e
    log_error("Failed to broadcast completion", error: e.message)
  end

  def broadcast_error(conversation_id, error_message)
    return unless conversation_id

    backend_api_post("/api/v1/ai/conversations/#{conversation_id}/worker_error", {
      error: error_message
    })
  rescue StandardError => e
    log_error("Failed to broadcast error", error: e.message)
  end
end
