# frozen_string_literal: true

class ChatSessionCleanupJob < BaseJob
  sidekiq_options queue: 'maintenance', retry: 1

  def execute(*_args)
    log_info("[ChatSessionCleanup] Starting periodic chat session cleanup")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/chat/channels/cleanup_sessions")
    end

    log_info("[ChatSessionCleanup] Cleanup completed successfully")
  end
end
