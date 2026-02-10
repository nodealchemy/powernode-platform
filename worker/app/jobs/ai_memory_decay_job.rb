# frozen_string_literal: true

class AiMemoryDecayJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[MemoryDecay] Starting memory decay processing")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/memory/decay")
    end

    log_info("[MemoryDecay] Memory decay processing completed successfully")
  end
end
