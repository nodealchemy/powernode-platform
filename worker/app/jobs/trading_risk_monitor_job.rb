# frozen_string_literal: true

class TradingRiskMonitorJob < BaseJob
  sidekiq_options queue: 'trading', retry: 2

  BATCH_SIZE = 50
  FETCH_TIMEOUT = 15 # seconds for portfolio list fetch

  def execute
    response = Timeout.timeout(FETCH_TIMEOUT) do
      api_client.get("/api/v1/internal/trading/active_portfolios")
    end
    portfolios = response.dig("data", "items") || []

    return if portfolios.empty?

    log_info("Running risk monitor for #{portfolios.size} portfolios (batched)")

    portfolio_ids = portfolios.map { |p| p["id"] }
    portfolio_ids.each_slice(BATCH_SIZE) do |batch|
      result = api_client.post("/api/v1/internal/trading/batch_check_risk", {
        portfolio_ids: batch
      })
      (result.dig("data", "results") || []).each do |r|
        if r["circuit_breaker_active"]
          log_warn("Circuit breaker ACTIVE", portfolio_id: r["portfolio_id"])
        elsif r["error"]
          log_warn("Risk check failed", portfolio_id: r["portfolio_id"], error: r["error"])
        end
      end
    end
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("Backend unavailable, skipping risk check (will retry next cycle)")
  rescue BackendApiClient::ApiError => e
    log_info("Risk monitor skipped: #{e.message}")
  end
end
