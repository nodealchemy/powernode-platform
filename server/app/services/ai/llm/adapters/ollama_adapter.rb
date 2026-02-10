# frozen_string_literal: true

module Ai
  module Llm
    module Adapters
      # Ollama adapter for local models
      # POST /api/chat
      # NDJSON streaming (not SSE)
      # Tool calling on Llama 3.1+, Mistral, Qwen 2.5
      # Structured output: format: { type: "object", properties: { ... } }
      # Auto-detect Open WebUI (/ollama/api/chat vs /api/chat)
      class OllamaAdapter < BaseAdapter
        def initialize(api_key: nil, base_url:, provider_name: "ollama", extra_headers: {})
          auth_headers = {}
          auth_headers["Authorization"] = "Bearer #{api_key}" if api_key.present?
          @raw_base_url = base_url.to_s.chomp("/")
          super(api_key: api_key, base_url: @raw_base_url, provider_name: provider_name,
                extra_headers: auth_headers.merge(extra_headers))
        end

        def complete(messages:, model:, **opts)
          body = build_chat_body(messages, model, stream: false, **opts)
          url = build_chat_url
          response = HTTParty.post(url, headers: headers, body: body.to_json, timeout: 300)

          case response.code
          when 200
            build_ollama_response(JSON.parse(response.body), model)
          else
            handle_error(response.code, response.parsed_response)
          end
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT => e
          build_error_response("Ollama connection failed: #{e.message}")
        end

        def stream(messages:, model:, **opts, &block)
          raise ArgumentError, "Block required for streaming" unless block_given?

          body = build_chat_body(messages, model, stream: true, **opts)
          url = build_chat_url

          accumulated_content = ""
          tool_calls = []
          usage_data = {}
          stream_id = SecureRandom.uuid

          yield Ai::Llm::Chunk.new(type: :stream_start, stream_id: stream_id,
                                    timestamp: Time.current.iso8601)

          uri = URI.parse(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.read_timeout = 300
          http.open_timeout = 30

          request = Net::HTTP::Post.new(uri.request_uri)
          headers.each { |k, v| request[k] = v }
          request.body = body.to_json

          http.request(request) do |response|
            unless response.is_a?(Net::HTTPSuccess)
              yield Ai::Llm::Chunk.new(type: :error, content: "HTTP #{response.code}",
                                        stream_id: stream_id, timestamp: Time.current.iso8601)
              return build_error_response("HTTP #{response.code}", status_code: response.code.to_i)
            end

            parse_ndjson_stream(response) do |parsed|
              # Text content
              if parsed.dig("message", "content")
                content = parsed["message"]["content"]
                accumulated_content += content
                yield Ai::Llm::Chunk.new(
                  type: :content_delta, content: content,
                  stream_id: stream_id, timestamp: Time.current.iso8601
                )
              end

              # Tool calls (in final message for Ollama)
              if parsed.dig("message", "tool_calls")
                parsed["message"]["tool_calls"].each do |tc|
                  tool_call = {
                    id: SecureRandom.uuid, # Ollama doesn't provide IDs
                    name: tc.dig("function", "name"),
                    arguments: tc.dig("function", "arguments") || {}
                  }
                  tool_calls << tool_call
                  yield Ai::Llm::Chunk.new(
                    type: :tool_call_start, tool_call_id: tool_call[:id],
                    tool_call_name: tool_call[:name],
                    stream_id: stream_id, timestamp: Time.current.iso8601
                  )
                  yield Ai::Llm::Chunk.new(
                    type: :tool_call_end, tool_call_id: tool_call[:id],
                    stream_id: stream_id, timestamp: Time.current.iso8601
                  )
                end
              end

              # Done signal
              if parsed["done"]
                usage_data = {
                  prompt_tokens: parsed["prompt_eval_count"] || 0,
                  completion_tokens: parsed["eval_count"] || 0,
                  total_tokens: (parsed["prompt_eval_count"] || 0) + (parsed["eval_count"] || 0)
                }
              end
            end
          end

          yield Ai::Llm::Chunk.new(
            type: :stream_end, done: true, usage: usage_data,
            stream_id: stream_id, timestamp: Time.current.iso8601
          )

          build_response(
            content: accumulated_content.presence,
            tool_calls: tool_calls,
            finish_reason: "stop",
            model: model,
            usage: usage_data,
            stream_id: stream_id
          )
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT => e
          yield Ai::Llm::Chunk.new(type: :error, content: e.message,
                                    stream_id: stream_id, timestamp: Time.current.iso8601)
          build_error_response("Ollama connection failed: #{e.message}")
        end

        def complete_with_tools(messages:, tools:, model:, **opts)
          ollama_tools = tools.map do |tool|
            {
              type: "function",
              function: {
                name: tool[:name],
                description: tool[:description],
                parameters: tool[:parameters]
              }
            }
          end

          body = build_chat_body(messages, model, stream: false, **opts)
          body[:tools] = ollama_tools

          url = build_chat_url
          response = HTTParty.post(url, headers: headers, body: body.to_json, timeout: 300)

          case response.code
          when 200
            build_ollama_response(JSON.parse(response.body), model)
          else
            handle_error(response.code, response.parsed_response)
          end
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT => e
          build_error_response("Ollama connection failed: #{e.message}")
        end

        def complete_structured(messages:, schema:, model:, **opts)
          body = build_chat_body(messages, model, stream: false, **opts)
          body[:format] = schema[:schema] || schema

          url = build_chat_url
          response = HTTParty.post(url, headers: headers, body: body.to_json, timeout: 300)

          case response.code
          when 200
            build_ollama_response(JSON.parse(response.body), model)
          else
            handle_error(response.code, response.parsed_response)
          end
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT => e
          build_error_response("Ollama connection failed: #{e.message}")
        end

        private

        def build_chat_body(messages, model, stream: false, **opts)
          formatted = messages.map do |m|
            role = m[:role] || m["role"]
            content = m[:content] || m["content"]

            # Convert tool results
            if role == "tool"
              { role: "tool", content: content.is_a?(String) ? content : content.to_json }
            else
              { role: role, content: content }
            end
          end

          body = { model: model, messages: formatted, stream: stream }
          body[:options] = {} unless opts.empty?

          if opts[:temperature]
            body[:options] ||= {}
            body[:options][:temperature] = opts[:temperature]
          end
          if opts[:max_tokens]
            body[:options] ||= {}
            body[:options][:num_predict] = opts[:max_tokens]
          end
          if opts[:keep_alive]
            body[:keep_alive] = opts[:keep_alive]
          end

          body.delete(:options) if body[:options]&.empty?
          body
        end

        def build_chat_url
          # Handle Open WebUI (/ollama/api/chat) vs standard Ollama (/api/chat)
          if @raw_base_url.end_with?("/api")
            "#{@raw_base_url}/chat"
          elsif @raw_base_url.include?("/ollama")
            "#{@raw_base_url}/api/chat"
          else
            "#{@raw_base_url}/api/chat"
          end
        end

        def build_ollama_response(parsed, model)
          message = parsed["message"] || {}
          content = message["content"]

          tool_calls = (message["tool_calls"] || []).map do |tc|
            {
              id: SecureRandom.uuid,
              name: tc.dig("function", "name"),
              arguments: tc.dig("function", "arguments") || {}
            }
          end

          build_response(
            content: content,
            tool_calls: tool_calls,
            finish_reason: parsed["done"] ? "stop" : "length",
            model: parsed["model"] || model,
            usage: {
              prompt_tokens: parsed["prompt_eval_count"] || 0,
              completion_tokens: parsed["eval_count"] || 0,
              total_tokens: (parsed["prompt_eval_count"] || 0) + (parsed["eval_count"] || 0)
            },
            raw_response: parsed
          )
        end

        def handle_error(status, parsed)
          error_msg = if parsed.is_a?(Hash)
                        parsed["error"] || "Unknown error"
                      else
                        parsed.to_s
                      end

          build_error_response("#{error_msg} (HTTP #{status})", status_code: status)
        end
      end
    end
  end
end
