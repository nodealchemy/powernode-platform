# frozen_string_literal: true

# DEPRECATED: This orchestrator is superseded by Ai::AgentTeamExecutionJob which handles
# all team execution via ActiveJob/SolidQueue. This service is retained for reference only.
# Do not add new functionality here — extend the job instead.

# Ai::AgentTeamOrchestrator - Coordinates multi-agent team execution
# Implements CrewAI-style patterns: hierarchical, mesh, sequential, parallel
# Uses A2A protocol for all inter-agent communication
class Ai::AgentTeamOrchestrator
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ExecutionStrategies
  include A2aTaskManagement
  include LifecycleAndContext

  class ExecutionError < StandardError; end
  class TeamNotActiveError < ExecutionError; end
  class NoMembersError < ExecutionError; end

  attr_accessor :team, :user, :workflow_run, :a2a_service

  def initialize(team:, user:)
    @team = team
    @user = user
    @logger = Rails.logger
  end

  # Execute the team with given input
  def execute(input:, context: {})
    validate_team!

    # Create workflow run for tracking
    @workflow_run = create_workflow_run(input, context)

    # Initialize A2A service for inter-agent communication
    @a2a_service = Ai::A2a::Service.new(account: team.account, workflow_run: @workflow_run)

    # Initialize authority enforcement
    @authority = Ai::TeamAuthorityService.new(team: team)

    # Setup shared context using memory service
    @team_context = setup_team_context(input, context)

    @logger.info "[TeamOrchestrator] Executing team #{team.name} (#{team.team_type})"

    begin
      # Route to appropriate execution strategy based on team type
      result = case team.team_type
      when "sequential"
                 execute_sequential
      when "parallel"
                 execute_parallel
      when "hierarchical"
                 execute_hierarchical
      when "mesh"
                 execute_mesh
      else
                 raise ExecutionError, "Unknown team type: #{team.team_type}"
      end

      finalize_execution(result, "completed")
      result
    rescue StandardError => e
      @logger.error "[TeamOrchestrator] Team execution failed: #{e.message}"
      finalize_execution({ error: e.message }, "failed")
      raise
    end
  end

  # Get execution status
  def execution_status
    return { status: "not_started" } unless @workflow_run

    {
      status: @workflow_run.status,
      team_id: team.id,
      team_name: team.name,
      started_at: @workflow_run.created_at,
      completed_at: @workflow_run.completed_at,
      current_node: @workflow_run.current_node_id,
      a2a_tasks: @workflow_run.a2a_tasks.count
    }
  end
end
