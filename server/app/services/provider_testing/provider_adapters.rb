# frozen_string_literal: true

module ProviderTesting
  module ProviderAdapters
    private

    # THE MODEL A CONNECTION TEST SENDS COMES FROM THE PROVIDER (E3).
    #
    # Each arm used to carry its own `config["model"] || "<a literal>"`. That
    # made a green connection test a statement about a model the operator may
    # never use — and on a provider whose catalog does not include the literal,
    # the test failed for a reason that had nothing to do with the credential
    # it was testing.
    #
    # Resolution order: an explicit per-credential override, then
    # Provider#default_model — the configured default, else the LIGHTEST-tier
    # model in the synced catalog (E3b). No `|| available_models.first`: that is
    # catalog[0], the most expensive model. Blank means "nothing is configured",
    # which each caller reports as a configuration error rather than guessing.
    def resolved_test_model(config)
      explicit = config["model"].presence
      return explicit if explicit

      provider = credential&.provider
      provider&.default_model.presence
    end

    def perform_connection_test
      config = credential.credentials

      case @provider.provider_type
      when "openai"
        perform_openai_connection_test(config)
      when "anthropic"
        perform_anthropic_connection_test(config)
      when "ollama"
        perform_ollama_connection_test(config)
      else
        perform_generic_connection_test(config)
      end
    end

    def perform_openai_connection_test(config)
      api_key = config["api_key"]
      return error_result("authentication_error", "API key not configured") unless api_key

      headers = {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json"
      }

      model = resolved_test_model(config)
      return error_result("configuration_error", "No model configured for this provider") if model.blank?

      payload = {
        model: model,
        messages: [ { role: "user", content: @test_config[:test_message] } ],
        max_tokens: 50
      }

      response = make_http_request(
        "https://api.openai.com/v1/chat/completions",
        method: :post,
        headers: headers,
        body: payload.to_json
      )

      parse_openai_response(response)
    end

    def perform_anthropic_connection_test(config)
      api_key = config["api_key"]
      return error_result("authentication_error", "API key not configured") unless api_key

      headers = {
        "x-api-key" => api_key,
        "anthropic-version" => "2023-06-01",
        "Content-Type" => "application/json"
      }

      model = resolved_test_model(config)
      return error_result("configuration_error", "No model configured for this provider") if model.blank?

      payload = {
        model: model,
        messages: [ { role: "user", content: @test_config[:test_message] } ],
        max_tokens: 50
      }

      response = make_http_request(
        "https://api.anthropic.com/v1/messages",
        method: :post,
        headers: headers,
        body: payload.to_json
      )

      parse_anthropic_response(response)
    end

    def perform_ollama_connection_test(config)
      base_url = build_ollama_base_url(config)

      # Build headers - include API key if provided (for Open WebUI authentication)
      headers = { "Content-Type" => "application/json" }
      api_key = config["api_key"]
      if api_key.present?
        headers["Authorization"] = "Bearer #{api_key}"
      end

      # First try a lightweight /api/tags check (fast, no model load needed)
      tags_url = build_ollama_api_url(base_url, "/api/tags")
      tags_response = make_http_request(tags_url, method: :get, headers: headers, timeout: 15)

      if tags_response.success?
        # Tags endpoint works — parse available models
        models_data = JSON.parse(tags_response.body) rescue {}
        available_models = models_data["models"] || []
        return {
          success: true,
          status_code: tags_response.code,
          response_content: "#{available_models.size} models available",
          provider_response: tags_response.body
        }
      end

      # Fall back to a chat test when the tags endpoint is not available. The
      # model comes from the credential or the provider (#resolved_test_model),
      # never a literal (E3b): "llama2" was the wrong id for any server that
      # had not pulled it, so the test reported a bad connection for a reason
      # that had nothing to do with the connection. Nothing configured is a
      # configuration_error, exactly as for the openai and anthropic testers,
      # and the tags check above still passes without any model at all.
      test_model = resolved_test_model(config)
      return error_result("configuration_error", "No model configured for this provider") if test_model.blank?

      payload = {
        model: test_model,
        messages: [ { role: "user", content: @test_config[:test_message] } ],
        stream: false
      }

      api_url = build_ollama_api_url(base_url, "/api/chat")

      response = make_http_request(
        api_url,
        method: :post,
        headers: headers,
        body: payload.to_json,
        timeout: 30
      )

      parse_ollama_response(response)
    end

    def build_ollama_base_url(config)
      # Priority: credentials base_url > provider api_base_url > localhost fallback
      url = config["base_url"].presence || @provider&.api_base_url.presence || "http://localhost:11434"
      url.to_s.chomp("/")
    end

    def build_ollama_api_url(base_url, endpoint)
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

    def perform_generic_connection_test(_config)
      { success: true, response_content: "Generic test successful", provider_response: {} }
    end

    def parse_openai_response(response)
      if response.code == 0 && response.message.to_s.include?("timeout")
        return { success: false, timeout: true, error_type: "network_timeout", error_details: response.message }
      end

      if response.success?
        begin
          data = JSON.parse(response.body)
          unless data.is_a?(Hash) && data["choices"].is_a?(Array) && data["choices"].first.is_a?(Hash)
            return { success: false, error_type: "invalid_response", error_details: "Malformed response structure" }
          end
          content = data.dig("choices", 0, "message", "content") || ""
          { success: true, status_code: response.code, response_content: content, provider_response: data.to_json }
        rescue JSON::ParserError
          { success: false, error_type: "invalid_response", error_details: "Invalid JSON response" }
        end
      else
        parse_error_response(response)
      end
    end

    def parse_anthropic_response(response)
      if response.success?
        data = JSON.parse(response.body) rescue {}
        content = data.dig("content", 0, "text") || ""
        { success: true, status_code: response.code, response_content: content, provider_response: data.to_json }
      else
        parse_error_response(response)
      end
    end

    def parse_ollama_response(response)
      if response.success?
        data = JSON.parse(response.body) rescue {}
        content = data.dig("message", "content") || ""
        { success: true, status_code: response.code, response_content: content, provider_response: data.to_json }
      else
        parse_error_response(response)
      end
    end

    def parse_error_response(response)
      error_data = JSON.parse(response.body) rescue {}
      error_message = error_data.dig("error", "code") || error_data.dig("error", "message") || response.message

      error_type = case response.code
      when 401 then "authentication_error"
      when 429
        retry_after = response.instance_variable_get(:@response)&.dig("Retry-After")&.to_i || 60
        return {
          success: false,
          status_code: response.code,
          error_type: "rate_limit_exceeded",
          error_details: error_message,
          retry_after: retry_after
        }
      when 500..599 then "server_error"
      else "invalid_response"
      end

      { success: false, status_code: response.code, error_type: error_type, error_details: error_message }
    end
  end
end
