# frozen_string_literal: true

module Maintenance
  # Recurring MCP OAuth housekeeping.
  #
  # The worker has no database access, so the actual pruning runs on the backend
  # (where the models live) via the internal API. This job just triggers it on a
  # schedule. The backend prunes stale MCP sessions, revoked Doorkeeper tokens/grants
  # past retention, and orphaned Dynamic-Client-Registration apps. Scheduled daily
  # in config/sidekiq.yml.
  class McpHousekeepingJob < BaseJob
    sidekiq_options queue: 'maintenance', retry: 2, dead: true

    def execute
      log_info "[McpHousekeepingJob] Starting MCP OAuth housekeeping"

      response = api_client.post("/api/v1/internal/mcp/housekeeping")
      summary = response.is_a?(Hash) ? (response['data'] || response) : {}

      log_info "[McpHousekeepingJob] Housekeeping complete: #{summary.to_json}"
      summary
    rescue StandardError => e
      log_error "[McpHousekeepingJob] Housekeeping failed", e
      raise
    end
  end
end
