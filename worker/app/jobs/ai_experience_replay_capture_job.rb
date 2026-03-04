# frozen_string_literal: true

class AiExperienceReplayCaptureJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(execution_id, trajectory_id = nil)
    validate_required_params({ "execution_id" => execution_id }, "execution_id")

    log_info("Starting experience replay capture", execution_id: execution_id)

    # Fetch execution data via API
    exec_response = with_api_retry do
      api_client.get("/api/v1/internal/ai/executions/#{execution_id}")
    end

    unless exec_response["success"]
      log_warn("Could not fetch execution #{execution_id}")
      return
    end

    # Trigger capture via API
    capture_response = with_api_retry do
      api_client.post("/api/v1/internal/ai/experience_replays/capture", {
        execution_id: execution_id,
        trajectory_id: trajectory_id
      })
    end

    if capture_response["success"]
      log_info("Experience replay captured", execution_id: execution_id, replay_id: capture_response.dig("data", "id"))
    else
      log_warn("Experience replay capture returned no result", execution_id: execution_id)
    end
  rescue StandardError => e
    log_error("Experience replay capture failed", e, execution_id: execution_id)
    raise
  end
end
