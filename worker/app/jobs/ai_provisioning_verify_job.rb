# frozen_string_literal: true

# Phase-4 worker job for the system_provisioning mission template.
# Drives the `verify` phase by POSTing to the internal API, which checks
# whether the provisioned stack hit the mission's slo_targets and either
# advances the mission to `handoff` or marks the verification failed.
#
# For M2 the actual SLO probe is a stub — the long-lived ProjectSloSensor
# (Slice A) handles ongoing SLO sampling once the mission reaches the
# `adapting` phase. This phase is the "did we get to running state" gate.
#
# Per worker convention, this job is API-only with the server.
class AiProvisioningVerifyJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: "ai_execution", retry: 3

  def execute(params)
    params = (params || {}).transform_keys(&:to_s)
    validate_required_params(params, "mission_id", "account_id")

    mission_id = params["mission_id"]
    log_info("Provisioning verify starting", mission_id: mission_id)

    result = backend_api_post(
      "/api/v1/internal/ai/provisioning/missions/#{mission_id}/verify",
      {}
    )

    if result.is_a?(Hash) && result["success"] == false
      report_failure(mission_id, result["error"] || "verify failed")
      return result
    end

    log_info("Provisioning verify complete",
             mission_id: mission_id,
             healthy: result.is_a?(Hash) ? result.dig("data", "healthy") : nil)
    result
  rescue StandardError => e
    log_error("AiProvisioningVerifyJob failed", e, mission_id: params && params["mission_id"])
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
