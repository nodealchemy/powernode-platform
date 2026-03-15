# frozen_string_literal: true

class TradingRiskMonitorJob < BaseJob
  sidekiq_options queue: 'trading', retry: 2

  PER_PORTFOLIO_TIMEOUT = 20 # seconds per risk check call
  FETCH_TIMEOUT = 15 # seconds for portfolio list fetch

  def execute
    response = Timeout.timeout(FETCH_TIMEOUT) do
      api_client.get("/api/v1/internal/trading/active_portfolios")
    end
    portfolios = response.dig("data", "items") || []

    log_info("Running risk monitor for #{portfolios.size} portfolios")

    portfolios.each do |portfolio|
      result = Timeout.timeout(PER_PORTFOLIO_TIMEOUT) do
        api_client.post("/api/v1/internal/trading/check_risk", {
          portfolio_id: portfolio["id"]
        })
      end

      if result.dig("data", "circuit_breaker_active")
        log_warn("Circuit breaker ACTIVE", portfolio_id: portfolio["id"])
      end
    rescue Timeout::Error
      log_error("Risk check timed out after #{PER_PORTFOLIO_TIMEOUT}s", nil, portfolio_id: portfolio["id"])
    rescue StandardError => e
      log_error("Risk check failed", e, portfolio_id: portfolio["id"])
    end
  end
end
