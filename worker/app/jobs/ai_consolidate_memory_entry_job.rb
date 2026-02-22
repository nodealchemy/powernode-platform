# frozen_string_literal: true

class AiConsolidateMemoryEntryJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 2

  def execute(entry_id)
    log_info("[ConsolidateMemoryEntry] Consolidating STM entry #{entry_id} to LTM")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/memory/consolidate_entry", { entry_id: entry_id })
    end

    log_info("[ConsolidateMemoryEntry] Completed for #{entry_id}")
  end
end
