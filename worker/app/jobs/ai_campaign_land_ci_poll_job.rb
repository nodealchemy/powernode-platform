# frozen_string_literal: true

# Polls the CI gate for a campaign land and advances it:
#   gate "staged":  green → merge (then poll the "target" gate); red → park.
#   gate "target":  terminal → verify (server lands on green / rolls back on red).
# Pending/missing CI re-enqueues with a delay up to MAX_ATTEMPTS, then parks so a
# stuck land never loops forever.
class AiCampaignLandCiPollJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 2

  MAX_ATTEMPTS = 40         # ~20 min at 30s spacing
  POLL_INTERVAL_SECONDS = 30

  def execute(args = {})
    land_id = args["land_id"]
    gate = args["gate"] || "staged"
    attempt = (args["attempt"] || 0).to_i
    return if land_id.blank?

    ci = ci_status(land_id, gate)
    log_info "[AiCampaignLandCiPoll] land #{land_id} gate=#{gate} attempt=#{attempt} → #{ci}"

    case ci
    when "pending", "missing"
      if attempt + 1 >= MAX_ATTEMPTS
        api_client.post("/api/v1/internal/ai/campaign_lands/#{land_id}/park", { reason: "CI #{gate} timed out" })
      else
        self.class.perform_in(POLL_INTERVAL_SECONDS, "land_id" => land_id, "gate" => gate, "attempt" => attempt + 1)
      end
    when "success"
      if gate == "staged"
        api_client.post("/api/v1/internal/ai/campaign_lands/#{land_id}/merge")
        # merge advances to verifying; now gate the merged commit on the target.
        self.class.perform_async("land_id" => land_id, "gate" => "target", "attempt" => 0)
      else
        api_client.post("/api/v1/internal/ai/campaign_lands/#{land_id}/verify") # lands on green
      end
    when "failure"
      if gate == "staged"
        api_client.post("/api/v1/internal/ai/campaign_lands/#{land_id}/park", { reason: "staged CI failed" })
      else
        api_client.post("/api/v1/internal/ai/campaign_lands/#{land_id}/verify") # server rolls back on red
      end
    end

    { land_id: land_id, gate: gate, ci: ci }
  rescue StandardError => e
    log_error "[AiCampaignLandCiPoll] failed for land #{args['land_id']}", e
    raise
  end

  private

  def ci_status(land_id, gate)
    resp = api_client.get("/api/v1/internal/ai/campaign_lands/#{land_id}/ci_status", gate: gate)
    return nil unless resp.is_a?(Hash)

    (resp["data"] || resp)["ci_status"]
  end
end
