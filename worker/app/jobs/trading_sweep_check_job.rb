# frozen_string_literal: true

class TradingSweepCheckJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Checking sweep opportunities for #{portfolios.size} portfolios")

    total_proposals = 0
    portfolios.each do |portfolio|
      result = api_client.post("/api/v1/internal/trading/check_sweep_opportunities", {
        portfolio_id: portfolio["id"]
      })

      if result["success"]
        count = result.dig("data", "proposals_created") || 0
        total_proposals += count
        log_info("Sweep check complete", portfolio_id: portfolio["id"], proposals: count) if count > 0
      end
    rescue StandardError => e
      log_error("Sweep check failed for portfolio", e, portfolio_id: portfolio["id"])
    end

    log_info("Sweep check complete", total_proposals: total_proposals)
    { total_proposals: total_proposals }
  end
end
