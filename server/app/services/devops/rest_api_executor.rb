# frozen_string_literal: true

module Devops
  class RestApiExecutor < BaseExecutor
    SUPPORTED_METHODS = %w[GET POST PUT PATCH DELETE HEAD OPTIONS].freeze
    DEFAULT_CONTENT_TYPE = "application/json"

    # Execute a REST API call
    def perform_execution(input)
      endpoint = build_endpoint(input)
      method = determine_method(input)
      headers = build_headers(input)
      body = build_body(input, method)

      validate_endpoint!(endpoint)

      with_retry(max_attempts: effective_configuration.fetch(:max_retries, 3)) do
        response = execute_request(method, endpoint, headers, body)

        result = {
          success: response.status.success?,
          status_code: response.status.code,
          headers: safe_response_headers(response),
          body: parse_response(response),
          endpoint: endpoint,
          method: method,
          executed_at: Time.current.iso8601
        }

        # Apply response transformation if configured
        if effective_configuration[:response_transform].present?
          result[:body] = transform_response(result[:body])
        end

        result
      end
    end

    def perform_connection_test
      test_endpoint = effective_configuration[:test_endpoint] || effective_configuration[:base_url]
      return { success: false, error: "No base URL configured" } unless test_endpoint.present?

      response = build_client.head(test_endpoint)

      if response.status.success? || response.status.code == 405
        { success: true, message: "Successfully connected to API" }
      else
        { success: false, error: "API returned status #{response.status.code}" }
      end
    rescue HTTP::Error => e
      { success: false, error: "Connection failed: #{e.message}" }
    end

    private

    def base_url
      effective_configuration[:base_url]
    end

    def build_endpoint(input)
      path = input[:path] || input[:endpoint] || ""
      base = base_url || ""

      # Handle path parameters
      if input[:path_params].present?
        input[:path_params].each do |key, value|
          path = path.gsub(":#{key}", value.to_s)
          path = path.gsub("{#{key}}", value.to_s)
        end
      end

      endpoint = if base.present? && path.present?
        URI.join(base.chomp("/") + "/", path.sub(%r{^/}, "")).to_s
      elsif base.present?
        base
      else
        path
      end

      # Add query parameters
      if input[:query].present? || input[:query_params].present?
        query = (input[:query] || input[:query_params]).to_h
        uri = URI.parse(endpoint)
        existing_query = URI.decode_www_form(uri.query || "").to_h
        uri.query = URI.encode_www_form(existing_query.merge(query))
        endpoint = uri.to_s
      end

      endpoint
    end

    def determine_method(input)
      method = (input[:method] || effective_configuration[:default_method] || "GET").to_s.upcase

      unless SUPPORTED_METHODS.include?(method)
        raise ConfigurationError, "Unsupported HTTP method: #{method}"
      end

      method
    end

    def build_headers(input)
      headers = default_api_headers
      headers = headers.merge(effective_configuration[:headers] || {})
      headers = headers.merge(input[:headers] || {})

      # Add authentication
      headers = add_authentication(headers)

      headers
    end

    def default_api_headers
      {
        "Content-Type" => effective_configuration[:content_type] || DEFAULT_CONTENT_TYPE,
        "Accept" => effective_configuration[:accept] || "application/json",
        "User-Agent" => "Powernode-API-Client/1.0"
      }
    end

    def add_authentication(headers)
      auth_type = effective_configuration[:auth_type] || credential&.credential_type

      case auth_type
      when "bearer_token", "oauth2"
        token = decrypted_credentials[:token] ||
                decrypted_credentials[:access_token] ||
                decrypted_credentials[:bearer_token]
        headers["Authorization"] = "Bearer #{token}" if token.present?

      when "api_key"
        api_key = decrypted_credentials[:api_key]
        if api_key.present?
          location = effective_configuration[:api_key_location] || "header"
          case location
          when "header"
            header_name = effective_configuration[:api_key_header] || "X-API-Key"
            headers[header_name] = api_key
          when "query"
            # Query params handled in build_endpoint
          end
        end

      when "basic"
        username = decrypted_credentials[:username]
        password = decrypted_credentials[:password]
        if username.present?
          credentials = Base64.strict_encode64("#{username}:#{password}")
          headers["Authorization"] = "Basic #{credentials}"
        end

      when "custom"
        # Allow custom header-based authentication
        if effective_configuration[:auth_header].present?
          header_name = effective_configuration[:auth_header][:name]
          header_value = effective_configuration[:auth_header][:value]
          # Replace placeholders with credential values
          decrypted_credentials.each do |key, value|
            header_value = header_value.gsub("{{#{key}}}", value.to_s)
          end
          headers[header_name] = header_value
        end
      end

      headers
    end

    def build_body(input, method)
      return nil if %w[GET HEAD DELETE OPTIONS].include?(method)

      body = input[:body] || input[:data]
      return nil if body.blank?

      content_type = effective_configuration[:content_type] || DEFAULT_CONTENT_TYPE

      # Apply request transformation if configured
      if effective_configuration[:request_transform].present?
        body = transform_request(body)
      end

      case content_type
      when /json/
        body.is_a?(String) ? body : body.to_json
      when /form-urlencoded/
        body.is_a?(String) ? body : URI.encode_www_form(body.to_h)
      when /multipart/
        body # Let HTTP library handle multipart
      when /xml/
        body.to_s
      else
        body.is_a?(String) ? body : body.to_json
      end
    end

    def validate_endpoint!(endpoint)
      uri = URI.parse(endpoint)

      unless %w[http https].include?(uri.scheme)
        raise ConfigurationError, "Invalid URL scheme: #{uri.scheme}"
      end

      # Security: Check for blocked hosts
      blocked = effective_configuration[:blocked_hosts] || []
      if blocked.include?(uri.host)
        raise ConfigurationError, "Host not allowed: #{uri.host}"
      end

      # Security: Check for internal IPs if configured
      if effective_configuration[:block_internal_ips]
        if internal_ip?(uri.host)
          raise ConfigurationError, "Internal IPs not allowed"
        end
      end

      true
    rescue URI::InvalidURIError => e
      raise ConfigurationError, "Invalid endpoint URL: #{e.message}"
    end

    def internal_ip?(host)
      return true if %w[localhost 127.0.0.1 0.0.0.0].include?(host)

      begin
        ip = IPAddr.new(host)
        ip.private? || ip.loopback? || ip.link_local?
      rescue IPAddr::InvalidAddressError
        false
      end
    end

    def execute_request(method, endpoint, headers, body)
      client = build_client.headers(headers)

      case method
      when "GET"
        client.get(endpoint)
      when "POST"
        client.post(endpoint, body: body)
      when "PUT"
        client.put(endpoint, body: body)
      when "PATCH"
        client.patch(endpoint, body: body)
      when "DELETE"
        client.delete(endpoint)
      when "HEAD"
        client.head(endpoint)
      when "OPTIONS"
        client.options(endpoint)
      end
    rescue HTTP::TimeoutError
      raise TimeoutError, "Request timed out"
    rescue HTTP::ConnectionError => e
      raise ExecutionError, "Connection failed: #{e.message}"
    end

    def build_client
      client = HTTP.timeout(
        connect: connect_timeout,
        read: read_timeout,
        write: effective_configuration.fetch(:write_timeout, 30)
      )

      # Configure redirects
      max_redirects = effective_configuration.fetch(:max_redirects, 5)
      client = client.follow(max_hops: max_redirects) if max_redirects > 0

      # Configure SSL verification
      unless effective_configuration[:verify_ssl] == false
        client = client.ssl_context(ssl_context)
      end

      client
    end

    def ssl_context
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER

      # Add custom CA if configured
      if effective_configuration[:ca_cert].present?
        ctx.ca_file = effective_configuration[:ca_cert]
      end

      ctx
    end

    def safe_response_headers(response)
      # Only include safe headers in response
      safe_headers = %w[
        content-type content-length date server
        x-request-id x-correlation-id
        x-ratelimit-limit x-ratelimit-remaining x-ratelimit-reset
        cache-control etag last-modified
      ]

      response.headers.to_h.select { |k, _| safe_headers.include?(k.downcase) }
    end

    def parse_response(response)
      body = response.body.to_s
      return nil if body.blank?

      content_type = response.content_type.mime_type rescue nil

      case content_type
      when /json/
        JSON.parse(body)
      when /xml/
        # Could add XML parsing here
        body
      when /text/
        body.truncate(50_000)
      else
        # Try JSON parsing first, fall back to raw
        begin
          JSON.parse(body)
        rescue JSON::ParserError
          body.truncate(50_000)
        end
      end
    end

    def transform_request(body)
      transform = effective_configuration[:request_transform]
      return body unless transform.is_a?(Hash)

      apply_transform(body, transform)
    end

    def transform_response(body)
      transform = effective_configuration[:response_transform]
      return body unless transform.is_a?(Hash)

      apply_transform(body, transform)
    end

    def apply_transform(data, transform)
      return data unless data.is_a?(Hash)

      result = {}

      transform.each do |target_key, source_path|
        value = dig_path(data, source_path.to_s.split("."))
        result[target_key.to_s] = value if value.present?
      end

      result
    end

    def dig_path(data, path)
      path.reduce(data) do |current, key|
        return nil unless current.is_a?(Hash)

        current[key] || current[key.to_sym]
      end
    end
  end
end
