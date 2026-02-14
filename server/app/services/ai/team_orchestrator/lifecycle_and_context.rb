# frozen_string_literal: true

class Ai::AgentTeamOrchestrator
  module LifecycleAndContext
    extend ActiveSupport::Concern

    private

    def validate_team!
      raise TeamNotActiveError, "Team must be active" unless team.active?
      raise NoMembersError, "Team has no members" if team.members.empty?

      # Enforce worktree mode when branch protection is active on a repo-based team
      enforce_worktree_mode_if_protected!
    end

    def enforce_worktree_mode_if_protected!
      repo_path = team.team_config&.dig("repository_path")
      return if repo_path.blank?

      protection = Ai::Git::BranchProtectionService.new(account: team.account)
      return unless protection.protection_summary[:enabled]

      return if team.parallel_mode == "worktree"

      @logger.warn "[TeamOrchestrator] Branch protection active — forcing worktree mode for team #{team.name}"
      team.update!(parallel_mode: "worktree") if team.respond_to?(:parallel_mode=)
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
      # Auto-create shared memory pool for this execution
      create_team_execution_pool

      {
        team_id: team.id,
        original_input: input,
        context: context,
        started_at: Time.current.iso8601
      }
    end

    def create_team_execution_pool
      storage = Ai::Memory::StorageService.new(account: team.account)
      @execution_pool = ActiveRecord::Base.transaction(requires_new: true) do
        storage.create_team_execution_pool(
          team_execution: @workflow_run,
          team: team
        )
      end
      @logger.info "[TeamOrchestrator] Created team execution memory pool: #{@execution_pool.pool_id}"
    rescue StandardError => e
      @logger.warn "[TeamOrchestrator] Failed to create execution memory pool: #{e.message}"
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
      @workflow_run.with_lock do
        @workflow_run.reload
        return if %w[completed failed cancelled].include?(@workflow_run.status)

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
      end

      # Build trajectory from completed execution
      if status == "completed"
        build_trajectory_async
        promote_learnings_to_global
      end

      compound_learning_extract(status)
      persist_to_team_memory(result) if status == "completed"
    end

    def extract_learnings_from_task(task_result, agent_id: nil)
      return unless @execution_pool && task_result.is_a?(Hash)

      storage = Ai::Memory::StorageService.new(account: team.account)
      count = storage.process_completed_task(
        pool: @execution_pool,
        output: task_result[:output],
        agent_id: agent_id
      )
      @logger.info "[TeamOrchestrator] Extracted #{count} learnings from task output" if count.positive?
    rescue StandardError => e
      @logger.warn "[TeamOrchestrator] Learning extraction failed: #{e.message}"
    end

    def promote_learnings_to_global
      return unless @execution_pool

      storage = Ai::Memory::StorageService.new(account: team.account)
      promoted = storage.promote_to_global(execution_pool: @execution_pool)
      @logger.info "[TeamOrchestrator] Promoted #{promoted} learnings to global pool" if promoted.positive?
    rescue StandardError => e
      @logger.warn "[TeamOrchestrator] Learning promotion failed: #{e.message}"
    end

    def build_trajectory_async
      Ai::BuildTrajectoryJob.perform_later(
        account_id: team.account_id,
        team_execution_id: @workflow_run.id
      )
    rescue StandardError => e
      @logger.error "[TeamOrchestrator] Trajectory job enqueue failed: #{e.message}"
    end

    def compound_learning_extract(status)
      return unless @workflow_run

      service = Ai::Learning::CompoundLearningService.new(account: team.account)
      count = service.post_execution_extract(@workflow_run)
      @logger.info "[TeamOrchestrator] Extracted #{count} compound learnings" if count.positive?
    rescue StandardError => e
      @logger.warn "[TeamOrchestrator] Compound learning extraction failed: #{e.message}"
    end

    def dispatch_to_runners(session, members)
      dispatch_service = Ai::RunnerDispatchService.new(account: team.account, session: session)
      required_labels = team.team_config&.dig("runner_labels") || []

      session.worktrees.where(status: "ready").each do |worktree|
        runner = dispatch_service.select_runner(required_labels: required_labels)
        next unless runner

        member = members.find { |m| m.ai_agent_id == worktree.ai_agent_id }
        task_input = { input: @team_context[:original_input], role: member&.role, capabilities: member&.capabilities }

        dispatch_service.dispatch(worktree: worktree, task_input: task_input, runner: runner)
      end

      Ai::RunnerDispatchPollJob.perform_later(session.id)
    rescue StandardError => e
      @logger.error "[TeamOrchestrator] Runner dispatch failed: #{e.message}"
    end

    def persist_to_team_memory(execution_result)
      permanent_pool = Ai::MemoryPool.find_by(team_id: team.id, persist_across_executions: true)
      return unless permanent_pool && @workflow_run

      permanent_pool.data["executions"] ||= {}
      permanent_pool.data["executions"][@workflow_run.run_id] = {
        status: @workflow_run.status,
        output: execution_result,
        completed_at: @workflow_run.completed_at&.iso8601
      }
      permanent_pool.save!
    rescue StandardError => e
      @logger.warn "[TeamOrchestrator] Memory persistence failed: #{e.message}"
    end

    # Check if team has Swarm infrastructure bindings
    def swarm_bound?
      @swarm_bound ||= Ai::AgentConnection.exists?(
        account_id: team.account_id,
        connection_type: "infrastructure",
        source_type: "Ai::AgentTeam",
        source_id: team.id,
        target_type: "Devops::SwarmCluster",
        status: "active"
      )
    end

    # Submit a task to a containerized agent instead of via A2A
    def submit_containerized_task(member, input)
      deployment_service = Ai::ContainerAgentDeploymentService.new(account: team.account)

      # Generate a synthetic conversation ID for this team execution task
      conversation_id = "team-#{team.id}-member-#{member.id}-#{SecureRandom.hex(4)}"

      instance = deployment_service.deploy_agent_session(
        agent: member.agent,
        conversation_id: conversation_id,
        user: user
      )

      @logger.info "[TeamOrchestrator] Containerized task submitted for #{member.agent_name} " \
                   "(container: #{instance.execution_id})"

      # Create a lightweight A2A task to track the container execution
      agent_card = find_or_create_agent_card(member.agent)
      task = @a2a_service.submit_task(
        from_agent: nil,
        to_agent_card: agent_card,
        message: build_task_message(member, input),
        metadata: {
          team_id: team.id,
          member_id: member.id,
          role: member.role,
          capabilities: member.capabilities,
          container_execution_id: instance.execution_id,
          containerized: true
        }
      )

      # Link A2A task to container instance
      instance.update!(a2a_task_id: task.id) if task.respond_to?(:id)

      task
    rescue Ai::ContainerAgentDeploymentService::DeploymentError => e
      @logger.error "[TeamOrchestrator] Container deployment failed for #{member.agent_name}: #{e.message}"
      # Fall back to standard A2A execution
      @logger.info "[TeamOrchestrator] Falling back to A2A execution for #{member.agent_name}"
      agent_card = find_or_create_agent_card(member.agent)
      @a2a_service.submit_task(
        from_agent: nil,
        to_agent_card: agent_card,
        message: build_task_message(member, input),
        metadata: {
          team_id: team.id,
          member_id: member.id,
          role: member.role,
          capabilities: member.capabilities,
          container_fallback: true
        }
      )
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
end
