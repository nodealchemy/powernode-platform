# frozen_string_literal: true

# Shared execution for AI/MCP workload substrate L3 agent-fleet mission phase
# jobs. Each concrete job (AiAgentFleet{Plan,Provision,Delegate,Aggregate,Reap}Job)
# is `< BaseJob`, `include`s this, and defines a PHASE constant. The job POSTs its
# phase to the extension worker_api; that controller runs
# System::AgentFleetMissionService#<phase>! and self-advances the mission.
#
# This is a concern (not a base class) on purpose: worker/config/boot.rb loads
# app/jobs/concerns/** BEFORE the job-file glob, so `include` is load-order-safe.
# A shared base class would be required mid-glob and break (a subclass file can
# sort before its parent) — which is why the AiProvisioning* jobs avoid one too.
module AiAgentFleetPhaseExecution
  def execute(params)
    params = (params || {}).transform_keys(&:to_s)
    validate_required_params(params, "mission_id", "account_id")
    mission_id = params["mission_id"]
    phase = self.class::PHASE
    log_info("[#{self.class.name}] #{phase} starting", mission_id: mission_id)

    result = api_client.post(
      "/api/v1/system/worker_api/agent_fleet/missions/#{mission_id}/#{phase}", {}
    )

    if result.is_a?(Hash) && result["success"] == false
      report_failure(mission_id, result["error"] || "#{phase} failed")
      return result
    end

    log_info("[#{self.class.name}] #{phase} complete", mission_id: mission_id)
    result
  rescue StandardError => e
    log_error("[#{self.class.name}] failed", e, mission_id: params && params["mission_id"])
    report_failure(params && params["mission_id"], e.message) if params && params["mission_id"]
    raise
  end

  private

  def report_failure(mission_id, message)
    return unless mission_id

    api_client.patch(
      "/api/v1/ai/missions/#{mission_id}",
      { mission: { status: "failed", error_message: message } }
    )
  rescue StandardError => e
    log_warn("[#{self.class.name}] failed to report mission failure", error: e.message)
  end
end
