# frozen_string_literal: true

# Drives a single campaign land through its first phase (stage) and then hands
# off to the CI poll job. Staging pushes the campaign branch to trigger CI; if it
# parks (conflict/missing/kill-switch) the pipeline stops here. Otherwise we poll
# the staged-branch CI before merging. All git work happens server-side; this job
# only sequences the internal-API phase calls.
class AiCampaignLandJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 2

  def execute(args = {})
    land_id = args["land_id"]
    return if land_id.blank?

    resp = api_client.post("/api/v1/internal/ai/campaign_lands/#{land_id}/stage")
    status = dig_status(resp)
    log_info "[AiCampaignLandJob] land #{land_id} staged → #{status}"

    # Parked / failed / halted: pipeline stops; operator handles via dashboard.
    return { land_id: land_id, status: status } unless status == "staged_ci"

    AiCampaignLandCiPollJob.perform_async("land_id" => land_id, "gate" => "staged", "attempt" => 0)
    { land_id: land_id, status: status }
  rescue StandardError => e
    log_error "[AiCampaignLandJob] failed for land #{args['land_id']}", e
    raise
  end

  private

  def dig_status(resp)
    return nil unless resp.is_a?(Hash)

    (resp["data"] || resp).dig("land", "status")
  end
end
