# frozen_string_literal: true

# Expires stale pending overseer decisions that have passed their TTL.
# Runs every 15 minutes to prevent decision queue buildup.
class TradingDecisionExpiryJob < BaseJob
  sidekiq_options queue: 'trading_critical', retry: 1

  def execute
    response = api_client.post("/api/v1/internal/trading/expire_decisions")
    if response&.dig("data", "expired_count").to_i > 0
      log_info("[DecisionExpiry] Expired #{response['data']['expired_count']} stale decisions")
    end
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("Backend unavailable, skipping decision expiry (will retry next cron)")
  rescue BackendApiClient::ApiError => e
    log_info("Decision expiry skipped: #{e.message}")
  end
end
