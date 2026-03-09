# frozen_string_literal: true

class TradingPositionCleanupJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute
    response = api_client.post("/api/v1/internal/trading/cleanup_stale_positions")
    data = response["data"] || {}

    closed = (data["decommissioned"] || 0) + (data["inactive"] || 0) +
             (data["stale"] || 0) + (data["training_orphans"] || 0)
    archived = data["archived"] || 0
    errors = data["errors"] || []

    if closed > 0 || archived > 0
      log_info("Position cleanup complete",
        decommissioned: data["decommissioned"],
        inactive: data["inactive"],
        stale: data["stale"],
        training_orphans: data["training_orphans"],
        archived: archived)
    end

    errors.each { |err| log_warn("Cleanup error: #{err}") } if errors.any?
  end
end
