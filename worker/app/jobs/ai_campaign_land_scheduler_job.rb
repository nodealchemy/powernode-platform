# frozen_string_literal: true

# Recurring poller for the campaign auto-land queue. Asks the backend to pick the
# next eligible land per (account, target) whose slot is free, then fans out one
# AiCampaignLandJob per picked land. Mirrors AiRalphLoopSchedulerJob.
class AiCampaignLandSchedulerJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(_args = {})
    response = api_client.post("/api/v1/internal/ai/campaign_lands/process_queue")
    lands = (response.is_a?(Hash) ? (response["data"] || response) : {})["lands"] || []

    lands.each do |land|
      AiCampaignLandJob.perform_async("land_id" => land["id"])
    end

    log_info "[AiCampaignLandScheduler] dispatched #{lands.size} land(s)"
    { dispatched: lands.size }
  rescue StandardError => e
    log_error "[AiCampaignLandScheduler] failed", e
    raise
  end
end
