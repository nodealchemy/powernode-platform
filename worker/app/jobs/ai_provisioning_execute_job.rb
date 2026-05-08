# frozen_string_literal: true

# Phase-3 worker job for the system_provisioning mission template.
# Triggers the server-side Ai::Provisioning::SkillCompositionRunner through
# the internal API. The runner itself dispatches per-step jobs and broadcasts
# step events to MissionChannel; this job only kicks the run off.
class AiProvisioningExecuteJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: "ai_execution", retry: 3

  def execute(params)
    params = (params || {}).transform_keys(&:to_s)
    validate_required_params(params, "mission_id", "account_id")

    mission_id = params["mission_id"]
    log_info("Provisioning execute starting", mission_id: mission_id)

    result = backend_api_post(
      "/api/v1/internal/ai/provisioning/missions/#{mission_id}/execute",
      {}
    )

    if result.is_a?(Hash) && result["success"] == false
      report_failure(mission_id, result["error"] || "execute failed")
      return result
    end

    log_info("Provisioning execute kicked off",
             mission_id: mission_id,
             runner_id: result.is_a?(Hash) ? result.dig("data", "runner_id") : nil,
             step_count: result.is_a?(Hash) ? result.dig("data", "step_count") : nil)
    result
  rescue StandardError => e
    log_error("AiProvisioningExecuteJob failed", e, mission_id: params && params["mission_id"])
    report_failure(params && params["mission_id"], e.message) if params && params["mission_id"]
    raise
  end

  private

  def report_failure(mission_id, error_message)
    return unless mission_id

    backend_api_patch("/api/v1/ai/missions/#{mission_id}", {
      mission: { status: "failed", error_message: error_message }
    })
  rescue StandardError => e
    log_warn("Failed to report mission failure", error: e.message)
  end
end
