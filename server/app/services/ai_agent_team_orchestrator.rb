# frozen_string_literal: true

# AiAgentTeamOrchestrator - Coordinates multi-agent team execution
# Implements CrewAI-style patterns: hierarchical, mesh, sequential, parallel
class AiAgentTeamOrchestrator
  include ActiveModel::Model
  include ActiveModel::Attributes

  class ExecutionError < StandardError; end
  class TeamNotActiveError < ExecutionError; end
  class NoMembersError < ExecutionError; end

  attr_accessor :team, :user, :workflow_run, :communication_hub

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

    # Initialize communication hub
    @communication_hub = Mcp::MultiAgentCommunicationHub.new(workflow_run: @workflow_run)

    # Setup shared context pool for team
    @team_context_pool = setup_team_context(input, context)

    @logger.info "[TeamOrchestrator] Executing team #{team.name} (#{team.team_type})"

    begin
      # Route to appropriate execution strategy based on team type
      result = case team.team_type
               when 'sequential'
                 execute_sequential
               when 'parallel'
                 execute_parallel
               when 'hierarchical'
                 execute_hierarchical
               when 'mesh'
                 execute_mesh
               else
                 raise ExecutionError, "Unknown team type: #{team.team_type}"
               end

      finalize_execution(result, 'completed')
      result
    rescue StandardError => e
      @logger.error "[TeamOrchestrator] Team execution failed: #{e.message}"
      finalize_execution({ error: e.message }, 'failed')
      raise
    end
  end

  # Get execution status
  def execution_status
    return { status: 'not_started' } unless @workflow_run

    {
      status: @workflow_run.status,
      team_id: team.id,
      team_name: team.name,
      started_at: @workflow_run.created_at,
      completed_at: @workflow_run.completed_at,
      current_node: @workflow_run.current_node_id,
      communication_stats: @communication_hub&.communication_stats
    }
  end

  private

  # ==========================================
  # Execution Strategies
  # ==========================================

  # Sequential execution - members execute in priority order
  def execute_sequential
    @logger.info "[TeamOrchestrator] Sequential execution started"

    members = team.ordered_members
    accumulated_output = nil

    members.each do |member|
      @logger.info "[TeamOrchestrator] Executing member: #{member.ai_agent_name} (priority: #{member.priority_order})"

      # Prepare input (first member gets original input, others get previous output)
      member_input = if member.priority_order.zero?
                       read_team_context('original_input')
                     else
                       accumulated_output
                     end

      # Execute member
      result = execute_member(member, member_input)

      # Store output for next member (extract just the output value, not the full result hash)
      accumulated_output = result[:output].is_a?(Hash) && result[:output][:output] ? result[:output][:output] : result[:output]

      # Write intermediate result to team context
      write_team_context("member_#{member.priority_order}_output", accumulated_output)
    end

    {
      success: true,
      output: accumulated_output,
      execution_type: 'sequential',
      members_executed: members.count
    }
  end

  # Parallel execution - all members execute concurrently
  def execute_parallel
    @logger.info "[TeamOrchestrator] Parallel execution started"

    members = team.ai_agent_team_members.includes(:ai_agent) # Preload for thread safety
    original_input = read_team_context('original_input')

    # Execute all members in parallel (simulated with threads)
    results = members.map do |member|
      Thread.new do
        @logger.info "[TeamOrchestrator] Executing member (parallel): #{member.ai_agent_name}"
        execute_member(member, original_input)
      end
    end.map(&:value)

    # Aggregate results
    aggregated_output = aggregate_parallel_results(results)

    {
      success: true,
      output: aggregated_output,
      execution_type: 'parallel',
      members_executed: members.count,
      individual_results: results
    }
  end

  # Hierarchical execution - lead coordinates workers
  def execute_hierarchical
    @logger.info "[TeamOrchestrator] Hierarchical execution started"

    lead = team.team_lead
    raise NoMembersError, "Hierarchical team requires a lead member" unless lead

    workers = team.ai_agent_team_members.non_leads.by_priority

    # Lead analyzes input and creates work plan
    original_input = read_team_context('original_input')
    work_plan = create_work_plan(lead, original_input, workers)

    # Lead delegates tasks to workers
    worker_results = workers.map do |worker|
      task = work_plan[:tasks].find { |t| t[:assigned_to] == worker.id }
      next unless task

      @logger.info "[TeamOrchestrator] Lead delegating to #{worker.ai_agent_name}"

      # Send command from lead to worker
      command_msg = @communication_hub.send_command(
        coordinator_agent_id: lead.ai_agent_id,
        worker_agent_id: worker.ai_agent_id,
        command: task[:instructions]
      )

      # Execute worker task
      worker_result = execute_member(worker, task[:input])

      # Worker reports back to lead
      @communication_hub.report_result(
        worker_agent_id: worker.ai_agent_id,
        coordinator_agent_id: lead.ai_agent_id,
        result: worker_result[:output],
        command_message_id: command_msg.message_id
      )

      worker_result
    end.compact

    # Lead synthesizes final result
    final_result = synthesize_hierarchical_results(lead, worker_results)

    {
      success: true,
      output: final_result,
      execution_type: 'hierarchical',
      lead: lead.ai_agent_name,
      workers_executed: worker_results.count
    }
  end

  # Mesh execution - peer-to-peer collaboration
  def execute_mesh
    @logger.info "[TeamOrchestrator] Mesh execution started"

    members = team.ai_agent_team_members.includes(:ai_agent) # Preload for thread safety
    original_input = read_team_context('original_input')

    # Create blackboard for collaboration
    blackboard = @communication_hub.create_context_pool(
      owner_agent_id: members.first.ai_agent_id,
      pool_type: 'blackboard',
      scope: 'agent_group', # Team is conceptually an agent_group
      initial_data: { 'contributions' => [], 'problem' => original_input }
    )

    # Grant access to all team members (required for blackboard collaboration)
    members.each do |member|
      blackboard.grant_access(member.ai_agent_id) unless member.ai_agent_id == blackboard.owner_agent_id
    end

    # Each member contributes to the solution
    members.each do |member|
      @logger.info "[TeamOrchestrator] Member #{member.ai_agent_name} contributing to mesh"

      # Read current blackboard state
      blackboard_state = @communication_hub.read_blackboard(
        blackboard_id: blackboard.pool_id,
        agent_id: member.ai_agent_id
      )

      # Member processes and contributes
      member_input = {
        original_input: original_input,
        blackboard_state: blackboard_state[:contributions],
        peer_count: members.count
      }

      result = execute_member(member, member_input)

      # Post contribution to blackboard
      @communication_hub.post_to_blackboard(
        blackboard_id: blackboard.pool_id,
        agent_id: member.ai_agent_id,
        contribution: result[:output]
      )
    end

    # Aggregate all contributions
    final_blackboard = @communication_hub.read_blackboard(
      blackboard_id: blackboard.pool_id,
      agent_id: members.first.ai_agent_id
    )

    {
      success: true,
      output: aggregate_mesh_contributions(final_blackboard[:contributions]),
      execution_type: 'mesh',
      members_executed: members.count,
      contributions: final_blackboard[:contributions]
    }
  end

  # ==========================================
  # Helper Methods
  # ==========================================

  def validate_team!
    raise TeamNotActiveError, "Team must be active" unless team.active?
    raise NoMembersError, "Team has no members" if team.ai_agent_team_members.empty?
  end

  def create_workflow_run(input, context)
    # Note: This creates a placeholder workflow for team execution
    # In production, you might create a dedicated team execution record
    workflow = team.account.ai_workflows.find_or_create_by!(
      name: "Team Execution: #{team.name}",
      slug: "team-execution-#{team.id}",
      creator_id: user.id
    ) do |w|
      w.description = "Auto-generated workflow for team #{team.name}"
      w.status = 'active'
      w.configuration = { 'team_execution' => true }
      w.metadata = {
        'team_id' => team.id,
        'team_type' => team.team_type,
        'auto_generated' => true
      }
    end

    workflow.ai_workflow_runs.create!(
      account_id: team.account_id,
      run_id: "team_#{team.id}_#{SecureRandom.hex(8)}",
      status: 'running',
      trigger_type: 'manual',
      triggered_by_user_id: user.id,
      started_at: Time.current,
      input_variables: {
        'team_id' => team.id,
        'team_name' => team.name,
        'input' => input,
        'context' => context
      },
      metadata: {
        'team_type' => team.team_type,
        'coordination_strategy' => team.coordination_strategy,
        'member_count' => team.ai_agent_team_members.count,
        'orchestrator' => 'team_orchestrator'
      }
    )
  end

  def setup_team_context(input, context)
    @communication_hub.create_context_pool(
      owner_agent_id: team.ai_agent_team_members.first&.ai_agent_id,
      pool_type: 'shared_memory',
      scope: 'agent_group',  # Team is an agent_group
      initial_data: {
        'team_id' => team.id,
        'original_input' => input,
        'context' => context,
        'started_at' => Time.current.iso8601
      }
    )
  end

  def execute_member(member, input)
    # Execute the agent with role-specific context
    execution_result = member.execute(
      context: {
        input: input,
        team_context: read_team_context_all,
        role: member.role,
        capabilities: member.capabilities
      },
      user: @user
    )

    {
      member_id: member.id,
      agent_id: member.ai_agent_id,
      agent_name: member.ai_agent_name,
      role: member.role,
      output: execution_result,
      should_stop: false
    }
  rescue StandardError => e
    @logger.error "[TeamOrchestrator] Member execution failed: #{e.message}"
    # Re-raise the exception so it can be caught by main execute block
    raise
  end

  def create_work_plan(lead, input, workers)
    # Lead creates distribution plan
    # In production, this would involve executing the lead agent to create the plan
    {
      tasks: workers.map.with_index do |worker, idx|
        {
          id: idx,
          assigned_to: worker.id,
          agent_name: worker.ai_agent_name,
          role: worker.role,
          instructions: "Process input based on your #{worker.role} role",
          input: input
        }
      end
    }
  end

  def synthesize_hierarchical_results(lead, worker_results)
    # Lead synthesizes all worker outputs
    # In production, this would execute the lead agent with worker outputs
    {
      synthesized: true,
      worker_outputs: worker_results.map { |r| r[:output] },
      synthesizer: lead.ai_agent_name
    }
  end

  def aggregate_parallel_results(results)
    {
      aggregated: true,
      results: results.map { |r| r[:output] },
      count: results.count
    }
  end

  def aggregate_mesh_contributions(contributions)
    {
      collaborative_result: true,
      contributions: contributions.map { |c| c['contribution'] },
      contributor_count: contributions.count
    }
  end

  def write_team_context(key, value)
    @communication_hub.write_to_pool(
      pool_id: @team_context_pool.pool_id,
      key: key,
      value: value,
      agent_id: @team_context_pool.owner_agent_id
    )
  end

  def read_team_context(key)
    result = @communication_hub.read_from_pool(
      pool_id: @team_context_pool.pool_id,
      key: key,
      agent_id: @team_context_pool.owner_agent_id
    )
    result[:value]
  end

  def read_team_context_all
    @team_context_pool.context_data
  end

  def finalize_execution(result, status)
    update_params = {
      status: status,
      completed_at: Time.current,
      output_variables: result,
      duration_ms: ((Time.current - @workflow_run.created_at) * 1000).to_i
    }

    # Add error_details for failed runs (required by validation)
    if status == 'failed'
      update_params[:error_details] = result[:error] || 'Unknown error occurred during team execution'
    end

    @workflow_run.update!(update_params)

    write_team_context('final_result', result)
    write_team_context('completed_at', Time.current.iso8601)
  end
end
