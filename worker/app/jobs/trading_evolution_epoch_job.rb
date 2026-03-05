# frozen_string_literal: true

class TradingEvolutionEpochJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute(portfolio_id = nil)
    if portfolio_id
      run_epoch(portfolio_id)
    else
      run_all_epochs
    end
  end

  private

  def run_all_epochs
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Running evolution epochs for #{portfolios.size} portfolios")

    portfolios.each do |portfolio|
      run_epoch(portfolio["id"])
    end

    { portfolios_processed: portfolios.size }
  end

  def run_epoch(portfolio_id)
    log_info("Running evolution epoch", portfolio_id: portfolio_id)

    response = api_client.post("/api/v1/internal/trading/run_evolution_epoch", {
      portfolio_id: portfolio_id
    })

    if response["success"]
      log_info("Evolution epoch complete", portfolio_id: portfolio_id,
        epoch: response.dig("data", "epoch_number"))
    else
      log_warn("Evolution epoch failed", portfolio_id: portfolio_id,
        error: response["error"])
    end

    response
  rescue StandardError => e
    log_error("Evolution epoch failed", e, portfolio_id: portfolio_id)
    nil
  end
end
