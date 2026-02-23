# frozen_string_literal: true

module Ai
  module Llm
    module Adapters
      # OpenAI-compatible adapter (also works with Groq, Mistral, Azure, Grok, Cohere)
      # POST /chat/completions
      # Tool calling: tools array with function definitions
      # Structured output: response_format: { type: "json_schema", json_schema: { ... } }
      # SSE streaming: data: {json}\n\n
      class OpenaiAdapter < BaseAdapter
        def initialize(api_key:, base_url:, provider_name: "openai", extra_headers: {})
          auth_headers = { "Authorization" => "Bearer #{api_key}" }
          super(api_key: api_key, base_url: base_url, provider_name: provider_name,
                extra_headers: auth_headers.merge(extra_headers))
        end

        def complete(messages:, model:, **opts)
          body = build_chat_body(messages, model, **opts)
          status, parsed, _headers = http_post("/chat/completions", body)

          case status
          when 200
            build_openai_response(parsed, model)
          else
            handle_error(status, parsed)
          end
        end

        def stream(messages:, model:, **opts, &block)
          raise ArgumentError, "Block required for streaming" unless block_given?

          body = build_chat_body(messages, model, **opts)
          body[:stream] = true
          body[:stream_options] = { include_usage: true }

          accumulated_content = ""
          tool_calls_buffer = {}
          usage_data = {}
          stream_id = SecureRandom.uuid
          finish_reason = nil

          yield Ai::Llm::Chunk.new(type: :stream_start, stream_id: stream_id,
                                    timestamp: Time.current.iso8601)

          http_stream("/chat/completions", body) do |response|
            parse_sse_stream(response) do |parsed|
              choice = parsed.dig("choices", 0)
              next unless choice

              delta = choice["delta"] || {}

              # Text content
              if delta["content"]
                accumulated_content += delta["content"]
                yield Ai::Llm::Chunk.new(
                  type: :content_delta, content: delta["content"],
                  stream_id: stream_id, timestamp: Time.current.iso8601
                )
              end

              # Tool calls (streamed incrementally)
              if delta["tool_calls"]
                delta["tool_calls"].each do |tc|
                  idx = tc["index"]
                  if tc["id"]
                    tool_calls_buffer[idx] = { id: tc["id"], name: tc.dig("function", "name"), arguments: "" }
                    yield Ai::Llm::Chunk.new(
                      type: :tool_call_start, tool_call_id: tc["id"],
                      tool_call_name: tc.dig("function", "name"),
                      stream_id: stream_id, timestamp: Time.current.iso8601
                    )
                  end
                  if tc.dig("function", "arguments")
                    tool_calls_buffer[idx][:arguments] += tc["function"]["arguments"]
                    yield Ai::Llm::Chunk.new(
                      type: :tool_call_delta, tool_call_id: tool_calls_buffer[idx][:id],
                      tool_call_args_delta: tc["function"]["arguments"],
                      stream_id: stream_id, timestamp: Time.current.iso8601
                    )
                  end
                end
              end

              finish_reason = choice["finish_reason"] if choice["finish_reason"]

              # Usage in final chunk
              if parsed["usage"]
                usage_data = {
                  prompt_tokens: parsed["usage"]["prompt_tokens"],
                  completion_tokens: parsed["usage"]["completion_tokens"],
                  cached_tokens: parsed["usage"]["prompt_tokens_details"]&.dig("cached_tokens") || 0,
                  total_tokens: parsed["usage"]["total_tokens"]
                }
              end
            end
          end

          # Emit tool_call_end for each accumulated tool call
          tool_calls_buffer.each_value do |tc|
            yield Ai::Llm::Chunk.new(
              type: :tool_call_end, tool_call_id: tc[:id],
              stream_id: stream_id, timestamp: Time.current.iso8601
            )
          end

          yield Ai::Llm::Chunk.new(
            type: :stream_end, done: true, usage: usage_data,
            stream_id: stream_id, timestamp: Time.current.iso8601
          )

          # Build normalized tool_calls array
          normalized_tool_calls = tool_calls_buffer.values.map do |tc|
            { id: tc[:id], name: tc[:name], arguments: safe_parse_json(tc[:arguments]) }
          end

          build_response(
            content: accumulated_content.presence,
            tool_calls: normalized_tool_calls,
            finish_reason: finish_reason,
            model: model,
            usage: usage_data,
            stream_id: stream_id
          )
        rescue Adapters::RequestError => e
          yield Ai::Llm::Chunk.new(type: :error, content: e.message,
                                    stream_id: stream_id, timestamp: Time.current.iso8601)
          build_error_response(e.message, status_code: e.status_code)
        end

        def complete_with_tools(messages:, tools:, model:, **opts)
          openai_tools = tools.map do |tool|
            {
              type: "function",
              function: {
                name: tool[:name],
                description: tool[:description],
                parameters: tool[:parameters],
                strict: tool[:strict] || false
              }.compact
            }
          end

          body = build_chat_body(messages, model, **opts)
          body[:tools] = openai_tools
          body[:tool_choice] = opts[:tool_choice] || "auto"

          status, parsed, _headers = http_post("/chat/completions", body)

          case status
          when 200
            build_openai_response(parsed, model)
          else
            handle_error(status, parsed)
          end
        end

        def complete_structured(messages:, schema:, model:, **opts)
          body = build_chat_body(messages, model, **opts)
          body[:response_format] = {
            type: "json_schema",
            json_schema: {
              name: schema[:name] || "response",
              schema: schema[:schema] || schema,
              strict: true
            }
          }

          status, parsed, _headers = http_post("/chat/completions", body)

          case status
          when 200
            build_openai_response(parsed, model)
          else
            handle_error(status, parsed)
          end
        end

        private

        def build_chat_body(messages, model, **opts)
          # Separate system messages
          system_msgs = messages.select { |m| (m[:role] || m["role"]) == "system" }
          other_msgs = messages.reject { |m| (m[:role] || m["role"]) == "system" }

          formatted_messages = []

          # Add system messages first
          system_content = system_msgs.map { |m| m[:content] || m["content"] }.join("\n")
          if opts[:system_prompt].present?
            system_content = [system_content, opts[:system_prompt]].reject(&:blank?).join("\n")
          end
          formatted_messages << { role: "system", content: system_content } if system_content.present?

          # Add other messages
          other_msgs.each do |m|
            formatted_messages << normalize_message(m)
          end

          body = {
            model: model,
            messages: formatted_messages,
            max_tokens: opts[:max_tokens] || 4096,
            temperature: opts[:temperature] || 0.7
          }

          body[:top_p] = opts[:top_p] if opts[:top_p]
          body[:stop] = opts[:stop] if opts[:stop]
          body[:presence_penalty] = opts[:presence_penalty] if opts[:presence_penalty]
          body[:frequency_penalty] = opts[:frequency_penalty] if opts[:frequency_penalty]
          body
        end

        def normalize_message(msg)
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]

          result = { role: role, content: content }

          # Tool results
          if role == "tool"
            result[:tool_call_id] = msg[:tool_call_id] || msg["tool_call_id"]
          end

          # Assistant messages with tool calls — ensure OpenAI nested format
          if msg[:tool_calls] || msg["tool_calls"]
            raw_calls = msg[:tool_calls] || msg["tool_calls"]
            result[:tool_calls] = raw_calls.map { |tc| normalize_tool_call(tc) }
          end

          result
        end

        # Ensure tool call is in OpenAI nested format {type: "function", function: {name, arguments}}
        def normalize_tool_call(tc)
          # Already in OpenAI format — pass through
          if tc[:type] == "function" || tc["type"] == "function"
            return tc
          end

          # Convert from flat canonical format {id, name, arguments}
          tc_name = tc[:name] || tc["name"]
          tc_args = tc[:arguments] || tc["arguments"] || {}
          tc_args = tc_args.to_json unless tc_args.is_a?(String)

          {
            id: tc[:id] || tc["id"],
            type: "function",
            function: { name: tc_name, arguments: tc_args }
          }
        end

        def build_openai_response(parsed, model)
          choice = parsed.dig("choices", 0) || {}
          message = choice["message"] || {}

          tool_calls = (message["tool_calls"] || []).map do |tc|
            {
              id: tc["id"],
              name: tc.dig("function", "name"),
              arguments: safe_parse_json(tc.dig("function", "arguments"))
            }
          end

          usage = parsed["usage"] || {}

          build_response(
            content: message["content"],
            tool_calls: tool_calls,
            finish_reason: choice["finish_reason"],
            model: parsed["model"] || model,
            usage: {
              prompt_tokens: usage["prompt_tokens"] || 0,
              completion_tokens: usage["completion_tokens"] || 0,
              cached_tokens: usage.dig("prompt_tokens_details", "cached_tokens") || 0,
              total_tokens: usage["total_tokens"] || 0
            },
            raw_response: parsed
          )
        end

        def handle_error(status, parsed)
          error_msg = if parsed.is_a?(Hash)
                        parsed.dig("error", "message") || parsed["error"] || "Unknown error"
                      else
                        parsed.to_s
                      end
          error_msg = error_msg.to_json if error_msg.is_a?(Hash)

          build_error_response("#{error_msg} (HTTP #{status})", status_code: status)
        end

        def safe_parse_json(str)
          return str unless str.is_a?(String)

          JSON.parse(str)
        rescue JSON::ParserError
          str
        end
      end
    end
  end
end
