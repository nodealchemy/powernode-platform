# frozen_string_literal: true

class AiCollusionDetectionJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(params = {})
    log_info("Starting collusion detection across active agents")
    response = with_api_retry { api_client.post("/api/v1/internal/ai/governance/detect_collusion", params) }
    if response["success"]
      log_info("Collusion detection completed", result: response.dig("data"))
    else
      log_warn("Collusion detection returned no result")
    end
  rescue StandardError => e
    log_error("Collusion detection failed", e)
    raise
  end
end
