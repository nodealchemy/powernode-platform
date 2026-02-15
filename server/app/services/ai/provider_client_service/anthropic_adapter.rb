# frozen_string_literal: true

class Ai::ProviderClientService
  module AnthropicAdapter
    extend ActiveSupport::Concern

    private

    # Anthropic text generation
    def anthropic_generate_text(prompt, model, **options)
      url = "/messages"

      body = {
        model: model,
        messages: [ { role: "user", content: prompt } ],
        max_tokens: options[:max_tokens] || 2000
      }

      # Add system prompt if provided
      body[:system] = options[:system_prompt] if options[:system_prompt].present?

      # Add temperature if provided
      body[:temperature] = options[:temperature] if options[:temperature]

      response = self.class.post(url, headers: @headers, body: body.to_json)
      handle_response(response)
    end

    # Anthropic streaming text generation
    def anthropic_stream_text(prompt, model, **options, &block)
      url = "/messages"
      messages = options[:messages] || [ { role: "user", content: prompt } ]

      # Separate system messages from other messages for Anthropic
      system_content = messages.select { |m| (m[:role] || m["role"]) == "system" }
                              .map { |m| m[:content] || m["content"] }
                              .join("\n")

      user_messages = messages.reject { |m| (m[:role] || m["role"]) == "system" }

      body = {
        model: model,
        messages: user_messages.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } },
        max_tokens: options[:max_tokens] || 2000,
        stream: true
      }

      body[:system] = system_content if system_content.present?
      body[:system] = options[:system_prompt] if options[:system_prompt].present? && body[:system].blank?
      body[:temperature] = options[:temperature] if options[:temperature]

      full_url = "#{provider.api_base_url}#{url}"
      stream_response_with_sse(full_url, body, :anthropic, &block)
    end

    # Anthropic chat message implementation
    def anthropic_send_message(messages, model, **options)
      url = "/messages"

      # Separate system messages from other messages for Anthropic
      system_content = messages.select { |m| (m[:role] || m["role"]) == "system" }
                              .map { |m| m[:content] || m["content"] }
                              .join("\n")

      user_messages = messages.reject { |m| (m[:role] || m["role"]) == "system" }

      body = {
        model: model,
        messages: user_messages.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } },
        max_tokens: options[:max_tokens] || 2000
      }

      body[:system] = system_content if system_content.present?
      body[:temperature] = options[:temperature] if options[:temperature]

      response = self.class.post(url, headers: @headers, body: body.to_json)
      handle_chat_response(response)
    end

    # Anthropic batch processing
    def process_anthropic_batch(prompts, model_name, **options)
      # Anthropic also processes individually for now
      prompts.map.with_index do |prompt, index|
        sleep(0.1) if index > 0

        result = anthropic_generate_text(prompt, model_name, **options)
        {
          prompt: prompt,
          result: result[:success] ? result[:text] : nil,
          success: result[:success],
          error: result[:error],
          cost: result[:cost] || 0
        }
      end
    end

    # Parse Anthropic SSE streaming chunk
    def parse_anthropic_sse_chunk(parsed)
      result = { content: nil, done: false, usage: nil }

      # Anthropic streaming events: content_block_delta, message_delta, message_stop
      case parsed["type"]
      when "content_block_delta"
        if parsed["delta"] && parsed["delta"]["type"] == "text_delta"
          result[:content] = parsed["delta"]["text"]
        end
      when "message_delta"
        if parsed["usage"]
          result[:usage] = {
            prompt_tokens: parsed["usage"]["input_tokens"],
            completion_tokens: parsed["usage"]["output_tokens"],
            total_tokens: (parsed["usage"]["input_tokens"] || 0) + (parsed["usage"]["output_tokens"] || 0)
          }
        end
      when "message_stop"
        result[:done] = true
      end

      result
    end
  end
end
