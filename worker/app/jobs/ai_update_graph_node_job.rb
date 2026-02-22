# frozen_string_literal: true

class AiUpdateGraphNodeJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 2

  def execute(node_id)
    log_info("[UpdateGraphNode] Recalculating confidence/quality for KG node #{node_id}")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/learning/update_graph_node", { node_id: node_id })
    end

    log_info("[UpdateGraphNode] Completed for #{node_id}")
  end
end
