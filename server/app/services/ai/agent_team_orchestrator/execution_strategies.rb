# frozen_string_literal: true

class Ai::AgentTeamOrchestrator
  module ExecutionStrategies
    extend ActiveSupport::Concern

    private

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

    # Parallel execution - route based on parallel_mode
    def execute_parallel
      if team.parallel_mode == "worktree"
        execute_parallel_worktree
      else
        execute_parallel_standard
      end
    end

    # Standard parallel execution via A2A - all members execute concurrently
    def execute_parallel_standard
      @logger.info "[TeamOrchestrator] Standard parallel execution started"

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

    # Worktree-based parallel execution using git worktrees
    def execute_parallel_worktree
      @logger.info "[TeamOrchestrator] Worktree parallel execution started"

      repo_path = team.team_config&.dig("repository_path")
      raise ExecutionError, "repository_path required in team_config for worktree mode" if repo_path.blank?

      members = team.members.includes(:agent)
      original_input = @team_context[:original_input]

      task_configs = members.map do |member|
        {
          task: member,
          agent_id: member.ai_agent_id,
          branch_suffix: member.agent_name.parameterize,
          metadata: {
            member_id: member.id,
            role: member.role,
            input: original_input
          }
        }
      end

      service = Ai::ParallelExecutionService.new(account: team.account, user: user)
      result = service.start_session(
        source: team,
        tasks: task_configs,
        repository_path: repo_path,
        options: {
          base_branch: team.team_config&.dig("base_branch") || "main",
          merge_strategy: team.team_config&.dig("merge_strategy") || "sequential",
          max_parallel: members.count
        }
      )

      # Runner-based execution (opt-in via team_config)
      if team.team_config&.dig("runner_execution") && result[:success]
        session = Ai::WorktreeSession.find(result.dig(:session, :id))
        dispatch_to_runners(session, members)
      end

      {
        success: result[:success],
        output: result,
        execution_type: "parallel_worktree",
        members_executed: members.count,
        session_id: result.dig(:session, :id)
      }
    end

    # Hierarchical execution - lead coordinates workers
    def execute_hierarchical
      @logger.info "[TeamOrchestrator] Hierarchical execution started"

      lead = team.team_lead
      raise NoMembersError, "Hierarchical team requires a lead member" unless lead

      # Validate lead has manager-level authority
      if @authority.authority_level(lead) > 1
        raise ExecutionError, "Team lead '#{lead.agent_name}' does not have manager-level authority"
      end

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
  end
end
