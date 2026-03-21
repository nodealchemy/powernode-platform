# frozen_string_literal: true

class TradingVenueSyncJob < BaseJob
  sidekiq_options queue: 'trading_critical', retry: 2

  BATCH_SIZE = 50

  def execute
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    return if portfolios.empty?

    log_info("Syncing venues for #{portfolios.size} portfolios (batched)")

    portfolio_ids = portfolios.map { |p| p["id"] }
    portfolio_ids.each_slice(BATCH_SIZE) do |batch|
      result = api_client.post("/api/v1/internal/trading/batch_sync_venue", {
        portfolio_ids: batch
      })
      errors = (result.dig("data", "results") || []).select { |r| r["error"] }
      errors.each do |e|
        log_warn("Venue sync failed", portfolio_id: e["portfolio_id"], error: e["error"])
      end
    end

    log_info("Venue sync complete for #{portfolios.size} portfolios")
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("Backend unavailable, skipping venue sync (will retry next cycle)")
  rescue BackendApiClient::ApiError => e
    log_info("Venue sync skipped: #{e.message}")
  end
end
