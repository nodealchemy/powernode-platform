# frozen_string_literal: true

class AiGoalPlanExecutionJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 2

  def execute(step_id)
    validate_required_params({ "step_id" => step_id }, "step_id")

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
