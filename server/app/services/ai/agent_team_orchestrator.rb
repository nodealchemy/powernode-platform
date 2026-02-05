# frozen_string_literal: true

# Ai::AgentTeamOrchestrator - Coordinates multi-agent team execution
# Implements CrewAI-style patterns: hierarchical, mesh, sequential, parallel
# Uses A2A protocol for all inter-agent communication
class Ai::AgentTeamOrchestrator
  include ActiveModel::Model
  include ActiveModel::Attributes

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
      @logger.info "[TeamOrchestrator] Executing member: #{member.agent_name} (priority: #{member.priority_order})"

      # Prepare input (first member gets original input, others get previous output)
      member_input = if member.priority_order.zero?
                       @team_context[:original_input]
      else
                       accumulated_output
      end

      # Execute member via A2A
      result = execute_member_via_a2a(member, member_input)

      # Run review if configured
      run_review_if_configured(result) if result[:success]

      # Store output for next member
      accumulated_output = result[:output]

      # Store intermediate result
      store_intermediate_result("member_#{member.priority_order}", accumulated_output)
    end

    {
      success: true,
      output: accumulated_output,
      execution_type: "sequential",
      members_executed: members.count
    }
  end

  # Parallel execution - all members execute concurrently
  def execute_parallel
    @logger.info "[TeamOrchestrator] Parallel execution started"

    members = team.members.includes(:agent)
    original_input = @team_context[:original_input]

    # Submit all A2A tasks in parallel
    tasks = members.map do |member|
      @logger.info "[TeamOrchestrator] Submitting parallel task for: #{member.agent_name}"

      submit_member_task(member, original_input)
    end

    # Wait for all tasks to complete
    results = tasks.map do |task|
      wait_for_task_completion(task)
    end

    # Aggregate results
    aggregated_output = aggregate_parallel_results(results)

    {
      success: true,
      output: aggregated_output,
      execution_type: "parallel",
      members_executed: members.count,
      individual_results: results
    }
  end

  # Hierarchical execution - lead coordinates workers
  def execute_hierarchical
    @logger.info "[TeamOrchestrator] Hierarchical execution started"

    lead = team.team_lead
    raise NoMembersError, "Hierarchical team requires a lead member" unless lead

    workers = team.members.non_leads.by_priority
    original_input = @team_context[:original_input]

    # Lead analyzes input and creates work plan
    work_plan = create_work_plan(lead, original_input, workers)

    # Lead delegates tasks to workers via A2A
    worker_tasks = workers.map do |worker|
      task_spec = work_plan[:tasks].find { |t| t[:assigned_to] == worker.id }
      next unless task_spec

      @logger.info "[TeamOrchestrator] Lead delegating to #{worker.agent_name}"

      # Submit A2A task from lead to worker
      submit_delegation_task(
        from_member: lead,
        to_member: worker,
        instructions: task_spec[:instructions],
        input: task_spec[:input]
      )
    end.compact

    # Wait for all worker tasks
    worker_results = worker_tasks.map do |task|
      wait_for_task_completion(task)
    end

    # Lead synthesizes final result
    final_result = synthesize_hierarchical_results(lead, worker_results)

    {
      success: true,
      output: final_result,
      execution_type: "hierarchical",
      lead: lead.agent_name,
      workers_executed: worker_results.count
    }
  end

  # Mesh execution - peer-to-peer collaboration via shared context
  def execute_mesh
    @logger.info "[TeamOrchestrator] Mesh execution started"

    members = team.members.includes(:agent)
    original_input = @team_context[:original_input]

    # Initialize collaboration context
    contributions = []

    # Each member contributes to the solution
    members.each do |member|
      @logger.info "[TeamOrchestrator] Member #{member.agent_name} contributing to mesh"

      # Member processes with awareness of peer contributions
      member_input = {
        original_input: original_input,
        peer_contributions: contributions,
        peer_count: members.count
      }

      result = execute_member_via_a2a(member, member_input)

      # Record contribution
      contributions << {
        agent_id: member.ai_agent_id,
        agent_name: member.agent_name,
        contribution: result[:output],
        timestamp: Time.current.iso8601
      }
    end

    {
      success: true,
      output: aggregate_mesh_contributions(contributions),
      execution_type: "mesh",
      members_executed: members.count,
      contributions: contributions
    }
  end

  # ==========================================
  # A2A Task Methods
  # ==========================================

  def execute_member_via_a2a(member, input)
    task = submit_member_task(member, input)
    wait_for_task_completion(task)
  end

  def submit_member_task(member, input)
    # Get or create agent card for the member's agent
    agent_card = find_or_create_agent_card(member.agent)

    @a2a_service.submit_task(
      from_agent: nil, # Team orchestrator
      to_agent_card: agent_card,
      message: build_task_message(member, input),
      metadata: {
        team_id: team.id,
        member_id: member.id,
        role: member.role,
        capabilities: member.capabilities
      }
    )
  end

  def submit_delegation_task(from_member:, to_member:, instructions:, input:)
    from_card = find_or_create_agent_card(from_member.agent)
    to_card = find_or_create_agent_card(to_member.agent)

    @a2a_service.submit_task(
      from_agent: from_member.agent,
      to_agent_card: to_card,
      message: {
        role: "user",
        parts: [
          { type: "text", text: instructions },
          { type: "data", data: input }
        ]
      },
      metadata: {
        team_id: team.id,
        delegation: true,
        from_member_id: from_member.id,
        to_member_id: to_member.id
      }
    )
  end

  def wait_for_task_completion(task, timeout: 300)
    start_time = Time.current

    loop do
      task.reload

      case task.status
      when "completed"
        return {
          task_id: task.task_id,
          output: task.output,
          artifacts: task.artifacts,
          success: true
        }
      when "failed"
        return {
          task_id: task.task_id,
          error: task.error_message,
          success: false
        }
      when "cancelled"
        return {
          task_id: task.task_id,
          error: "Task was cancelled",
          success: false
        }
      end

      if Time.current - start_time > timeout
        task.cancel!("Timeout waiting for completion")
        return {
          task_id: task.task_id,
          error: "Task timeout",
          success: false
        }
      end

      sleep 0.5
    end
  end

  def find_or_create_agent_card(agent)
    Ai::AgentCard.find_or_create_by!(
      account_id: team.account_id,
      ai_agent_id: agent.id
    ) do |card|
      card.name = agent.name
      card.description = agent.description&.truncate(500)
      card.visibility = "private"
      card.status = "active"
      card.capabilities = { "skills" => agent.mcp_capabilities || [] }
    end
  end

  def build_task_message(member, input)
    {
      role: "user",
      parts: [
        {
          type: "text",
          text: "Execute task as #{member.role} with capabilities: #{member.capabilities.join(', ')}"
        },
        {
          type: "data",
          data: input
        }
      ]
    }
  end

  # ==========================================
  # Helper Methods
  # ==========================================

  def validate_team!
    raise TeamNotActiveError, "Team must be active" unless team.active?
    raise NoMembersError, "Team has no members" if team.members.empty?
  end

  def create_workflow_run(input, context)
    # Find or create workflow for this team execution
    # Include version in the lookup to avoid uniqueness constraint issues
    workflow = team.account.ai_workflows.find_or_initialize_by(
      name: "Team Execution: #{team.name}",
      slug: "team-execution-#{team.id}",
      version: "1.0.0"
    )

    unless workflow.persisted?
      workflow.assign_attributes(
        creator_id: user.id,
        description: "Auto-generated workflow for team #{team.name}",
        status: "active",
        configuration: { "team_execution" => true },
        metadata: {
          "team_id" => team.id,
          "team_type" => team.team_type,
          "auto_generated" => true
        }
      )
      workflow.save!
    end

    workflow.runs.create!(
      account_id: team.account_id,
      run_id: "team_#{team.id}_#{SecureRandom.hex(8)}",
      status: "running",
      trigger_type: "manual",
      triggered_by_user_id: user.id,
      started_at: Time.current,
      input_variables: {
        "team_id" => team.id,
        "team_name" => team.name,
        "input" => input,
        "context" => context
      },
      metadata: {
        "team_type" => team.team_type,
        "coordination_strategy" => team.coordination_strategy,
        "member_count" => team.members.count,
        "orchestrator" => "team_orchestrator_a2a"
      }
    )
  end

  def setup_team_context(input, context)
    {
      team_id: team.id,
      original_input: input,
      context: context,
      started_at: Time.current.iso8601
    }
  end

  def store_intermediate_result(key, value)
    @team_context[key.to_sym] = value
  end

  def create_work_plan(lead, input, workers)
    {
      tasks: workers.map.with_index do |worker, idx|
        {
          id: idx,
          assigned_to: worker.id,
          agent_name: worker.agent_name,
          role: worker.role,
          instructions: "Process input based on your #{worker.role} role",
          input: input
        }
      end
    }
  end

  def synthesize_hierarchical_results(lead, worker_results)
    {
      synthesized: true,
      worker_outputs: worker_results.map { |r| r[:output] },
      synthesizer: lead.agent_name
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
      contributions: contributions.map { |c| c[:contribution] },
      contributor_count: contributions.count
    }
  end

  def finalize_execution(result, status)
    update_params = {
      status: status,
      completed_at: Time.current,
      output_variables: result,
      duration_ms: ((Time.current - @workflow_run.created_at) * 1000).to_i
    }

    if status == "failed"
      update_params[:error_details] = result[:error] || "Unknown error occurred during team execution"
    end

    @workflow_run.update!(update_params)

    # Build trajectory from completed execution
    if status == "completed"
      build_trajectory_async
    end
  end

  def build_trajectory_async
    Ai::BuildTrajectoryJob.perform_later(
      account_id: team.account_id,
      team_execution_id: @workflow_run.id
    )
  rescue StandardError => e
    @logger.error "[TeamOrchestrator] Trajectory job enqueue failed: #{e.message}"
  end

  def run_review_if_configured(task_result)
    return unless task_result.is_a?(Hash) && task_result[:task_id]

    team_task = Ai::TeamTask.find_by(task_id: task_result[:task_id])
    return unless team_task

    review_service = Ai::ReviewWorkflowService.new(account: team.account)
    review = review_service.on_task_completed(team_task)
    return unless review&.review_mode == "blocking"

    wait_for_review(review)
  rescue StandardError => e
    @logger.warn "[TeamOrchestrator] Review check skipped: #{e.message}"
  end

  def wait_for_review(review, timeout: 120)
    start_time = Time.current

    loop do
      review.reload

      case review.status
      when "approved"
        @logger.info "[TeamOrchestrator] Review approved: #{review.review_id}"
        return
      when "rejected"
        @logger.warn "[TeamOrchestrator] Review rejected: #{review.review_id}"
        return
      when "revision_requested"
        @logger.info "[TeamOrchestrator] Revision requested: #{review.review_id}"
        return
      end

      if Time.current - start_time > timeout
        @logger.warn "[TeamOrchestrator] Review timeout: #{review.review_id}"
        return
      end

      sleep 1
    end
  end
end
