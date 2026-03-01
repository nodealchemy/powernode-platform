# frozen_string_literal: true

module ChatFallbackProvidersConcern
  extend ActiveSupport::Concern

  private

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

  # Response parsers

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

  # Broadcast helpers

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
