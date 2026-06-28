# frozen_string_literal: true

# AiMemoryPoolCleanupJob - Periodic cleanup of expired AI memory pools
# Runs daily to remove expired pools and free storage
class AiMemoryPoolCleanupJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 1

  def execute(args = {})
    log_info "[AiMemoryPoolCleanupJob] Starting memory pool cleanup"

    pools_cleaned = 0
    bytes_freed = 0

    begin
      # Single bulk purge instead of one DELETE per expired pool (unbounded N+1 that grows if the
      # daily job ever lags). The server deletes the whole expired set in one transaction.
      result = api_client.post("/api/v1/internal/ai/memory_pools/purge_expired", {})
      data = result['data'] || result
      pools_cleaned = (data['pools_cleaned'] || 0).to_i
      bytes_freed = (data['bytes_freed'] || 0).to_i
    rescue StandardError => e
      log_error "[AiMemoryPoolCleanupJob] Failed to purge expired pools", e
    end

    report_cleanup_results(pools_cleaned, bytes_freed)

    log_info "[AiMemoryPoolCleanupJob] Cleanup complete: #{pools_cleaned} pools, #{bytes_freed} bytes freed"

    { pools_cleaned: pools_cleaned, bytes_freed: bytes_freed }
  end

  private

  def report_cleanup_results(pools_cleaned, bytes_freed)
    api_client.post(
      "/api/v1/internal/ai/memory_pools/cleanup_results",
      { pools_cleaned: pools_cleaned, bytes_freed: bytes_freed }
    )
  rescue StandardError => e
    log_error "[AiMemoryPoolCleanupJob] Failed to report results", e
  end
end
