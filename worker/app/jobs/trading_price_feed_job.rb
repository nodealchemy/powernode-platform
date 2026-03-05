# frozen_string_literal: true

class TradingPriceFeedJob < BaseJob
  sidekiq_options queue: 'trading', retry: 2

  DEFAULT_PAIRS = %w[BTC/USDC ETH/USDC SOL/USDC].freeze

  def execute(pairs = nil, source = nil)
    pairs ||= DEFAULT_PAIRS
    source ||= "coingecko"

    log_info("Fetching prices", pairs: pairs.join(","), source: source)

    response = api_client.post("/api/v1/internal/trading/fetch_prices", {
      pairs: pairs,
      source: source
    })

    if response["success"]
      data = response["data"] || {}
      log_info("Prices fetched", pairs_count: data.keys.size)
    else
      log_error("Price fetch failed: #{response['error']}")
    end

    response
  end
end
