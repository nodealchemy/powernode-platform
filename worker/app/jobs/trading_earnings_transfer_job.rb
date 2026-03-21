# frozen_string_literal: true

class TradingEarningsTransferJob < BaseJob
  sidekiq_options queue: 'trading_batch', retry: 1

  def execute(args = {})
    if args.is_a?(Hash) && args["portfolio_id"]
      return process_portfolio(args["portfolio_id"])
    end

    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Dispatching earnings transfers for #{portfolios.size} portfolios")
    portfolios.each do |portfolio|
      TradingEarningsTransferJob.perform_async({ "portfolio_id" => portfolio["id"] })
    end

    { dispatched: portfolios.size }
  end

  private

  def process_portfolio(portfolio_id)
    result = api_client.post("/api/v1/internal/trading/check_earnings_transfers", {
      portfolio_id: portfolio_id
    })

    count = result.dig("data", "transfers_count") || 0
    log_info("Earnings transfer complete", portfolio_id: portfolio_id, transfers: count) if count > 0
    { portfolio_id: portfolio_id, transfers: count }
  rescue StandardError => e
    log_error("Earnings transfer failed for portfolio", e, portfolio_id: portfolio_id)
    { portfolio_id: portfolio_id, error: e.message }
  end
end
