# frozen_string_literal: true

# Generic webhook delivery job for app webhooks and MCP webhooks
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
    delivery_attempt = delivery_data['attempt'] || 1

    log_info "Delivering webhook to: #{webhook_url} (attempt #{delivery_attempt})"

    # Mark delivery as in_progress
    mark_delivery_status(delivery_id, 'in_progress')

    # Make the HTTP request
    result = deliver_webhook(webhook_url, payload, headers)

    if result[:success]
      log_info "Webhook delivered successfully: #{delivery_id}"
      mark_delivery_status(delivery_id, 'delivered', {
        status_code: result[:status_code],
        response_body: result[:response_body],
        response_time_ms: result[:response_time_ms]
      })

      { success: true, delivery_id: delivery_id, status_code: result[:status_code] }
    else
      log_error "Webhook delivery failed: #{result[:error]}"
      mark_delivery_status(delivery_id, 'failed', {
        error_message: result[:error],
        status_code: result[:status_code],
        response_body: result[:response_body]
      })

      # Schedule retry if within retry limits
      if delivery_attempt < 5
        schedule_retry(delivery_id, delivery_attempt)
      end

      { success: false, error: result[:error] }
    end
  rescue StandardError => e
    log_error "Webhook delivery job failed: #{e.message}"
    mark_delivery_status(delivery_id, 'failed', { error_message: e.message })
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

    # Add custom headers
    headers.each do |key, value|
      request[key] = value
    end

    request.body = payload.is_a?(String) ? payload : payload.to_json

    response = http.request(request)
    response_time_ms = ((Time.current - start_time) * 1000).round

    if response.code.to_i.between?(200, 299)
      {
        success: true,
        status_code: response.code.to_i,
        response_body: response.body&.slice(0, 1000), # Limit stored response
        response_time_ms: response_time_ms
      }
    else
      {
        success: false,
        error: "HTTP #{response.code}: #{response.message}",
        status_code: response.code.to_i,
        response_body: response.body&.slice(0, 1000)
      }
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    {
      success: false,
      error: "Timeout: #{e.message}",
      status_code: nil,
      response_body: nil
    }
  rescue SocketError, Errno::ECONNREFUSED => e
    {
      success: false,
      error: "Connection error: #{e.message}",
      status_code: nil,
      response_body: nil
    }
  rescue StandardError => e
    {
      success: false,
      error: "Delivery error: #{e.message}",
      status_code: nil,
      response_body: nil
    }
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
