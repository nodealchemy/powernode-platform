# frozen_string_literal: true

module Integrations
  class WebhookExecutor < BaseExecutor
    SUPPORTED_METHODS = %w[GET POST PUT PATCH DELETE].freeze

    # Execute a webhook call
    def perform_execution(input)
      url = build_url(input)
      method = determine_method(input)
      headers = build_headers(input)
      body = build_body(input)

      validate_url!(url)

      with_retry(max_attempts: effective_configuration.fetch(:max_retries, 3)) do
        response = make_request(method, url, headers, body)

        {
          success: response.status.success?,
          status_code: response.status.code,
          headers: response_headers(response),
          body: parse_response_body(response),
          url: url,
          method: method,
          executed_at: Time.current.iso8601
        }
      end
    end

    def perform_connection_test
      url = effective_configuration[:url] || effective_configuration[:base_url]
      return { success: false, error: "No URL configured" } unless url.present?

      # Use HEAD request for connection test if supported, otherwise GET
      test_method = effective_configuration[:test_method] || "HEAD"

      response = http_client.request(test_method, url)

      if response.status.success? || response.status.code == 405
        { success: true, message: "Successfully connected to #{url}" }
      else
        { success: false, error: "Connection test failed: #{response.status}" }
      end
    rescue HTTP::Error => e
      { success: false, error: "Connection failed: #{e.message}" }
    end

    private

    def build_url(input)
      base_url = effective_configuration[:url] || effective_configuration[:base_url]
      path = input[:path] || ""
      query_params = input[:query_params] || effective_configuration[:default_query_params] || {}

      url = URI.join(base_url, path).to_s

      if query_params.present?
        uri = URI.parse(url)
        existing_params = URI.decode_www_form(uri.query || "").to_h
        uri.query = URI.encode_www_form(existing_params.merge(query_params))
        url = uri.to_s
      end

      url
    end

    def determine_method(input)
      method = (input[:method] || effective_configuration[:method] || "POST").to_s.upcase

      unless SUPPORTED_METHODS.include?(method)
        raise ConfigurationError, "Unsupported HTTP method: #{method}"
      end

      method
    end

    def build_headers(input)
      headers = default_headers.merge(effective_configuration[:headers] || {})
      headers = headers.merge(input[:headers] || {})

      # Add authentication headers
      headers = add_auth_headers(headers)

      # Add custom headers from configuration
      if effective_configuration[:custom_headers].present?
        headers = headers.merge(effective_configuration[:custom_headers])
      end

      headers
    end

    def add_auth_headers(headers)
      auth_type = effective_configuration[:auth_type] || credential&.credential_type

      case auth_type
      when "bearer_token", "oauth2"
        token = decrypted_credentials[:token] || decrypted_credentials[:access_token]
        headers["Authorization"] = "Bearer #{token}" if token.present?
      when "api_key"
        api_key = decrypted_credentials[:api_key]
        header_name = effective_configuration[:api_key_header] || "X-API-Key"
        headers[header_name] = api_key if api_key.present?
      when "basic"
        username = decrypted_credentials[:username]
        password = decrypted_credentials[:password]
        if username.present? && password.present?
          headers["Authorization"] = "Basic #{Base64.strict_encode64("#{username}:#{password}")}"
        end
      end

      headers
    end

    def build_body(input)
      return nil if %w[GET HEAD DELETE].include?(determine_method(input))

      body = input[:body] || input[:data] || effective_configuration[:default_body]
      return nil if body.blank?

      content_type = effective_configuration[:content_type] || "application/json"

      case content_type
      when /json/
        body.is_a?(String) ? body : body.to_json
      when /form-urlencoded/
        body.is_a?(String) ? body : URI.encode_www_form(body)
      else
        body.to_s
      end
    end

    def validate_url!(url)
      uri = URI.parse(url)

      unless %w[http https].include?(uri.scheme)
        raise ConfigurationError, "Invalid URL scheme: #{uri.scheme}"
      end

      # Check for blocked hosts (security)
      blocked_hosts = effective_configuration[:blocked_hosts] || %w[localhost 127.0.0.1 0.0.0.0]
      if blocked_hosts.include?(uri.host)
        raise ConfigurationError, "Host not allowed: #{uri.host}"
      end

      true
    rescue URI::InvalidURIError => e
      raise ConfigurationError, "Invalid URL: #{e.message}"
    end

    def make_request(method, url, headers, body)
      client = HTTP
        .timeout(connect: connect_timeout, read: read_timeout)
        .headers(headers)
        .follow(max_hops: effective_configuration.fetch(:max_redirects, 5))

      case method
      when "GET"
        client.get(url)
      when "POST"
        client.post(url, body: body)
      when "PUT"
        client.put(url, body: body)
      when "PATCH"
        client.patch(url, body: body)
      when "DELETE"
        client.delete(url)
      end
    rescue HTTP::TimeoutError
      raise TimeoutError, "Request timed out after #{read_timeout} seconds"
    rescue HTTP::ConnectionError => e
      raise ExecutionError, "Connection error: #{e.message}"
    end

    def response_headers(response)
      # Only include safe headers
      safe_headers = %w[content-type content-length date server x-request-id]
      response.headers.to_h.select { |k, _| safe_headers.include?(k.downcase) }
    end

    def parse_response_body(response)
      body = response.body.to_s
      return nil if body.blank?

      content_type = response.content_type.mime_type rescue nil

      case content_type
      when /json/
        JSON.parse(body)
      when /xml/
        body # Return raw XML, could add XML parsing if needed
      else
        body.truncate(10_000) # Limit response size
      end
    rescue JSON::ParserError
      body.truncate(10_000)
    end
  end
end
