# frozen_string_literal: true

class AiDedupLearningJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 2

  def execute(learning_id)
    log_info("[DedupLearning] Running dedup check for learning #{learning_id}")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/learning/dedup_check", { learning_id: learning_id })
    end

    log_info("[DedupLearning] Completed for #{learning_id}")
  end
end
