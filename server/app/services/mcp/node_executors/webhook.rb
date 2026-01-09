# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Mcp
  module NodeExecutors
    # Webhook node executor - sends webhook notifications to external services
    #
    # Configuration options:
    #   url: Webhook endpoint URL (required, supports {{variable}} interpolation)
    #   payload: Payload to send (supports {{variable}} interpolation)
    #   headers: Additional headers (supports {{variable}} interpolation)
    #   timeout_seconds: Request timeout (default: 10)
    #   async: Fire-and-forget mode (default: false)
    #   retry_count: Number of retries on failure (default: 3)
    #   retry_delay_seconds: Delay between retries (default: 2)
    #   signature_secret: Secret for HMAC signature (optional)
    #   signature_header: Header name for signature (default: X-Webhook-Signature)
    #
    class Webhook < Base
      DEFAULT_TIMEOUT_SECONDS = 10
      DEFAULT_RETRY_COUNT = 3
      DEFAULT_RETRY_DELAY_SECONDS = 2
      MAX_RETRY_COUNT = 5
      DEFAULT_SIGNATURE_HEADER = "X-Webhook-Signature"

      protected

      def perform_execution
        log_info "Executing webhook node"

        # Get configuration
        url = resolve_template(configuration["url"])
        payload = build_payload
        headers = resolve_headers(configuration["headers"] || {})
        timeout_seconds = (configuration["timeout_seconds"] || DEFAULT_TIMEOUT_SECONDS).to_i
        async = configuration.fetch("async", false)
        retry_count = [(configuration["retry_count"] || DEFAULT_RETRY_COUNT).to_i, MAX_RETRY_COUNT].min
        retry_delay = (configuration["retry_delay_seconds"] || DEFAULT_RETRY_DELAY_SECONDS).to_f

        # Validate URL
        if url.blank?
          return error_result("Webhook URL is required")
        end

        uri = parse_url(url)
        return error_result("Invalid webhook URL: #{url}") unless uri

        # Add signature if secret is configured
        if configuration["signature_secret"].present?
          signature = generate_signature(payload, configuration["signature_secret"])
          signature_header = configuration["signature_header"] || DEFAULT_SIGNATURE_HEADER
          headers[signature_header] = signature
        end

        # Add webhook metadata headers
        headers["X-Webhook-ID"] = generate_webhook_id
        headers["X-Webhook-Timestamp"] = Time.current.to_i.to_s
        headers["X-Webhook-Source"] = "powernode-workflow"

        log_info "Sending webhook to #{uri.host}#{uri.path}"

        # Execute webhook delivery
        if async
          # Fire-and-forget: schedule async delivery
          schedule_async_delivery(uri, headers, payload, retry_count, retry_delay, timeout_seconds)

          {
            output: { status: "scheduled" },
            result: {
              delivered: false,
              async: true,
              webhook_id: headers["X-Webhook-ID"]
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "webhook",
              executed_at: Time.current.iso8601,
              webhook_url: sanitize_url(uri)
            }
          }
        else
          # Synchronous delivery with retries
          deliver_webhook(uri, headers, payload, retry_count, retry_delay, timeout_seconds)
        end
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

      def build_payload
        payload_config = configuration["payload"]

        # If no explicit payload, use input data
        if payload_config.blank?
          return {
            event: "workflow_webhook",
            data: input_data,
            workflow_run_id: @node_execution&.workflow_run_id,
            node_id: @node.node_id,
            timestamp: Time.current.iso8601
          }.to_json
        end

        # Resolve template variables in payload
        resolved_payload = resolve_payload(payload_config)
        resolved_payload.is_a?(String) ? resolved_payload : resolved_payload.to_json
      end

      def resolve_payload(payload)
        case payload
        when String
          resolve_template(payload)
        when Hash
          payload.transform_values { |v| resolve_payload(v) }
        when Array
          payload.map { |v| resolve_payload(v) }
        else
          payload
        end
      end

      def resolve_headers(headers)
        resolved = {}
        headers.each do |key, value|
          resolved[key] = resolve_template(value.to_s)
        end

        # Default headers
        resolved["Content-Type"] ||= "application/json"
        resolved["User-Agent"] ||= "Powernode-Webhook/1.0"

        resolved
      end

      def generate_signature(payload, secret)
        # HMAC-SHA256 signature
        digest = OpenSSL::Digest.new("sha256")
        signature = OpenSSL::HMAC.hexdigest(digest, secret, payload)
        "sha256=#{signature}"
      end

      def generate_webhook_id
        "whk_#{SecureRandom.hex(16)}"
      end

      def deliver_webhook(uri, headers, payload, retry_count, retry_delay, timeout_seconds)
        start_time = Time.current
        last_error = nil
        last_response = nil
        attempts = 0

        (retry_count + 1).times do |attempt|
          attempts = attempt + 1

          begin
            response = send_request(uri, headers, payload, timeout_seconds)
            last_response = response

            if response[:success]
              response_time_ms = ((Time.current - start_time) * 1000).round

              return {
                output: { status: "sent" },
                result: {
                  delivered: true,
                  response_code: response[:status],
                  attempts: attempts
                },
                data: {
                  response_time_ms: response_time_ms,
                  response_body: response[:body]&.truncate(1000)
                },
                metadata: {
                  node_id: @node.node_id,
                  node_type: "webhook",
                  executed_at: Time.current.iso8601,
                  webhook_url: sanitize_url(uri)
                }
              }
            end

            last_error = response[:error] || "HTTP #{response[:status]}"
          rescue StandardError => e
            last_error = e.message
          end

          # Wait before retry (except on last attempt)
          if attempt < retry_count
            log_debug "Webhook delivery failed, retrying in #{retry_delay}s (attempt #{attempt + 1}/#{retry_count + 1})"
            sleep(retry_delay)
          end
        end

        # All retries exhausted
        response_time_ms = ((Time.current - start_time) * 1000).round

        {
          output: { status: "failed" },
          result: {
            delivered: false,
            response_code: last_response&.dig(:status),
            attempts: attempts,
            error: last_error
          },
          data: {
            response_time_ms: response_time_ms
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "webhook",
            executed_at: Time.current.iso8601,
            webhook_url: sanitize_url(uri),
            error: true
          }
        }
      end

      def send_request(uri, headers, payload, timeout_seconds)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout_seconds
        http.read_timeout = timeout_seconds

        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |k, v| request[k] = v }
        request.body = payload

        response = http.request(request)

        {
          success: response.is_a?(Net::HTTPSuccess),
          status: response.code.to_i,
          body: response.body
        }
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        { success: false, error: "Timeout: #{e.message}", status: nil }
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET => e
        { success: false, error: "Connection error: #{e.message}", status: nil }
      rescue StandardError => e
        { success: false, error: e.message, status: nil }
      end

      def schedule_async_delivery(uri, headers, payload, retry_count, retry_delay, timeout_seconds)
        # Schedule background job for async delivery
        # This would typically use Sidekiq or similar
        if defined?(WebhookDeliveryJob)
          WebhookDeliveryJob.perform_async(
            uri.to_s,
            headers,
            payload,
            retry_count: retry_count,
            retry_delay: retry_delay,
            timeout_seconds: timeout_seconds
          )
        else
          log_debug "Async delivery not available, falling back to synchronous"
          # Fallback to synchronous if job not defined
          Thread.new do
            deliver_webhook(uri, headers, payload, retry_count, retry_delay, timeout_seconds)
          end
        end
      end

      def sanitize_url(uri)
        "#{uri.scheme}://#{uri.host}#{uri.path}"
      end

      def error_result(message)
        {
          output: { status: "error" },
          result: {
            delivered: false,
            error: message
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "webhook",
            executed_at: Time.current.iso8601,
            error: true
          }
        }
      end
    end
  end
end
