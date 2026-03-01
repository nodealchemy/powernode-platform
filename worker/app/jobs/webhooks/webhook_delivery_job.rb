# frozen_string_literal: true

# Generic webhook delivery job for app webhooks and MCP webhooks
# Supports: custom headers, circuit breaker pattern, payload detail levels, enhanced diagnostics
class Webhooks::WebhookDeliveryJob < BaseJob
  sidekiq_options queue: 'webhooks', retry: 3

  def execute(delivery_id)
    log_info "Processing webhook delivery: #{delivery_id}"

    # Fetch delivery details from backend
    delivery_response = api_client.get("/api/v1/internal/webhook_deliveries/#{delivery_id}")

    unless delivery_response['success']
      log_error "Failed to fetch delivery details: #{delivery_response['error']}"
      return { success: false, error: delivery_response['error'] }
    end

    delivery_data = delivery_response['data']
    webhook_url = delivery_data['webhook_url']
    payload = delivery_data['payload']
    headers = delivery_data['headers'] || {}
    custom_headers = delivery_data['custom_headers'] || {}
    delivery_attempt = delivery_data['attempt'] || 1
    endpoint_id = delivery_data['endpoint_id']

    # Check circuit breaker status
    if delivery_data['circuit_broken']
      log_info "Webhook endpoint circuit is open, skipping delivery: #{delivery_id}"
      mark_delivery_status(delivery_id, 'skipped', {
        error_message: "Circuit breaker is open",
        circuit_cooldown_until: delivery_data['circuit_cooldown_until']
      })
      return { success: false, error: "Circuit breaker is open", skipped: true }
    end

    # Apply payload detail level trimming if specified
    payload = apply_payload_trimming(payload, delivery_data['payload_detail_level'])

    log_info "Delivering webhook to: #{webhook_url} (attempt #{delivery_attempt})"

    # Mark delivery as in_progress
    mark_delivery_status(delivery_id, 'in_progress')

    # Merge custom headers with standard headers
    merged_headers = headers.merge(custom_headers)

    # Make the HTTP request
    result = deliver_webhook(webhook_url, payload, merged_headers)

    if result[:success]
      log_info "Webhook delivered successfully: #{delivery_id}"
      mark_delivery_status(delivery_id, 'delivered', {
        status_code: result[:status_code],
        response_body: result[:response_body],
        response_time_ms: result[:response_time_ms],
        response_headers: result[:response_headers]
      })

      # Record success for circuit breaker
      record_endpoint_result(endpoint_id, true) if endpoint_id

      { success: true, delivery_id: delivery_id, status_code: result[:status_code], response_time_ms: result[:response_time_ms] }
    else
      log_error "Webhook delivery failed: #{result[:error]}"
      mark_delivery_status(delivery_id, 'failed', {
        error_message: result[:error],
        status_code: result[:status_code],
        response_body: result[:response_body],
        response_time_ms: result[:response_time_ms],
        error_category: categorize_error(result)
      })

      # Record failure for circuit breaker
      record_endpoint_result(endpoint_id, false) if endpoint_id

      # Schedule retry if within retry limits
      if delivery_attempt < 5
        schedule_retry(delivery_id, delivery_attempt)
      end

      { success: false, error: result[:error], response_time_ms: result[:response_time_ms] }
    end
  rescue StandardError => e
    log_error "Webhook delivery job failed: #{e.message}"
    mark_delivery_status(delivery_id, 'failed', {
      error_message: e.message,
      error_category: 'internal_error'
    })
    { success: false, error: e.message }
  end

  private

  def deliver_webhook(url, payload, headers)
    require 'net/http'
    require 'uri'

    start_time = Time.current

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 5
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request['User-Agent'] = 'Powernode-Webhook/1.0'
    request['X-Powernode-Delivery-Timestamp'] = Time.current.to_i.to_s

    # Add all headers (including custom headers)
    headers.each do |key, value|
      # Skip headers that might conflict with our standard headers
      next if %w[content-type user-agent host content-length].include?(key.to_s.downcase)
      request[key] = value.to_s
    end

    request.body = payload.is_a?(String) ? payload : payload.to_json

    response = http.request(request)
    response_time_ms = ((Time.current - start_time) * 1000).round

    # Capture response headers
    response_headers = {}
    response.each_header { |k, v| response_headers[k] = v }

    if response.code.to_i.between?(200, 299)
      {
        success: true,
        status_code: response.code.to_i,
        response_body: response.body&.slice(0, 1000), # Limit stored response
        response_time_ms: response_time_ms,
        response_headers: response_headers
      }
    else
      {
        success: false,
        error: "HTTP #{response.code}: #{response.message}",
        status_code: response.code.to_i,
        response_body: response.body&.slice(0, 1000),
        response_time_ms: response_time_ms,
        response_headers: response_headers
      }
    end
  rescue Net::OpenTimeout => e
    response_time_ms = ((Time.current - start_time) * 1000).round
    {
      success: false,
      error: "Connection timeout: #{e.message}",
      status_code: nil,
      response_body: nil,
      response_time_ms: response_time_ms,
      error_type: 'connection_timeout'
    }
  rescue Net::ReadTimeout => e
    response_time_ms = ((Time.current - start_time) * 1000).round
    {
      success: false,
      error: "Read timeout: #{e.message}",
      status_code: nil,
      response_body: nil,
      response_time_ms: response_time_ms,
      error_type: 'read_timeout'
    }
  rescue SocketError => e
    response_time_ms = ((Time.current - start_time) * 1000).round
    {
      success: false,
      error: "DNS/Socket error: #{e.message}",
      status_code: nil,
      response_body: nil,
      response_time_ms: response_time_ms,
      error_type: 'dns_error'
    }
  rescue Errno::ECONNREFUSED => e
    response_time_ms = ((Time.current - start_time) * 1000).round
    {
      success: false,
      error: "Connection refused: #{e.message}",
      status_code: nil,
      response_body: nil,
      response_time_ms: response_time_ms,
      error_type: 'connection_refused'
    }
  rescue Errno::ECONNRESET => e
    response_time_ms = ((Time.current - start_time) * 1000).round
    {
      success: false,
      error: "Connection reset: #{e.message}",
      status_code: nil,
      response_body: nil,
      response_time_ms: response_time_ms,
      error_type: 'connection_reset'
    }
  rescue OpenSSL::SSL::SSLError => e
    response_time_ms = ((Time.current - start_time) * 1000).round
    {
      success: false,
      error: "SSL error: #{e.message}",
      status_code: nil,
      response_body: nil,
      response_time_ms: response_time_ms,
      error_type: 'ssl_error'
    }
  rescue StandardError => e
    response_time_ms = ((Time.current - start_time) * 1000).round rescue nil
    {
      success: false,
      error: "Delivery error: #{e.message}",
      status_code: nil,
      response_body: nil,
      response_time_ms: response_time_ms,
      error_type: 'unknown_error'
    }
  end

  def apply_payload_trimming(payload, detail_level)
    return payload if detail_level.blank? || detail_level == 'full'

    case detail_level
    when 'minimal'
      trim_payload_minimal(payload)
    when 'ids_only'
      trim_payload_ids_only(payload)
    else
      payload
    end
  end

  def trim_payload_minimal(payload)
    return {} unless payload.is_a?(Hash)

    {
      event_type: payload['event_type'] || payload[:event_type],
      timestamp: payload['timestamp'] || payload[:timestamp] || Time.current.iso8601,
      id: payload['id'] || payload[:id],
      action: payload['action'] || payload[:action],
      account_id: payload['account_id'] || payload[:account_id]
    }.compact
  end

  def trim_payload_ids_only(payload)
    return {} unless payload.is_a?(Hash)

    extract_ids(payload)
  end

  def extract_ids(obj, prefix = '')
    result = {}
    return result unless obj.is_a?(Hash)

    obj.each do |key, value|
      key_str = key.to_s
      full_key = prefix.empty? ? key_str : "#{prefix}_#{key_str}"

      if key_str.end_with?('_id') || key_str == 'id'
        result[full_key] = value
      elsif value.is_a?(Hash)
        result.merge!(extract_ids(value, full_key))
      end
    end
    result
  end

  def categorize_error(result)
    return result[:error_type] if result[:error_type]

    status = result[:status_code]
    return 'unknown' unless status

    case status
    when 400..499
      'client_error'
    when 500..599
      'server_error'
    else
      'http_error'
    end
  end

  def record_endpoint_result(endpoint_id, success)
    return unless endpoint_id

    with_api_retry do
      if success
        api_client.post("/api/v1/internal/webhook_endpoints/#{endpoint_id}/record_success")
      else
        api_client.post("/api/v1/internal/webhook_endpoints/#{endpoint_id}/record_failure")
      end
    end
  rescue StandardError => e
    log_error "Failed to record endpoint result: #{e.message}"
  end

  def mark_delivery_status(delivery_id, status, metadata = {})
    with_api_retry do
      api_client.patch("/api/v1/internal/webhook_deliveries/#{delivery_id}", {
        status: status,
        metadata: metadata
      })
    end
  rescue StandardError => e
    log_error "Failed to update delivery status: #{e.message}"
  end

  def schedule_retry(delivery_id, current_attempt)
    # Exponential backoff: 1min, 5min, 15min, 1hr
    delays = [1.minute, 5.minutes, 15.minutes, 1.hour]
    delay = delays[current_attempt - 1] || 1.hour

    log_info "Scheduling retry for delivery #{delivery_id} in #{delay} seconds"

    Webhooks::WebhookRetryJob.perform_in(delay, delivery_id)
  rescue StandardError => e
    log_error "Failed to schedule retry: #{e.message}"
  end
end
