# frozen_string_literal: true

# Per-step worker job for the system_provisioning DAG.
#
# Ai::Provisioning::SkillCompositionRunner#execute! computes parallel-safe
# layers of step ids and dispatches one of these jobs per step in the first
# layer. Each job POSTs to the internal API which invokes the runner's
# execute_step!(step), which in turn dispatches successors as their
# dependencies clear. The runner references this class by string name
# (`WorkerJobService.enqueue_job("AiProvisioningStepJob", ...)`) so this
# closes the loop the runner expected to find at dispatch time.
#
# Args contract (matching SkillCompositionRunner#dispatch_step_job):
#   { mission_id, step_id, account_id, runner_id }
class AiProvisioningStepJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: "ai_execution", retry: 3

  def execute(params)
    params = (params || {}).transform_keys(&:to_s)
    validate_required_params(params, "mission_id", "step_id", "account_id")

    mission_id = params["mission_id"]
    step_id    = params["step_id"]
    runner_id  = params["runner_id"]

    log_info("Provisioning step starting",
             mission_id: mission_id, step_id: step_id, runner_id: runner_id)

    result = backend_api_post(
      "/api/v1/internal/ai/provisioning/missions/#{mission_id}/steps/#{step_id}/execute",
      { runner_id: runner_id }.compact
    )

    if result.is_a?(Hash) && result["success"] == false
      log_warn("Provisioning step reported failure",
               mission_id: mission_id, step_id: step_id,
               error: result["error"])
      return result
    end

    log_info("Provisioning step complete",
             mission_id: mission_id, step_id: step_id,
             status: result.is_a?(Hash) ? result.dig("data", "status") : nil)
    result
  rescue StandardError => e
    log_error("AiProvisioningStepJob failed", e,
              mission_id: params && params["mission_id"],
              step_id: params && params["step_id"])
    raise
  end
end
