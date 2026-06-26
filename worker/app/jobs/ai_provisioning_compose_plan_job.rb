# frozen_string_literal: true

# Phase-1 worker job for the system_provisioning mission template.
# Wraps the server-side Ai::Provisioning::PlanComposerService through the
# internal API. Per worker convention, the worker is API-only with the server.
class AiProvisioningComposePlanJob < BaseJob
  include AiJobsConcern
  include AiSuspensionCheckConcern

  sidekiq_options queue: "ai_execution", retry: 3

  def execute(params)
    params = (params || {}).transform_keys(&:to_s)
    validate_required_params(params, "mission_id", "account_id")

    mission_id = params["mission_id"]

    # Kill switch check — bail if AI activity is suspended for the account
    return if bail_if_ai_suspended!(params["account_id"])

    log_info("Provisioning compose_plan starting", mission_id: mission_id)

    result = backend_api_post(
      "/api/v1/internal/ai/provisioning/missions/#{mission_id}/compose_plan",
      {}
    )

    if result.is_a?(Hash) && result["success"] == false
      report_failure(mission_id, result["error"] || "compose_plan failed")
      return result
    end

    log_info("Provisioning compose_plan complete",
             mission_id: mission_id,
             plan_id: result.is_a?(Hash) ? result.dig("data", "plan_id") : nil)
    result
  rescue StandardError => e
    log_error("AiProvisioningComposePlanJob failed", e, mission_id: params && params["mission_id"])
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
