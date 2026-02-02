# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Mcp
  module NodeExecutors
    # API Call node executor - makes HTTP requests to external APIs
    #
    # Configuration options:
    #   url: Target URL (supports {{variable}} interpolation)
    #   method: HTTP method (GET, POST, PUT, PATCH, DELETE) default: GET
    #   headers: Hash of headers (supports {{variable}} interpolation)
    #   body: Request body (supports {{variable}} interpolation)
    #   body_type: "json", "form", "raw" (default: "json")
    #   timeout_seconds: Request timeout (default: 30)
    #   response_mapping: Dot notation path to extract from response
    #   retry_count: Number of retries on failure (default: 0)
    #   retry_delay_seconds: Delay between retries (default: 1)
    #
    class ApiCall < Base
      ALLOWED_METHODS = %w[GET POST PUT PATCH DELETE HEAD OPTIONS].freeze
      DEFAULT_TIMEOUT_SECONDS = 30
      DEFAULT_RETRY_COUNT = 0
      DEFAULT_RETRY_DELAY_SECONDS = 1
      MAX_RETRY_COUNT = 5

      protected

      def perform_execution
        log_info "Making API call"

        # Get configuration
        url = resolve_template(configuration["url"])
        method = (configuration["method"] || "GET").upcase
        headers = resolve_headers(configuration["headers"] || {})
        body = resolve_body(configuration["body"], configuration["body_type"])
        timeout_seconds = (configuration["timeout_seconds"] || DEFAULT_TIMEOUT_SECONDS).to_i
        response_mapping = configuration["response_mapping"]
        retry_count = [ (configuration["retry_count"] || DEFAULT_RETRY_COUNT).to_i, MAX_RETRY_COUNT ].min
        retry_delay = (configuration["retry_delay_seconds"] || DEFAULT_RETRY_DELAY_SECONDS).to_f

        # Validate configuration
        unless ALLOWED_METHODS.include?(method)
          return error_result("Invalid HTTP method: #{method}")
        end

        if url.blank?
          return error_result("URL is required")
        end

        # Parse URL
        uri = parse_url(url)
        return error_result("Invalid URL: #{url}") unless uri

        log_info "#{method} #{uri.host}#{uri.path}"

        # Execute request with retries
        start_time = Time.current
        response = nil
        last_error = nil
        attempts = 0

        (retry_count + 1).times do |attempt|
          attempts = attempt + 1
          begin
            response = execute_request(uri, method, headers, body, timeout_seconds)
            break if response[:success] || !retryable_error?(response)

            last_error = response[:error]
          rescue StandardError => e
            last_error = e.message
          end

          # Wait before retry (except on last attempt)
          if attempt < retry_count
            log_debug "Request failed, retrying in #{retry_delay}s (attempt #{attempt + 1}/#{retry_count + 1})"
            sleep(retry_delay)
          end
        end

        response_time_ms = ((Time.current - start_time) * 1000).round

        # Handle failed request
        unless response && response[:success]
          return error_result(
            last_error || "Request failed after #{attempts} attempts",
            response_time_ms: response_time_ms,
            attempts: attempts
          )
        end

        # Parse response
        parsed_response = parse_response(response[:body], response[:content_type])

        # Apply response mapping if configured
        output = if response_mapping.present?
                   extract_mapped_value(parsed_response, response_mapping)
        else
                   parsed_response
        end

        # Store in variable if configured
        if configuration["output_variable"].present?
          set_variable(configuration["output_variable"], output)
        end

        # Industry-standard output format (v1.0)
        {
          output: output,
          data: {
            status_code: response[:status],
            headers: response[:headers],
            response_time_ms: response_time_ms,
            content_type: response[:content_type],
            attempts: attempts
          },
          result: {
            success: true,
            status: response[:status],
            response_size_bytes: response[:body]&.bytesize || 0
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "api_call",
            executed_at: Time.current.iso8601,
            http_method: method,
            url: sanitize_url(uri)
          }
        }
      end

      private

      def parse_url(url)
        URI.parse(url)
      rescue URI::InvalidURIError
        nil
      end

      def resolve_template(template)
        return nil if template.nil?
        return template unless template.is_a?(String)

        template.gsub(/\{\{(\w+(?:\.\w+)*)\}\}/) do
          path = $1
          value = resolve_variable_path(path)
          value.present? ? value.to_s : "{{#{path}}}"
        end
      end

      def resolve_variable_path(path)
        parts = path.split(".")
        value = get_variable(parts.first)

        return value if parts.length == 1 || value.nil?

        # Traverse nested path
        parts[1..].each do |part|
          if value.is_a?(Hash)
            value = value[part] || value[part.to_sym]
          elsif value.respond_to?(part)
            value = value.send(part)
          else
            return nil
          end
          return nil if value.nil?
        end

        value
      end

      def resolve_headers(headers)
        resolved = {}
        headers.each do |key, value|
          resolved[key] = resolve_template(value.to_s)
        end

        # Add default headers
        resolved["User-Agent"] ||= "Powernode-Workflow/1.0"
        resolved["Accept"] ||= "application/json"

        resolved
      end

      def resolve_body(body, body_type)
        return nil if body.blank?

        case body_type
        when "form"
          if body.is_a?(Hash)
            body.transform_values { |v| resolve_template(v.to_s) }
          else
            resolve_template(body.to_s)
          end
        when "raw"
          resolve_template(body.to_s)
        else # json (default)
          if body.is_a?(Hash)
            resolved = body.transform_values do |v|
              if v.is_a?(String)
                resolve_template(v)
              else
                v
              end
            end
            resolved.to_json
          else
            resolve_template(body.to_s)
          end
        end
      end

      def execute_request(uri, method, headers, body, timeout_seconds)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout_seconds
        http.read_timeout = timeout_seconds

        # Build request
        request = build_request(method, uri, headers, body)

        # Execute
        response = http.request(request)

        {
          success: response.is_a?(Net::HTTPSuccess),
          status: response.code.to_i,
          body: response.body,
          headers: response.to_hash,
          content_type: response["content-type"]
        }
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        { success: false, error: "Request timeout: #{e.message}", retryable: true }
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET => e
        { success: false, error: "Connection error: #{e.message}", retryable: true }
      rescue StandardError => e
        { success: false, error: e.message, retryable: false }
      end

      def build_request(method, uri, headers, body)
        path = uri.request_uri

        request = case method
        when "GET"    then Net::HTTP::Get.new(path)
        when "POST"   then Net::HTTP::Post.new(path)
        when "PUT"    then Net::HTTP::Put.new(path)
        when "PATCH"  then Net::HTTP::Patch.new(path)
        when "DELETE" then Net::HTTP::Delete.new(path)
        when "HEAD"   then Net::HTTP::Head.new(path)
        when "OPTIONS" then Net::HTTP::Options.new(path)
        else
                       raise ArgumentError, "Unsupported method: #{method}"
        end

        # Set headers
        headers.each { |k, v| request[k] = v }

        # Set body for methods that support it
        if body.present? && %w[POST PUT PATCH].include?(method)
          request.body = body
          request["Content-Type"] ||= "application/json"
        end

        request
      end

      def parse_response(body, content_type)
        return nil if body.blank?

        if content_type&.include?("application/json")
          JSON.parse(body)
        elsif content_type&.include?("application/xml") || content_type&.include?("text/xml")
          # Basic XML handling - return as string for now
          # Could use Nokogiri for full XML parsing
          body
        else
          body
        end
      rescue JSON::ParserError => e
        log_debug "Failed to parse JSON response: #{e.message}"
        body
      end

      def extract_mapped_value(data, mapping)
        return data if mapping.blank?

        parts = mapping.split(".")
        result = data

        parts.each do |part|
          if result.is_a?(Hash)
            result = result[part] || result[part.to_sym]
          elsif result.is_a?(Array) && part =~ /^\d+$/
            result = result[part.to_i]
          else
            return nil
          end
          return nil if result.nil?
        end

        result
      end

      def retryable_error?(response)
        return true if response[:retryable]

        # Retry on server errors
        response[:status]&.to_i&.>=(500)
      end

      def sanitize_url(uri)
        # Remove sensitive query parameters for logging
        sanitized = "#{uri.scheme}://#{uri.host}#{uri.path}"
        sanitized += "?..." if uri.query.present?
        sanitized
      end

      def error_result(message, response_time_ms: 0, attempts: 1)
        {
          output: nil,
          data: {
            status_code: nil,
            headers: {},
            response_time_ms: response_time_ms,
            attempts: attempts
          },
          result: {
            success: false,
            error_message: message
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "api_call",
            executed_at: Time.current.iso8601,
            error: true
          }
        }
      end
    end
  end
end
