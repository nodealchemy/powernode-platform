# frozen_string_literal: true

class AiMemoryConsolidationJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[MemoryConsolidation] Starting memory consolidation")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/memory/consolidate")
    end

    log_info("[MemoryConsolidation] Memory consolidation completed successfully")
  end
end
