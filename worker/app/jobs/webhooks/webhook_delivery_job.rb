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
    # IMP-3e7c104f2b36: the server trims and serializes the payload and signs
    # those exact bytes; the worker never sees the signing secret, so it must send
    # this body unchanged.
    body = delivery_data['body']
    signature_headers = delivery_data['signature_headers'] || {}
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

    # A delivery the server did not sign is not sent: receivers are told to
    # verify every delivery, and an unsigned one would fail that check or teach
    # them to skip it. Retried, so it goes out once the server signs it.
    if body.nil? || signature_headers['X-Powernode-Signature'].blank?
      log_error "Webhook delivery #{delivery_id} has no server-signed body; not sending"
      mark_delivery_status(delivery_id, 'failed', {
        error_message: 'Delivery was not signed by the server',
        error_category: 'unsigned_delivery'
      })
      schedule_retry(delivery_id, delivery_attempt) if delivery_attempt < 5
      return { success: false, error: 'Unsigned delivery' }
    end

    log_info "Delivering webhook to: #{webhook_url} (attempt #{delivery_attempt})"

    # SSRF guard: refuse outbound delivery to internal/metadata/private targets.
    # Record as a permanent failure and return WITHOUT scheduling a retry — the
    # destination is blocked by policy, so retrying would never succeed.
    vetted_target = Security::WebhookUrlGuard.vetted_target(webhook_url)
    unless vetted_target
      log_error "[Webhook] blocked SSRF target #{webhook_url}"
      mark_delivery_status(delivery_id, 'failed', {
        error_message: "Blocked SSRF target (internal/private destination): #{webhook_url}",
        error_category: 'blocked_ssrf'
      })
      record_endpoint_result(endpoint_id, false) if endpoint_id
      return { success: false, error: 'Blocked SSRF target', blocked: true }
    end

    # Mark delivery as in_progress
    mark_delivery_status(delivery_id, 'in_progress')

    # Merge custom headers with standard headers
    merged_headers = headers.merge(custom_headers)

    # Make the HTTP request
    result = deliver_webhook(vetted_target, body, merged_headers, signature_headers)

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

  def deliver_webhook(vetted_target, body, headers, signature_headers)
    require 'net/http'
    require 'uri'

    start_time = Time.current

    uri = vetted_target.uri
    http = Net::HTTP.new(uri.host, uri.port)
    # Pin the socket to the IP the guard actually vetted (Host header + TLS SNI
    # stay on uri.host) so a DNS rebind between check and connect cannot point
    # this request at an internal address. ip is nil only for opted-in trusted
    # hosts the guard couldn't pre-resolve — those fall back to normal resolution.
    http.ipaddr = vetted_target.ip if vetted_target.ip
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 5
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request['User-Agent'] = 'Powernode-Webhook/1.0'

    # Add all headers (including custom headers)
    headers.each do |key, value|
      # Skip headers that might conflict with our standard headers
      next if %w[content-type user-agent host content-length].include?(key.to_s.downcase)

      request[key] = value.to_s
    end
    # Applied LAST, so an endpoint's configured headers can never replace the
    # server's signature (Net::HTTP#[]= overwrites).
    signature_headers.each { |key, value| request[key] = value.to_s }

    request.body = body

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
