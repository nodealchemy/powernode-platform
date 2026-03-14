# frozen_string_literal: true

class TradingCompoundingCheckJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Checking compounding eligibility for #{portfolios.size} portfolios")

    total_compounded = 0
    portfolios.each do |portfolio|
      result = api_client.post("/api/v1/internal/trading/check_compounding", {
        portfolio_id: portfolio["id"]
      })

      if result["success"]
        count = result.dig("data", "strategies_compounded") || 0
        total_compounded += count
        log_info("Compounding check complete", portfolio_id: portfolio["id"], compounded: count) if count > 0
      end
    rescue StandardError => e
      log_error("Compounding check failed for portfolio", e, portfolio_id: portfolio["id"])
    end

    log_info("Compounding check complete", total_compounded: total_compounded)
    { total_compounded: total_compounded }
  end
end
