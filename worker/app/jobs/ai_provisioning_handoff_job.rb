# frozen_string_literal: true

# Phase-5 worker job for the system_provisioning mission template.
# Drives the `handoff` phase by POSTing to the internal API, which:
#   - creates an Ai::RalphLoop bound to the mission (one per active
#     infrastructure mission, per the M2 plan),
#   - advances the mission to the long-lived `adapting` phase,
#   - emits a "mission handed off" notification.
#
# The created RalphLoop is a record of intent: its iterations are driven
# by FleetAutonomyService.tick! (60s) rather than the loop's own
# scheduler — so max_iterations: 0 (unbounded) and scheduling_mode: "manual"
# keep the loop's internal scheduler out of the way.
#
# Per worker convention, this job is API-only with the server.
class AiProvisioningHandoffJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: "ai_execution", retry: 3

  def execute(params)
    params = (params || {}).transform_keys(&:to_s)
    validate_required_params(params, "mission_id", "account_id")

    mission_id = params["mission_id"]
    log_info("Provisioning handoff starting", mission_id: mission_id)

    result = backend_api_post(
      "/api/v1/internal/ai/provisioning/missions/#{mission_id}/handoff",
      {}
    )

    if result.is_a?(Hash) && result["success"] == false
      report_failure(mission_id, result["error"] || "handoff failed")
      return result
    end

    log_info("Provisioning handoff complete",
             mission_id: mission_id,
             ralph_loop_id: result.is_a?(Hash) ? result.dig("data", "ralph_loop_id") : nil)
    result
  rescue StandardError => e
    log_error("AiProvisioningHandoffJob failed", e, mission_id: params && params["mission_id"])
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
