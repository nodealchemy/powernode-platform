# frozen_string_literal: true

class AiObservationPipelineJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 1

  def execute(args = {})
    account_id = args["account_id"]
    observations_created = 0
    agents_processed = 0

    if account_id.present?
      # Single account mode
      result = run_for_account(account_id)
      observations_created = result[:observations_created]
      agents_processed = result[:agents_processed]
    else
      # All accounts mode — find accounts with autonomous agents
      response = api_client.get("/api/v1/internal/ai/observation_pipeline/accounts")
      account_ids = response["data"] || []

      account_ids.each do |aid|
        result = run_for_account(aid)
        observations_created += result[:observations_created]
        agents_processed += result[:agents_processed]
      rescue StandardError => e
        log_warn "[AiObservationPipelineJob] Failed for account #{aid}: #{e.message}"
      end
    end

    log_info "[AiObservationPipelineJob] Processed #{agents_processed} agents, created #{observations_created} observations"
    { agents_processed: agents_processed, observations_created: observations_created }
  end

  private

  def run_for_account(account_id)
    response = api_client.post(
      "/api/v1/internal/ai/observation_pipeline/run",
      { account_id: account_id }
    )

    if response["success"]
      {
        observations_created: response.dig("data", "observations_created") || 0,
        agents_processed: response.dig("data", "agents_processed") || 0
      }
    else
      log_warn "[AiObservationPipelineJob] API returned error for account #{account_id}: #{response['error']}"
      { observations_created: 0, agents_processed: 0 }
    end
  end
end
