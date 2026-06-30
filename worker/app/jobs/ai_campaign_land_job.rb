# frozen_string_literal: true

# Drives a single campaign land through its first phase (stage) and then hands
# off to the worker-side deep security scan (G4), which gates the merge and chains
# the CI poll on a clean diff. Staging pushes the campaign branch to trigger CI;
# if it parks (conflict/missing/kill-switch) the pipeline stops here. All git work
# happens server-side; this job only sequences the internal-API phase calls and
# fans out the scan with the land's repository + branches.
class AiCampaignLandJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 2

  def execute(args = {})
    land_id = args["land_id"]
    return if land_id.blank?

    resp = api_client.post("/api/v1/internal/ai/campaign_lands/#{land_id}/stage")
    land = dig_land(resp)
    status = land["status"]
    log_info "[AiCampaignLandJob] land #{land_id} staged → #{status}"

    # Parked / failed / halted: pipeline stops; operator handles via dashboard.
    return { land_id: land_id, status: status } unless status == "staged_ci"

    # Deep-scan the REAL staged diff BEFORE the merge gate. The scan job parks the
    # land on a finding, or chains the staged-CI poll on a clean scan.
    AiLandSecurityScanJob.perform_async(
      "land_id"       => land_id,
      "repository"    => land["repository"],
      "source_branch" => land["source_branch"],
      "target_branch" => land["target_branch"],
      "base_sha"      => land["base_sha"]
    )
    { land_id: land_id, status: status }
  rescue StandardError => e
    log_error "[AiCampaignLandJob] failed for land #{args['land_id']}", e
    raise
  end

  private

  def dig_land(resp)
    return {} unless resp.is_a?(Hash)

    (resp["data"] || resp)["land"] || {}
  end
end
