# frozen_string_literal: true

module Ai
  module Llm
    module Adapters
      # Anthropic adapter for Claude models
      # POST /v1/messages
      # Key differences from OpenAI:
      #   - System prompt is separate `system` param (NOT in messages)
      #   - Tools use `input_schema` (NOT `parameters`)
      #   - Tool results are role: "user" with type: "tool_result" (NOT role: "tool")
      #   - Auth via x-api-key + anthropic-version headers
      #   - Named SSE events (event: content_block_delta\ndata: {json}\n\n)
      #   - Structured output: output_config: { format: { type: "json", schema: {...} } }
      #   - Prompt caching: cache_control: { type: "ephemeral" } (max 4 breakpoints)
      #   - Extended thinking: thinking: { type: "enabled", budget_tokens: N }
      class AnthropicAdapter < BaseAdapter
        ANTHROPIC_VERSION = "2023-06-01"

        def initialize(api_key:, base_url: "https://api.anthropic.com/v1", provider_name: "anthropic", extra_headers: {})
          auth_headers = {
            "x-api-key" => api_key,
            "anthropic-version" => ANTHROPIC_VERSION
          }
          super(api_key: api_key, base_url: base_url, provider_name: provider_name,
                extra_headers: auth_headers.merge(extra_headers))
        end

        def complete(messages:, model:, **opts)
          body = build_messages_body(messages, model, **opts)
          status, parsed, _headers = http_post("/messages", body)

          case status
          when 200
            build_anthropic_response(parsed, model)
          else
            handle_error(status, parsed)
          end
        end

        def stream(messages:, model:, **opts, &block)
          raise ArgumentError, "Block required for streaming" unless block_given?

          body = build_messages_body(messages, model, **opts)
          body[:stream] = true

          accumulated_content = ""
          tool_calls = []
          current_tool_call = nil
          usage_data = {}
          stream_id = SecureRandom.uuid
          finish_reason = nil
          thinking_content = ""

          yield Ai::Llm::Chunk.new(type: :stream_start, stream_id: stream_id,
                                    timestamp: Time.current.iso8601)

          http_stream("/messages", body) do |response|
            parse_anthropic_sse_stream(response) do |event_type, parsed|
              case event_type
              when "content_block_start"
                block_type = parsed.dig("content_block", "type")
                if block_type == "tool_use"
                  current_tool_call = {
                    id: parsed.dig("content_block", "id"),
                    name: parsed.dig("content_block", "name"),
                    arguments: ""
                  }
                  yield Ai::Llm::Chunk.new(
                    type: :tool_call_start,
                    tool_call_id: current_tool_call[:id],
                    tool_call_name: current_tool_call[:name],
                    stream_id: stream_id, timestamp: Time.current.iso8601
                  )
                end

              when "content_block_delta"
                delta = parsed["delta"] || {}
                case delta["type"]
                when "text_delta"
                  text = delta["text"]
                  accumulated_content += text
                  yield Ai::Llm::Chunk.new(
                    type: :content_delta, content: text,
                    stream_id: stream_id, timestamp: Time.current.iso8601
                  )
                when "input_json_delta"
                  if current_tool_call
                    current_tool_call[:arguments] += delta["partial_json"].to_s
                    yield Ai::Llm::Chunk.new(
                      type: :tool_call_delta,
                      tool_call_id: current_tool_call[:id],
                      tool_call_args_delta: delta["partial_json"],
                      stream_id: stream_id, timestamp: Time.current.iso8601
                    )
                  end
                when "thinking_delta"
                  thinking_content += delta["thinking"].to_s
                  yield Ai::Llm::Chunk.new(
                    type: :thinking_delta, content: delta["thinking"],
                    stream_id: stream_id, timestamp: Time.current.iso8601
                  )
                end

              when "content_block_stop"
                if current_tool_call
                  tool_calls << {
                    id: current_tool_call[:id],
                    name: current_tool_call[:name],
                    arguments: safe_parse_json(current_tool_call[:arguments])
                  }
                  yield Ai::Llm::Chunk.new(
                    type: :tool_call_end, tool_call_id: current_tool_call[:id],
                    stream_id: stream_id, timestamp: Time.current.iso8601
                  )
                  current_tool_call = nil
                end

              when "message_delta"
                finish_reason = parsed.dig("delta", "stop_reason")
                if parsed["usage"]
                  usage_data[:completion_tokens] = parsed["usage"]["output_tokens"]
                end

              when "message_start"
                if parsed.dig("message", "usage")
                  usage_data[:prompt_tokens] = parsed["message"]["usage"]["input_tokens"]
                  usage_data[:cached_tokens] = parsed["message"]["usage"]["cache_read_input_tokens"] || 0
                end
              end
            end
          end

          usage_data[:total_tokens] = (usage_data[:prompt_tokens] || 0) + (usage_data[:completion_tokens] || 0)

          yield Ai::Llm::Chunk.new(
            type: :stream_end, done: true, usage: usage_data,
            stream_id: stream_id, timestamp: Time.current.iso8601
          )

          build_response(
            content: accumulated_content.presence,
            tool_calls: tool_calls,
            finish_reason: finish_reason,
            model: model,
            usage: usage_data,
            thinking_content: thinking_content.presence,
            stream_id: stream_id
          )
        rescue Adapters::RequestError => e
          yield Ai::Llm::Chunk.new(type: :error, content: e.message,
                                    stream_id: stream_id, timestamp: Time.current.iso8601)
          build_error_response(e.message, status_code: e.status_code)
        end

        def complete_with_tools(messages:, tools:, model:, **opts)
          anthropic_tools = tools.map do |tool|
            {
              name: tool[:name],
              description: tool[:description],
              input_schema: tool[:parameters] || tool[:input_schema]
            }
          end

          body = build_messages_body(messages, model, **opts)
          body[:tools] = anthropic_tools
          body[:tool_choice] = opts[:tool_choice] ? anthropic_tool_choice(opts[:tool_choice]) : { type: "auto" }

          status, parsed, _headers = http_post("/messages", body)

          case status
          when 200
            build_anthropic_response(parsed, model)
          else
            handle_error(status, parsed)
          end
        end

        def complete_structured(messages:, schema:, model:, **opts)
          body = build_messages_body(messages, model, **opts)
          # Anthropic uses output_config for structured output (GA since late 2025)
          body[:output_config] = {
            format: {
              type: "json",
              schema: schema[:schema] || schema
            }
          }

          status, parsed, _headers = http_post("/messages", body)

          case status
          when 200
            build_anthropic_response(parsed, model)
          else
            handle_error(status, parsed)
          end
        end

        private

        def build_messages_body(messages, model, **opts)
          # Separate system messages — Anthropic requires system as top-level param
          system_msgs = messages.select { |m| (m[:role] || m["role"]) == "system" }
          other_msgs = messages.reject { |m| (m[:role] || m["role"]) == "system" }

          system_content = system_msgs.map { |m| m[:content] || m["content"] }.join("\n")
          if opts[:system_prompt].present?
            system_content = [system_content, opts[:system_prompt]].reject(&:blank?).join("\n")
          end

          formatted_messages = other_msgs.map { |m| normalize_message(m) }

          body = {
            model: model,
            messages: formatted_messages,
            max_tokens: opts[:max_tokens] || 4096
          }

          body[:system] = build_system_param(system_content, opts) if system_content.present?
          body[:temperature] = opts[:temperature] if opts[:temperature]
          body[:top_p] = opts[:top_p] if opts[:top_p]
          body[:stop_sequences] = opts[:stop] if opts[:stop]

          # Extended thinking
          if opts[:thinking_budget]
            body[:thinking] = { type: "enabled", budget_tokens: opts[:thinking_budget] }
          end

          body
        end

        def build_system_param(system_content, opts)
          if opts[:cache_system_prompt]
            # Use cache_control for prompt caching
            [{ type: "text", text: system_content, cache_control: { type: "ephemeral" } }]
          else
            system_content
          end
        end

        def normalize_message(msg)
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]

          # Convert tool results from OpenAI format to Anthropic format
          if role == "tool"
            return {
              role: "user",
              content: [{
                type: "tool_result",
                tool_use_id: msg[:tool_call_id] || msg["tool_call_id"],
                content: content.is_a?(String) ? content : content.to_json
              }]
            }
          end

          # Handle assistant messages with tool_calls (convert to tool_use content blocks)
          if role == "assistant" && (msg[:tool_calls] || msg["tool_calls"])
            tool_calls = msg[:tool_calls] || msg["tool_calls"]
            content_blocks = []
            content_blocks << { type: "text", text: content } if content.present?
            tool_calls.each do |tc|
              content_blocks << {
                type: "tool_use",
                id: tc[:id] || tc["id"],
                name: tc[:name] || tc.dig("function", "name"),
                input: tc[:arguments] || tc.dig("function", "arguments") || {}
              }
            end
            return { role: "assistant", content: content_blocks }
          end

          { role: role, content: content }
        end

        def build_anthropic_response(parsed, model)
          content_blocks = parsed["content"] || []

          text_content = content_blocks
            .select { |b| b["type"] == "text" }
            .map { |b| b["text"] }
            .join

          thinking = content_blocks
            .select { |b| b["type"] == "thinking" }
            .map { |b| b["thinking"] }
            .join

          tool_calls = content_blocks
            .select { |b| b["type"] == "tool_use" }
            .map { |b| { id: b["id"], name: b["name"], arguments: b["input"] } }

          usage = parsed["usage"] || {}

          build_response(
            content: text_content.presence,
            tool_calls: tool_calls,
            finish_reason: parsed["stop_reason"],
            model: parsed["model"] || model,
            usage: {
              prompt_tokens: usage["input_tokens"] || 0,
              completion_tokens: usage["output_tokens"] || 0,
              cached_tokens: usage["cache_read_input_tokens"] || 0,
              total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
            },
            thinking_content: thinking.presence,
            raw_response: parsed
          )
        end

        # Parse Anthropic-specific SSE with named events
        def parse_anthropic_sse_stream(response)
          buffer = ""
          current_event_type = nil

          response.read_body do |chunk|
            buffer += chunk
            while (event_end = buffer.index("\n\n"))
              event_data = buffer[0...event_end]
              buffer = buffer[(event_end + 2)..]

              event_data.split("\n").each do |line|
                if line.start_with?("event: ")
                  current_event_type = line[7..]
                elsif line.start_with?("data: ")
                  json_str = line[6..]
                  begin
                    parsed = JSON.parse(json_str)
                    yield current_event_type, parsed
                  rescue JSON::ParserError => e
                    Rails.logger.warn "[LLM] Failed to parse Anthropic SSE: #{e.message}"
                  end
                end
              end
            end
          end
        end

        def anthropic_tool_choice(choice)
          case choice
          when "auto" then { type: "auto" }
          when "none" then { type: "none" }
          when "required", "any" then { type: "any" }
          when Hash then choice
          else { type: "tool", name: choice.to_s }
          end
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
