# frozen_string_literal: true

class AiKnowledgeGraphMaintenanceJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[KnowledgeGraphMaintenance] Starting daily knowledge graph maintenance")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/learning/knowledge_graph_maintenance")
    end

    log_info("[KnowledgeGraphMaintenance] Maintenance completed successfully")
  end
end
