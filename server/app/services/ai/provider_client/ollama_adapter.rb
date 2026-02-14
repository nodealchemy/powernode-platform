# frozen_string_literal: true

class Ai::ProviderClientService
  module OllamaAdapter
    extend ActiveSupport::Concern

    private

    # Ollama text generation
    def ollama_generate_text(prompt, model, **options)
      body = {
        model: model,
        prompt: prompt,
        stream: false
      }

      full_url = build_ollama_url("/api/generate")
      request_headers = build_ollama_headers

      response = HTTParty.post(full_url, headers: request_headers, body: body.to_json, timeout: 120)

      # Handle Ollama-specific response format
      if response.code == 200
        data = JSON.parse(response.body)
        content = data["response"] || "No response generated"

        {
          success: true,
          content: content,
          text: content, # For backward compatibility
          data: data,
          status_code: response.code,
          provider: provider.name,
          cost: 0, # Ollama is typically free
          metadata: {
            model: model,
            done: data["done"],
            total_duration: data["total_duration"],
            load_duration: data["load_duration"],
            prompt_eval_count: data["prompt_eval_count"],
            eval_count: data["eval_count"]
          }
        }
      else
        handle_response(response)
      end
    rescue StandardError => e
      {
        success: false,
        error: "Ollama request failed: #{e.message}",
        status_code: nil,
        provider: provider.name
      }
    end

    # Ollama streaming text generation
    def ollama_stream_text(prompt, model, **options, &block)
      messages = options[:messages] || [ { role: "user", content: prompt } ]

      body = {
        model: model,
        messages: messages.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } },
        stream: true
      }

      full_url = build_ollama_url("/api/chat")
      stream_response_with_ndjson(full_url, body, build_ollama_headers, &block)
    end

    # Ollama chat message implementation
    def ollama_send_message(messages, model, **options)
      body = {
        model: model,
        messages: messages.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } },
        stream: options[:stream] || false
      }

      full_url = build_ollama_url("/api/chat")
      request_headers = build_ollama_headers

      response = HTTParty.post(full_url, headers: request_headers, body: body.to_json, timeout: 120)
      handle_ollama_chat_response(response)
    end

    # Build Ollama URL handling both standard Ollama and Open WebUI
    def build_ollama_url(endpoint)
      base_url = (credentials_data["base_url"] || provider.api_base_url || "http://localhost:11434").to_s.chomp("/")

      # Handle Open WebUI which uses /ollama/api/... structure
      if base_url.end_with?("/ollama")
        "#{base_url}#{endpoint}"
      elsif base_url.include?("webui") || base_url.include?("openwebui")
        # Auto-detect Open WebUI and add /ollama prefix
        "#{base_url}/ollama#{endpoint}"
      else
        # Standard Ollama
        "#{base_url}#{endpoint}"
      end
    end

    # Build headers for Ollama requests (including auth for Open WebUI)
    def build_ollama_headers
      headers = {
        "Content-Type" => "application/json",
        "User-Agent" => "Powernode-AI/1.0"
      }

      # Add auth for Open WebUI
      api_key = credentials_data["api_key"]
      headers["Authorization"] = "Bearer #{api_key}" if api_key.present?

      headers
    end

    # Handle Ollama-specific chat response
    def handle_ollama_chat_response(response)
      if response.code == 200
        data = JSON.parse(response.body).deep_symbolize_keys

        prompt_tokens = data[:prompt_eval_count] || 0
        completion_tokens = data[:eval_count] || 0

        {
          success: true,
          response: {
            choices: [
              {
                message: data[:message],
                finish_reason: "stop"
              }
            ],
            model: data[:model],
            usage: {
              prompt_tokens: prompt_tokens,
              completion_tokens: completion_tokens,
              total_tokens: prompt_tokens + completion_tokens
            }
          },
          status_code: response.code,
          provider: provider.name
        }
      else
        handle_chat_response(response)
      end
    rescue JSON::ParserError
      {
        success: false,
        error: "Failed to parse Ollama response",
        error_type: "parse_error",
        status_code: response.code,
        provider: provider.name
      }
    end
  end
end
