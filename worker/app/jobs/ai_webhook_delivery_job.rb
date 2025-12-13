# frozen_string_literal: true

# AI webhook delivery job for AI agent execution webhooks
class AiWebhookDeliveryJob < BaseJob
  sidekiq_options queue: 'ai_agents', retry: 2

  def execute(ai_agent_execution_id)
    validate_required_params(ai_agent_execution_id: ai_agent_execution_id)

    log_info "Processing AI webhook delivery for execution: #{ai_agent_execution_id}"

    # Fetch execution details and webhook URLs from backend
    execution_response = api_client.get("/api/v1/ai/agent_executions/#{ai_agent_execution_id}")

    unless execution_response['success']
      log_error "Failed to fetch execution: #{execution_response['error']}"
      return { success: false, error: execution_response['error'] }
    end

    execution_data = execution_response['data']
    webhook_urls = execution_data['webhook_urls'] || []

    if webhook_urls.empty?
      log_info "No webhooks configured for execution: #{ai_agent_execution_id}"
      return { success: true, webhooks_delivered: 0 }
    end

    log_info "Delivering to #{webhook_urls.size} webhook(s)"

    # Prepare webhook payload
    payload = {
      event: 'agent_execution_completed',
      execution_id: ai_agent_execution_id,
      agent_id: execution_data['agent_id'],
      status: execution_data['status'],
      result: execution_data['result'],
      completed_at: execution_data['completed_at'],
      metadata: execution_data['metadata']
    }

    # Deliver to each webhook URL
    results = webhook_urls.map do |webhook_url|
      deliver_to_webhook(webhook_url, payload, ai_agent_execution_id)
    end

    successful_deliveries = results.count { |r| r[:success] }
    failed_deliveries = results.count { |r| !r[:success] }

    log_info "Webhook delivery complete: #{successful_deliveries} successful, #{failed_deliveries} failed"

    {
      success: true,
      webhooks_delivered: successful_deliveries,
      webhooks_failed: failed_deliveries,
      results: results
    }
  rescue StandardError => e
    log_error "AI webhook delivery job failed: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def deliver_to_webhook(webhook_url, payload, execution_id)
    require 'net/http'
    require 'uri'

    log_info "Delivering to webhook: #{webhook_url}"

    start_time = Time.current

    uri = URI.parse(webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 5
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request['User-Agent'] = 'Powernode-AI-Agent/1.0'
    request['X-Powernode-Event'] = 'agent_execution_completed'
    request['X-Powernode-Execution-Id'] = execution_id.to_s

    request.body = payload.to_json

    response = http.request(request)
    response_time_ms = ((Time.current - start_time) * 1000).round

    if response.code.to_i.between?(200, 299)
      log_info "Webhook delivered successfully: #{webhook_url} (#{response_time_ms}ms)"
      {
        success: true,
        webhook_url: webhook_url,
        status_code: response.code.to_i,
        response_time_ms: response_time_ms
      }
    else
      log_error "Webhook delivery failed: #{webhook_url} - HTTP #{response.code}"
      {
        success: false,
        webhook_url: webhook_url,
        error: "HTTP #{response.code}: #{response.message}",
        status_code: response.code.to_i
      }
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    log_error "Webhook timeout: #{webhook_url} - #{e.message}"
    { success: false, webhook_url: webhook_url, error: "Timeout: #{e.message}" }
  rescue SocketError, Errno::ECONNREFUSED => e
    log_error "Webhook connection error: #{webhook_url} - #{e.message}"
    { success: false, webhook_url: webhook_url, error: "Connection error: #{e.message}" }
  rescue StandardError => e
    log_error "Webhook delivery error: #{webhook_url} - #{e.message}"
    { success: false, webhook_url: webhook_url, error: "Delivery error: #{e.message}" }
  end
end
