# frozen_string_literal: true

# AiTrajectoryBuildJob - Builds trajectory narratives from completed team executions
# Called asynchronously after team execution completes to avoid blocking the orchestrator
class AiTrajectoryBuildJob < BaseJob
  queue_as :ai_orchestration
  sidekiq_options retry: 2

  def execute(args = {})
    @account_id = args[:account_id] || args['account_id']
    @execution_id = args[:execution_id] || args['execution_id']

    raise ArgumentError, "account_id is required" unless @account_id
    raise ArgumentError, "execution_id is required" unless @execution_id

    # Fetch execution data from backend
    execution_data = fetch_execution

    # Trigger trajectory build on backend
    result = build_trajectory(execution_data)

    logger.info "[AiTrajectoryBuildJob] Trajectory built for execution #{@execution_id}"
    result
  end

  private

  def fetch_execution
    response = api_client.get("/api/v1/internal/team_executions/#{@execution_id}")
    raise "Execution not found: #{@execution_id}" unless response['success']

    response['data']
  end

  def build_trajectory(execution_data)
    response = api_client.post(
      "/api/v1/ai/teams/trajectories/build",
      {
        account_id: @account_id,
        execution_id: @execution_id,
        execution_data: execution_data
      }
    )

    raise "Trajectory build failed: #{response['error']}" unless response['success']

    response['data']
  rescue StandardError => e
    logger.error "[AiTrajectoryBuildJob] Failed to build trajectory: #{e.message}"
    report_failure(e)
    raise
  end

  def report_failure(error)
    api_client.post(
      "/api/v1/internal/team_executions/#{@execution_id}/trajectory_failed",
      {
        error: error.message,
        job_id: jid,
        failed_at: Time.current.iso8601
      }
    )
  rescue StandardError
    # Ignore reporting failures
  end
end
