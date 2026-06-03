# frozen_string_literal: true

# AI/MCP workload substrate L3 — shared base for agent-fleet mission phase
# jobs. Never enqueued directly: core's Ai::Missions::OrchestratorService
# dispatches the CONCRETE subclasses by job_class string (from the
# system_agent_fleet mission template). Each subclass POSTs to the extension's
# worker_api agent_fleet endpoint for its phase; that controller runs
# System::AgentFleetMissionService and self-advances the mission.
#
# Per worker convention the worker is API-only with the server; api_client
# presents the worker's mTLS client cert (BackendApiClient), which the
# worker_api BaseController verifies against our internal CA.
class AiAgentFleetPhaseJob < BaseJob
  sidekiq_options queue: "ai_execution", retry: 3

  def execute(params)
    params = (params || {}).transform_keys(&:to_s)
    validate_required_params(params, "mission_id", "account_id")
    mission_id = params["mission_id"]
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

  # Phase key — overridden by each concrete job. Maps to both the worker_api
  # route segment and the mission template phase key.
  def phase
    raise NotImplementedError, "#{self.class.name} must define #phase"
  end

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
