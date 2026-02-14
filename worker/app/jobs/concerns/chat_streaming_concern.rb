# frozen_string_literal: true

module ChatStreamingConcern
  extend ActiveSupport::Concern

  private

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
      delta = event_data.dig('choices', 0, 'delta', 'content')
      if delta
        accumulated += delta
        token_count += 1
      end

      if event_data['usage']
        token_count = (event_data['usage']['prompt_tokens'] || 0) +
                      (event_data['usage']['completion_tokens'] || 0)
      end

      accumulated
    end

    if success && accumulated.present?
      { success: true, content: accumulated, model: model, tokens_used: token_count, cost: 0.0 }
    elsif accumulated.present?
      { success: true, content: accumulated, model: model, tokens_used: token_count, cost: 0.0 }
    else
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

  # Parse SSE (Server-Sent Events) stream from OpenAI/Anthropic
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

        while (event_end = buffer.index("\n\n"))
          event_text = buffer[0...event_end]
          buffer = buffer[(event_end + 2)..]

          data_lines = event_text.split("\n").select { |l| l.start_with?("data: ") }
          data_lines.each do |line|
            payload = line.sub("data: ", "")
            next if payload.strip == "[DONE]"

            event_data = safe_parse_json(payload)
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
end
