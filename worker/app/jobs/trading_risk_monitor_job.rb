# frozen_string_literal: true

class TradingRiskMonitorJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Running risk monitor for #{portfolios.size} portfolios")

    portfolios.each do |portfolio|
      result = api_client.post("/api/v1/internal/trading/check_risk", {
        portfolio_id: portfolio["id"]
      })

      if result.dig("data", "circuit_breaker_active")
        log_warn("Circuit breaker ACTIVE", portfolio_id: portfolio["id"])
      end
    rescue StandardError => e
      log_error("Risk check failed", e, portfolio_id: portfolio["id"])
    end
  end
end
