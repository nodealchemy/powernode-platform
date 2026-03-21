# frozen_string_literal: true

class TradingEvolutionEpochJob < BaseJob
  sidekiq_options queue: 'trading_batch', retry: 1

  def execute(portfolio_id = nil, options = {})
    options = options.is_a?(Hash) ? options : {}
    trigger_type = options["trigger_type"] || options[:trigger_type] || "scheduled"
    engine = Trading::EvolutionEngine.new(trading_data_fetcher)

    if portfolio_id
      result = engine.run_epoch!(portfolio_id, trigger_type: trigger_type)
      log_info("Evolution epoch complete",
               portfolio_id: portfolio_id,
               epoch_id: result[:epoch_id],
               strategies: result[:strategies_evaluated],
               skipped: result[:skipped])
      result
    else
      run_all_epochs(engine, trigger_type: trigger_type)
    end
  end

  private

  def run_all_epochs(engine, trigger_type:)
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    portfolios = response.dig("data", "items") || []

    log_info("Running evolution epochs for #{portfolios.size} portfolios")

    results = portfolios.map do |portfolio|
      engine.run_epoch!(portfolio["id"], trigger_type: trigger_type)
    rescue StandardError => e
      log_error("Evolution failed for #{portfolio['id']}", e)
      nil
    end

    { portfolios_processed: results.compact.size }
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("Backend unavailable, skipping evolution epochs (will retry next cron)")
  rescue BackendApiClient::ApiError => e
    log_info("Evolution epochs skipped: #{e.message}")
  end

  def trading_data_fetcher
    @trading_data_fetcher ||= Trading::DataFetcher.new(api_client)
  end
end
