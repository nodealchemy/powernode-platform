# frozen_string_literal: true

class Ai::ProviderClientService
  module OpenaiAdapter
    extend ActiveSupport::Concern

    private

    # OpenAI text generation
    def openai_generate_text(prompt, model, **options)
      url = "/chat/completions"

      body = {
        model: model,
        messages: [ { role: "user", content: prompt } ],
        max_tokens: options[:max_tokens] || 2000,
        temperature: options[:temperature] || 0.7
      }

      response = self.class.post(url, headers: @headers, body: body.to_json)
      handle_response(response)
    end

    # OpenAI streaming text generation
    def openai_stream_text(prompt, model, **options, &block)
      url = "/chat/completions"
      messages = options[:messages] || [ { role: "user", content: prompt } ]

      body = {
        model: model,
        messages: messages.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } },
        max_tokens: options[:max_tokens] || 2000,
        temperature: options[:temperature] || 0.7,
        stream: true,
        stream_options: { include_usage: true }
      }

      # Add optional parameters
      body[:system] = options[:system_prompt] if options[:system_prompt].present?

      full_url = "#{provider.api_base_url}#{url}"
      stream_response_with_sse(full_url, body, :openai, &block)
    end

    # OpenAI image generation
    def openai_generate_image(prompt, model, **options)
      url = "/images/generations"

      body = {
        model: model,
        prompt: prompt,
        n: options[:n] || 1,
        size: options[:size] || "1024x1024"
      }

      response = self.class.post(url, headers: @headers, body: body.to_json)
      handle_response(response)
    end

    # OpenAI chat message implementation
    def openai_send_message(messages, model, **options)
      url = "/chat/completions"

      body = {
        model: model,
        messages: messages.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } },
        max_tokens: options[:max_tokens] || 2000,
        temperature: options[:temperature] || 0.7
      }

      # Add optional parameters
      body[:stream] = options[:stream] if options[:stream]
      body[:presence_penalty] = options[:presence_penalty] if options[:presence_penalty]
      body[:frequency_penalty] = options[:frequency_penalty] if options[:frequency_penalty]
      body[:functions] = options[:functions] if options[:functions]
      body[:function_call] = options[:function_call] if options[:function_call]

      response = self.class.post(url, headers: @headers, body: body.to_json)
      handle_chat_response(response)
    end

    # OpenAI batch processing
    def process_openai_batch(prompts, model_name, **options)
      # OpenAI doesn't have native batch API for chat completions yet
      # Process individually with rate limiting
      prompts.map.with_index do |prompt, index|
        # Add small delay between requests to avoid rate limits
        sleep(0.1) if index > 0

        result = openai_generate_text(prompt, model_name, **options)
        {
          prompt: prompt,
          result: result[:success] ? result[:text] : nil,
          success: result[:success],
          error: result[:error],
          cost: result[:cost] || 0
        }
      end
    end

    # Parse OpenAI SSE streaming chunk
    def parse_openai_sse_chunk(parsed)
      result = { content: nil, done: false, usage: nil }

      # OpenAI streaming format: { choices: [{ delta: { content: "..." } }] }
      if parsed["choices"]&.first
        choice = parsed["choices"].first
        delta = choice["delta"]

        result[:content] = delta["content"] if delta && delta["content"]
        result[:done] = choice["finish_reason"].present?
      end

      # Usage data comes in the final chunk with stream_options: include_usage
      if parsed["usage"]
        result[:usage] = {
          prompt_tokens: parsed["usage"]["prompt_tokens"],
          completion_tokens: parsed["usage"]["completion_tokens"],
          total_tokens: parsed["usage"]["total_tokens"]
        }
      end

      result
    end
  end
end
