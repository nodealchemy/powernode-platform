# frozen_string_literal: true

class AiReflexionJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(execution_id)
    validate_required_params({ "execution_id" => execution_id }, "execution_id")

    log_info("Starting reflexion analysis", execution_id: execution_id)

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
