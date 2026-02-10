# frozen_string_literal: true

class AiResellerAnalysisJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[ResellerAnalysis] Starting reseller analysis")

    with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/intelligence/reseller/performance_scores")
    end

    log_info("[ResellerAnalysis] Reseller analysis completed successfully")
  end
end
