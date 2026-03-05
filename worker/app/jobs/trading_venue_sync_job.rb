# frozen_string_literal: true

class TradingVenueSyncJob < BaseJob
  sidekiq_options queue: 'trading', retry: 2

  def execute
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Syncing venues for #{portfolios.size} portfolios")

    portfolios.each do |portfolio|
      api_client.post("/api/v1/internal/trading/sync_venue", {
        portfolio_id: portfolio["id"]
      })
      log_info("Venue sync complete", portfolio_id: portfolio["id"])
    rescue StandardError => e
      log_error("Venue sync failed", e, portfolio_id: portfolio["id"])
    end
  end
end
