# frozen_string_literal: true

class AiEscalationTimeoutJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 1

  def execute(args = {})
    response = api_client.post("/api/v1/internal/ai/escalations/auto_escalate")

    if response["success"]
      data = response["data"] || {}
      escalated = data["escalated_count"] || 0
      log_info "[AiEscalationTimeoutJob] Auto-escalated #{escalated} overdue escalations" if escalated > 0
      data
    else
      log_warn "[AiEscalationTimeoutJob] API returned error: #{response['error']}"
      { escalated_count: 0 }
    end
  end
end
