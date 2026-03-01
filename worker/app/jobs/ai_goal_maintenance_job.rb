# frozen_string_literal: true

class AiGoalMaintenanceJob < BaseJob
  sidekiq_options queue: :maintenance, retry: 1

  def execute(args = {})
    response = api_client.post("/api/v1/internal/ai/goals/maintenance")

    if response["success"]
      data = response["data"] || {}
      log_info "[AiGoalMaintenanceJob] Abandoned #{data['goals_abandoned']} stale goals"
      data
    else
      log_warn "[AiGoalMaintenanceJob] API returned error: #{response['error']}"
      { goals_abandoned: 0 }
    end
  end
end
