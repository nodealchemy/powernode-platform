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

    log_step_outcome(result, mission_id: mission_id, step_id: step_id)
    result
  rescue StandardError => e
    log_error("AiProvisioningStepJob failed", e,
              mission_id: params && params["mission_id"],
              step_id: params && params["step_id"])
    raise
  end

  private

  # The HTTP envelope's `success` is true for EVERY 200 the internal controller
  # renders; the runner's own verdict is one level down, in `data` — which is
  # SkillCompositionRunner#execute_step!'s return merged with the mission/step
  # ids. Reading the envelope logged "Provisioning step complete" for a step
  # that PARKED on an approval (data.pending), for one that failed inside a 200
  # (data.success == false), and for one refused as a duplicate dispatch
  # (data.already_running) — and reported a `data.status` key that payload never
  # carries. A parked run reading as complete in the log is the worst of those:
  # it hides that the plan is blocked on a human decision.
  def log_step_outcome(result, mission_id:, step_id:)
    inner = result.is_a?(Hash) && result["data"].is_a?(Hash) ? result["data"] : {}
    context = { mission_id: mission_id, step_id: step_id }

    if inner["pending"]
      log_info("Provisioning step parked on approval",
               **context,
               deferred_operation_id: inner["deferred_operation_id"],
               approval_request_id: inner["approval_request_id"])
    elsif inner["already_running"] || inner["skipped"]
      # `skipped` is #resume_step!'s lost-claim / no-longer-parked envelope —
      # a benign race with a concurrent resume, not a failure. It carries no
      # `error`, so the failure arm below would have logged `error: nil`.
      log_info("Provisioning step already in flight; no-op", **context)
    elsif inner["success"] == false
      log_warn("Provisioning step reported failure", **context, error: inner["error"])
    else
      log_info("Provisioning step complete", **context, outputs: inner["outputs"])
    end
  end
end
