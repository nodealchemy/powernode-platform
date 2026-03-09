# frozen_string_literal: true

module Devops
  class PortAllocationCleanupJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 2, dead: false

    def execute
      log_info "[PortCleanup] Starting expired port allocation cleanup"

      result = api_client.post("/api/v1/internal/devops/maintenance/cleanup_expired_ports")

      released_count = result.dig("data", "released_count") || 0

      log_info "[PortCleanup] Released #{released_count} expired port allocations"

      increment_counter("port_allocation_cleanup_run")
      track_cleanup_metrics(released_ports: released_count)
    end
  end
end
