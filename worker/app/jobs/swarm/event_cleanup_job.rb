# frozen_string_literal: true

module Swarm
  # Purges old acknowledged Swarm events
  # Queue: maintenance
  # Retry: 2
  class EventCleanupJob < BaseJob
    sidekiq_options queue: "maintenance", retry: 2

    DEFAULT_RETENTION_DAYS = 30

    # Clean up old acknowledged events
    def execute
      log_info "Starting Swarm event cleanup", retention_days: DEFAULT_RETENTION_DAYS

      response = api_client.post("/api/v1/internal/devops/swarm/events", {
        action: "cleanup",
        older_than_days: DEFAULT_RETENTION_DAYS
      })

      deleted_count = response.dig("data", "deleted_count") || 0

      log_info "Swarm event cleanup completed", deleted: deleted_count

      increment_counter("swarm.events.cleaned", count: deleted_count)
    end
  end
end
