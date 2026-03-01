# frozen_string_literal: true

class AiTeamMessageCleanupJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[AiTeamMessageCleanup] Starting AI team message cleanup")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/teams/cleanup_messages")
    end

    log_info("[AiTeamMessageCleanup] Cleanup completed successfully")
  end
end
