# frozen_string_literal: true

class TradingOrderFillCheckJob < BaseJob
  sidekiq_options queue: 'trading', retry: 2

  def execute
    # For now, this is a no-op for simulation mode.
    # When real venue adapters are added, this will poll for order fills.
    log_info("Order fill check - simulation mode (no-op)")
    { checked: true, mode: "simulation" }
  end
end
