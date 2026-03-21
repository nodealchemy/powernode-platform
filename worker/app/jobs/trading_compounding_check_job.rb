# frozen_string_literal: true

class TradingCompoundingCheckJob < BaseJob
  sidekiq_options queue: 'trading_batch', retry: 1

  def execute(args = {})
    # Fan-out: if portfolio_id given, process single portfolio
    if args.is_a?(Hash) && args["portfolio_id"]
      return process_portfolio(args["portfolio_id"])
    end

    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Dispatching compounding check for #{portfolios.size} portfolios")
    portfolios.each do |portfolio|
      TradingCompoundingCheckJob.perform_async({ "portfolio_id" => portfolio["id"] })
    end

    { dispatched: portfolios.size }
  end

  private

  def process_portfolio(portfolio_id)
    result = api_client.post("/api/v1/internal/trading/check_compounding", {
      portfolio_id: portfolio_id
    })

    count = result.dig("data", "strategies_compounded") || 0
    log_info("Compounding check complete", portfolio_id: portfolio_id, compounded: count) if count > 0
    { portfolio_id: portfolio_id, compounded: count }
  rescue StandardError => e
    log_error("Compounding check failed for portfolio", e, portfolio_id: portfolio_id)
    { portfolio_id: portfolio_id, error: e.message }
  end
end
