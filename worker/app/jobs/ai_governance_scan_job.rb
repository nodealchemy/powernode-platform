# frozen_string_literal: true

class AiGovernanceScanJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(params = {})
    log_info("Starting governance scan for all agents")
    response = with_api_retry { api_client.post("/api/v1/internal/ai/governance/scan_all", params) }
    if response["success"]
      log_info("Governance scan completed", result: response.dig("data"))
    else
      log_warn("Governance scan returned no result")
    end
  rescue StandardError => e
    log_error("Governance scan failed", e)
    raise
  end
end
