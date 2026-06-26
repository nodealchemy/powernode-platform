# frozen_string_literal: true

class AiGoalPlanExecutionJob < BaseJob
  include AiSuspensionCheckConcern

  sidekiq_options queue: "ai_orchestration", retry: 2

  # account_id is resolved server-side at enqueue (from the step's goal plan) and
  # threaded through so the worker can honor the per-account kill switch. It is
  # optional for backward compatibility with any in-flight old-format jobs.
  def execute(step_id, account_id = nil)
    validate_required_params({ "step_id" => step_id }, "step_id")

    # Kill switch check — bail if AI activity is suspended for the account
    return if bail_if_ai_suspended!(account_id)

    log_info("Executing goal plan step", step_id: step_id)

    response = with_api_retry do
      api_client.post("/api/v1/internal/ai/goal_plans/execute_step", {
        step_id: step_id
      })
    end

    if response["success"]
      log_info("Goal plan step executed", step_id: step_id, status: response.dig("data", "status"))
    else
      log_warn("Goal plan step execution failed", step_id: step_id, error: response["error"])
    end
  rescue StandardError => e
    log_error("Goal plan step execution failed", e, step_id: step_id)
    raise
  end
end
