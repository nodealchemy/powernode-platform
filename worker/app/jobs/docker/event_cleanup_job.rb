# frozen_string_literal: true

module Docker
  class EventCleanupJob < BaseJob
    sidekiq_options queue: "maintenance", retry: 1

    DEFAULT_RETENTION_DAYS = 30

    def execute
      log_info "Starting Docker event cleanup"

      days = DEFAULT_RETENTION_DAYS
      response = api_client.post("/api/v1/internal/devops/docker/events", {
        action_type: "cleanup",
        older_than_days: days
      })

      deleted = response.dig("data", "deleted_count") || 0
      log_info "Docker event cleanup completed", deleted_count: deleted, retention_days: days
    end
  end
end
