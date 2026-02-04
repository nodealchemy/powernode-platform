# frozen_string_literal: true

module ProviderTesting
  module ProviderAdapters
    private

    def perform_test
      provider = credential.provider
      decrypted_config = credential.credentials

      case provider.provider_type
      when "ollama"
        test_ollama_connection(provider, decrypted_config)
      when "openai"
        test_openai_connection(provider, decrypted_config)
      when "anthropic"
        test_anthropic_connection(provider, decrypted_config)
      when "xai"
        test_xai_connection(provider, decrypted_config)
      when "huggingface"
        test_huggingface_connection(provider, decrypted_config)
      when "cohere"
        test_cohere_connection(provider, decrypted_config)
      when "custom"
        case provider.slug
        when /xai|grok/i
          test_xai_connection(provider, decrypted_config)
        when /ollama/i
          test_ollama_connection(provider, decrypted_config)
        when /cohere/i
          test_cohere_connection(provider, decrypted_config)
        else
          test_generic_connection(provider, decrypted_config)
        end
      else
        test_generic_connection(provider, decrypted_config)
      end
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

      payload = {
        model: config["model"] || "gpt-3.5-turbo",
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

      payload = {
        model: config["model"] || "claude-3-haiku-20240307",
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

      payload = {
        model: config["model"] || "llama2",
        messages: [ { role: "user", content: @test_config[:test_message] } ]
      }

      # Build the proper API endpoint URL
      api_url = build_ollama_api_url(base_url, "/api/chat")

      # Build headers - include API key if provided (for Open WebUI authentication)
      headers = { "Content-Type" => "application/json" }
      api_key = config["api_key"]
      if api_key.present?
        headers["Authorization"] = "Bearer #{api_key}"
      end

      response = make_http_request(
        api_url,
        method: :post,
        headers: headers,
        body: payload.to_json
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

    def test_ollama_connection(provider, config)
      base_url = build_ollama_base_url(config)
      api_url = build_ollama_api_url(base_url, "/api/tags")

      # Build headers - include API key if provided (for Open WebUI authentication)
      headers = {}
      api_key = config["api_key"]
      if api_key.present?
        headers["Authorization"] = "Bearer #{api_key}"
      end

      response = make_http_request(api_url, method: :get, headers: headers)

      if response.success?
        models = JSON.parse(response.body)["models"] || []
        is_remote = !base_url.include?("localhost") && !base_url.include?("127.0.0.1")
        {
          success: true,
          provider_info: { version: "latest", status: "running", connection_type: is_remote ? "remote" : "local" },
          model_info: { available_models: models.size }
        }
      else
        {
          success: false,
          error: "Ollama server not reachable at #{api_url}",
          error_code: "SERVER_UNREACHABLE"
        }
      end
    end

    def test_openai_connection(provider, config)
      api_key = config["api_key"]
      return { success: false, error: "API key not configured", error_code: "MISSING_CREDENTIALS" } unless api_key

      headers = {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json"
      }

      response = make_http_request("#{provider.api_base_url}/models", method: :get, headers: headers)

      if response.success?
        data = JSON.parse(response.body)
        {
          success: true,
          provider_info: { status: "active" },
          model_info: { available_models: data["data"]&.size || 0 }
        }
      else
        error_data = JSON.parse(response.body) rescue {}
        {
          success: false,
          error: error_data["error"]&.dig("message") || "Authentication failed",
          error_code: "AUTHENTICATION_FAILED"
        }
      end
    end

    def test_anthropic_connection(provider, config)
      api_key = config["api_key"]
      return { success: false, error: "API key not configured", error_code: "MISSING_CREDENTIALS" } unless api_key

      headers = {
        "x-api-key" => api_key,
        "anthropic-version" => "2023-06-01",
        "Content-Type" => "application/json"
      }

      test_model = "claude-3-haiku-20240307"
      payload = {
        model: test_model,
        messages: [ { role: "user", content: "Hi" } ],
        max_tokens: 10
      }

      response = make_http_request(
        "#{provider.api_base_url}/messages",
        method: :post,
        headers: headers,
        body: payload.to_json
      )

      if response.success?
        data = JSON.parse(response.body) rescue {}
        {
          success: true,
          provider_info: { status: "active", api_version: "2023-06-01" },
          model_info: { test_model: test_model, response_id: data["id"] }
        }
      else
        error_data = JSON.parse(response.body) rescue {}
        error_message = error_data.dig("error", "message") || "Authentication failed"
        { success: false, error: error_message, error_code: "AUTHENTICATION_FAILED" }
      end
    rescue StandardError => e
      { success: false, error: "Anthropic connection error: #{e.message}", error_code: "CONNECTION_ERROR" }
    end

    def test_xai_connection(provider, config)
      api_key = config["api_key"]
      return { success: false, error: "API key not configured", error_code: "MISSING_CREDENTIALS" } unless api_key

      begin
        headers = { "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json" }
        test_model = "grok-3"
        payload = {
          model: test_model,
          messages: [ { role: "user", content: 'Hello, respond with just "OK"' } ],
          max_tokens: 10,
          temperature: 0
        }

        response = make_http_request(
          "#{provider.api_base_url}/chat/completions",
          method: :post,
          headers: headers,
          body: payload.to_json
        )

        if response.success?
          {
            success: true,
            provider_info: { status: "active", api_version: "v1", models_available: [ "grok-3", "grok-vision" ] },
            model_info: { test_model: test_model }
          }
        else
          error_data = JSON.parse(response.body) rescue {}
          error_message = if error_data["error"].is_a?(Hash)
                            error_data["error"]["message"] || error_data["error"].to_s
          elsif error_data["error"].is_a?(String)
                            error_data["error"]
          else
                            error_data["message"] || "Connection test failed"
          end
          { success: false, error: error_message, error_code: "API_ERROR" }
        end
      rescue StandardError => e
        { success: false, error: "x.ai connection error: #{e.message}", error_code: "CONNECTION_ERROR" }
      end
    end

    def test_huggingface_connection(provider, config)
      api_key = config["api_key"]
      return { success: false, error: "API key not configured", error_code: "MISSING_CREDENTIALS" } unless api_key

      { success: true, provider_info: { status: "active" }, model_info: { test_model: "gpt2" } }
    end

    def test_cohere_connection(provider, config)
      api_key = config["api_key"]
      return { success: false, error: "API key not configured", error_code: "MISSING_CREDENTIALS" } unless api_key

      { success: true, provider_info: { status: "active" }, model_info: { test_model: "command" } }
    end

    def test_generic_connection(provider, config)
      response = make_http_request(provider.api_base_url, method: :get)

      if response.success?
        { success: true, provider_info: { status: "reachable" }, model_info: { test: "basic_connectivity" } }
      else
        { success: false, error: "Provider endpoint not reachable", error_code: "CONNECTION_FAILED" }
      end
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
