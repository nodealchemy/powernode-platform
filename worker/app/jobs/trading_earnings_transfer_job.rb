# frozen_string_literal: true

class TradingEarningsTransferJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Checking earnings transfers for #{portfolios.size} portfolios")

    total_transfers = 0
    portfolios.each do |portfolio|
      result = api_client.post("/api/v1/internal/trading/check_earnings_transfers", {
        portfolio_id: portfolio["id"]
      })

      if result["success"]
        count = result.dig("data", "transfers_count") || 0
        total_transfers += count
        log_info("Earnings transfer complete", portfolio_id: portfolio["id"], transfers: count) if count > 0
      end
    rescue StandardError => e
      log_error("Earnings transfer failed for portfolio", e, portfolio_id: portfolio["id"])
    end

    log_info("Earnings transfer check complete", total_transfers: total_transfers)
    { total_transfers: total_transfers }
  end
end
