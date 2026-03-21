# frozen_string_literal: true

class TradingSweepCheckJob < BaseJob
  sidekiq_options queue: 'trading_batch', retry: 1

  def execute(args = {})
    if args.is_a?(Hash) && args["portfolio_id"]
      return process_portfolio(args["portfolio_id"])
    end

    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Dispatching sweep check for #{portfolios.size} portfolios")
    portfolios.each do |portfolio|
      TradingSweepCheckJob.perform_async({ "portfolio_id" => portfolio["id"] })
    end

    { dispatched: portfolios.size }
  end

  private

  def process_portfolio(portfolio_id)
    result = api_client.post("/api/v1/internal/trading/check_sweep_opportunities", {
      portfolio_id: portfolio_id
    })

    count = result.dig("data", "proposals_created") || 0
    log_info("Sweep check complete", portfolio_id: portfolio_id, proposals: count) if count > 0
    { portfolio_id: portfolio_id, proposals: count }
  rescue StandardError => e
    log_error("Sweep check failed for portfolio", e, portfolio_id: portfolio_id)
    { portfolio_id: portfolio_id, error: e.message }
  end
end
