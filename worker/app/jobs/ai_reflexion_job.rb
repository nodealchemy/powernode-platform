# frozen_string_literal: true

class AiReflexionJob < BaseJob
  include AiSuspensionCheckConcern

  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(execution_id)
    validate_required_params({ "execution_id" => execution_id }, "execution_id")

    log_info("Starting reflexion analysis", execution_id: execution_id)

    # Kill switch check — resolve the owning account from the execution record
    # and bail if AI activity is suspended before triggering reflexion.
    execution = api_client.get("/api/v1/internal/ai/executions/#{execution_id}")
    account_id = execution.dig("data", "agent_execution", "account_id")
    return if bail_if_ai_suspended!(account_id)

    # Trigger reflexion via API
    response = with_api_retry do
      api_client.post("/api/v1/internal/ai/reflexions/reflect", {
        execution_id: execution_id
      })
    end

    if response["success"]
      learning_id = response.dig("data", "learning_id")
      log_info("Reflexion completed", execution_id: execution_id, learning_id: learning_id)
    else
      log_warn("Reflexion produced no result", execution_id: execution_id, error: response["error"])
    end
  rescue StandardError => e
    log_error("Reflexion failed", e, execution_id: execution_id)
    raise
  end
end
