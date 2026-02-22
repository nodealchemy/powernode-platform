# frozen_string_literal: true

class AiPromoteLearningJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 2

  def execute(learning_id)
    log_info("[PromoteLearning] Promoting learning #{learning_id} to global scope")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/learning/promote_learning", { learning_id: learning_id })
    end

    log_info("[PromoteLearning] Completed for #{learning_id}")
  end
end
