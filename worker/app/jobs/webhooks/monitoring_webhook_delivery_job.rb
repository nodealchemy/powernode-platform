# frozen_string_literal: true

require 'net/http'
require 'uri'

module Webhooks
  # Ad-hoc outbound delivery of a raw (url, payload) pair to a TRUSTED,
  # operator-configured target.
  #
  # Unlike Webhooks::WebhookDeliveryJob — which fetches a persisted
  # WebhookDelivery record by id (with SSRF guarding, circuit breaker and a
  # delivery ledger) — this seam delivers a caller-supplied URL and JSON payload
  # with no backing record. It exists for internal producers such as the MCP
  # monitoring webhook (Mcp::BroadcastService), whose URL comes from operator
  # credentials, not attacker-controllable user/DB input.
  #
  # Because the destination is a trusted operator callout, the user-webhook SSRF
  # guard (Security::WebhookUrlGuard) is intentionally NOT applied here: its
  # documented scope is attacker-controlled URLs only, and it would wrongly block
  # legitimate internal monitoring collectors on RFC1918 addresses. Do NOT route
  # attacker-controlled URLs through this job — use the record-id delivery
  # pipeline (which guards) instead.
  #
  # Non-2xx responses raise so Sidekiq retries the delivery with backoff.
  class MonitoringWebhookDeliveryJob < BaseJob
    class DeliveryError < StandardError; end

    sidekiq_options queue: 'webhooks', retry: 3

    def execute(webhook_url, payload)
      log_info "[MonitoringWebhook] delivering to #{webhook_url}"

      result = deliver(webhook_url, payload)

      if result[:success]
        log_info "[MonitoringWebhook] delivered to #{webhook_url} (#{result[:status_code]})"
        { success: true, status_code: result[:status_code] }
      else
        log_error "[MonitoringWebhook] delivery to #{webhook_url} failed: #{result[:error]}"
        raise DeliveryError, result[:error]
      end
    end

    private

    def deliver(url, payload)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 5
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['User-Agent'] = 'Powernode-Webhook/1.0'
      request.body = payload.is_a?(String) ? payload : payload.to_json

      response = http.request(request)
      code = response.code.to_i

      if code.between?(200, 299)
        { success: true, status_code: code }
      else
        { success: false, status_code: code, error: "HTTP #{code}: #{response.message}" }
      end
    end
  end
end
