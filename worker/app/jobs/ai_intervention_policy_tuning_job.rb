# frozen_string_literal: true

class AiInterventionPolicyTuningJob < BaseJob
  sidekiq_options queue: :maintenance, retry: 1

  def execute(args = {})
    response = api_client.post("/api/v1/internal/ai/intervention_policies/analyze_patterns")

    if response["success"]
      data = response["data"] || {}
      suggestions = data["suggestions_count"] || 0
      log_info "[AiInterventionPolicyTuningJob] Generated #{suggestions} policy tuning suggestions" if suggestions > 0
      data
    else
      log_warn "[AiInterventionPolicyTuningJob] API returned error: #{response['error']}"
      { suggestions_count: 0 }
    end
  end
end
