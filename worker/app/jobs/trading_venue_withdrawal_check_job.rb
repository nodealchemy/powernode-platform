# frozen_string_literal: true

class TradingVenueWithdrawalCheckJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Checking venue withdrawal rules for #{portfolios.size} portfolios")

    total_withdrawals = 0
    portfolios.each do |portfolio|
      result = api_client.post("/api/v1/internal/trading/check_venue_withdrawals", {
        portfolio_id: portfolio["id"]
      })

      if result["success"]
        count = result.dig("data", "withdrawals_processed") || 0
        total_withdrawals += count
        log_info("Venue withdrawal check complete", portfolio_id: portfolio["id"], withdrawals: count) if count > 0
      end
    rescue StandardError => e
      log_error("Venue withdrawal check failed for portfolio", e, portfolio_id: portfolio["id"])
    end

    log_info("Venue withdrawal check complete", total_withdrawals: total_withdrawals)
    { total_withdrawals: total_withdrawals }
  end
end
