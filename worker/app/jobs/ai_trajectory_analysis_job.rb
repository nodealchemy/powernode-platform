# frozen_string_literal: true

class AiTrajectoryAnalysisJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[TrajectoryAnalysis] Starting trajectory analysis")

    response = api_client.post("/api/v1/internal/ai/trajectory/analyze_all")

    if response['success']
      log_info("[TrajectoryAnalysis] Analysis completed",
        accounts_processed: response.dig('data', 'accounts_processed'))
    else
      log_error("[TrajectoryAnalysis] Analysis failed: #{response['error']}")
    end
  end
end
