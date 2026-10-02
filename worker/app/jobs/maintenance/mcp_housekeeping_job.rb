# frozen_string_literal: true

module Maintenance
  # Recurring MCP OAuth housekeeping.
  #
  # The worker has no database access, so the actual pruning runs on the backend
  # (where the models live) via the internal API. This job just triggers it on a
  # schedule. The backend prunes stale MCP sessions, revoked Doorkeeper tokens/grants
  # past retention, and orphaned Dynamic-Client-Registration apps. Scheduled daily
  # in config/sidekiq.yml. It also reclaims this host's idle or orphaned
  # per-account stdio sandbox caches (see #prune_sandbox_caches).
  class McpHousekeepingJob < BaseJob
    sidekiq_options queue: 'maintenance', retry: 2, dead: true

    def execute
      log_info "[McpHousekeepingJob] Starting MCP OAuth housekeeping"

      response = api_client.post("/api/v1/internal/mcp/housekeeping")
      summary = response.is_a?(Hash) ? (response['data'] || response) : {}

      pruned = prune_sandbox_caches
      summary = summary.merge('sandbox_caches_pruned' => pruned) if pruned

      log_info "[McpHousekeepingJob] Housekeeping complete: #{summary.to_json}"
      summary
    rescue StandardError => e
      log_error "[McpHousekeepingJob] Housekeeping failed", e
      raise
    end

    private

    # IMP-f074ef554781 — reclaim the per-account stdio sandbox caches
    # (/var/cache/private/mcp-stdio-<hash>) on THIS host. They are on the
    # worker's own disk, so the pruning can only run here; the facts it needs
    # (accounts that exist, the idle age) come from the backend. A failure is
    # logged and returns nil: the OAuth housekeeping above already succeeded
    # and must not be retried because a cache could not be reclaimed.
    def prune_sandbox_caches
      response = api_client.get("/api/v1/internal/mcp/sandbox_cache_policy")
      policy = response.is_a?(Hash) ? (response['data'] || response) : {}

      McpSandboxCachePruner.call(
        account_ids: Array(policy['account_ids']),
        max_idle_seconds: policy['max_idle_seconds']
      )[:pruned]
    rescue StandardError => e
      log_error "[McpHousekeepingJob] Sandbox cache pruning failed", e
      nil
    end
  end
end
