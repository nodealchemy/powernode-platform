# frozen_string_literal: true

class AiKnowledgeDocSyncJob < BaseJob
  sidekiq_options queue: 'maintenance', retry: 1

  def execute(*_args)
    log_info("[KnowledgeDocSync] Starting documentation sync")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/learning/knowledge_doc_sync")
    end

    log_info("[KnowledgeDocSync] Documentation sync completed")
  end
end
