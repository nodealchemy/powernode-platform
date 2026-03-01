# frozen_string_literal: true

class AiReviewAnalysisJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[ReviewAnalysis] Starting review analysis")

    with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/intelligence/reviews/spam_detection")
    end

    log_info("[ReviewAnalysis] Review analysis completed successfully")
  end
end
