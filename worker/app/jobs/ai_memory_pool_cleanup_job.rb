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
      response = api_client.get("/api/v1/internal/ai/memory_pools/expired")
      expired_pools = response['data'] || []

      expired_pools.each do |pool|
        begin
          delete_response = api_client.delete("/api/v1/internal/ai/memory_pools/#{pool['id']}")
          if delete_response['success']
            pools_cleaned += 1
            bytes_freed += (pool['data_size_bytes'] || 0)
          end
        rescue StandardError => e
          log_warn "[AiMemoryPoolCleanupJob] Failed to clean pool #{pool['id']}: #{e.message}"
        end
      end
    rescue StandardError => e
      log_error "[AiMemoryPoolCleanupJob] Failed to fetch expired pools", e
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
