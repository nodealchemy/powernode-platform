# frozen_string_literal: true

# AiAgentTeamExecutionJob - Executes AI agent teams asynchronously
# Handles team orchestration in the background with progress tracking and error handling
class AiAgentTeamExecutionJob < BaseJob
  # Job configuration
  sidekiq_options queue: :ai_orchestration, retry: 3

  # Execute team asynchronously
  def execute(args = {})
    # Extract parameters from args hash
    @team_id = args[:team_id] || args['team_id']
    @user_id = args[:user_id] || args['user_id']
    @input = args[:input] || args['input']
    @context = args[:context] || args['context'] || {}

    # Fetch team and user from backend API
    team_data = fetch_team
    user_data = fetch_user

    # Execute team via orchestrator
    result = execute_team_orchestration(team_data, user_data)

    # Report completion to backend
    report_team_execution_complete(result)

    result
  rescue StandardError => e
    # Report failure to backend
    report_team_execution_failed(e)
    raise
  end

  private

  def fetch_team
    response = api_client.get("/api/v1/ai/agent_teams/#{@team_id}")
    raise "Team not found: #{@team_id}" unless response['success']

    response['data']
  end

  def fetch_user
    response = api_client.get("/api/v1/internal/users/#{@user_id}")
    raise "User not found: #{@user_id}" unless response['success']

    response['data']
  end

  def execute_team_orchestration(team_data, user_data)
    # Note: In production, this would use the team orchestrator
    # For now, we'll make an API call to trigger execution on the backend
    # The backend will handle the actual orchestration

    response = api_client.post(
      "/api/v1/ai/agent_teams/#{@team_id}/execute",
      {
        input: @input,
        context: @context,
        user_id: @user_id
      }
    )

    raise "Team execution failed: #{response['error']}" unless response['success']

    response['data']
  end

  def report_team_execution_complete(result)
    api_client.post(
      "/api/v1/ai/agent_teams/#{@team_id}/execution_complete",
      {
        result: result,
        job_id: jid,
        completed_at: Time.current.iso8601
      }
    )
  rescue StandardError
    # Silently ignore reporting failures - job succeeded regardless
  end

  def report_team_execution_failed(error)
    api_client.post(
      "/api/v1/ai/agent_teams/#{@team_id}/execution_failed",
      {
        error: error.message,
        error_class: error.class.name,
        job_id: jid,
        failed_at: Time.current.iso8601
      }
    )
  rescue StandardError
    # Silently ignore reporting failures - error will still be raised
  end

  def api_client
    @api_client ||= BackendApiClient.new
  end
end
