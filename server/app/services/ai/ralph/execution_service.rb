# frozen_string_literal: true

module Ai
  module Ralph
    # ExecutionService - Orchestrates Ralph Loop execution
    #
    # Ralph Loops implement an iterative AI-driven development pattern:
    # 1. Parse PRD into discrete tasks
    # 2. Select next task based on priority and dependencies
    # 3. Execute task using configured AI tool (AMP/Claude Code)
    # 4. Validate results and extract learnings
    # 5. Repeat until all tasks completed or max iterations reached
    #
    class ExecutionService
      attr_reader :ralph_loop, :account, :user

      def initialize(ralph_loop:, account: nil, user: nil)
        @ralph_loop = ralph_loop
        @account = account || ralph_loop.account
        @user = user
      end

      # Start the Ralph loop execution
      def start_loop
        return error_result("Loop is not in pending status") unless ralph_loop.can_start?
        return error_result("No tasks defined") if ralph_loop.ralph_tasks.empty?

        ralph_loop.start!

        # Check for blocked tasks and unblock if dependencies are satisfied
        update_blocked_tasks

        success_result(loop: ralph_loop.loop_summary, message: "Loop started successfully")
      rescue StandardError => e
        error_result("Failed to start loop: #{e.message}")
      end

      # Pause the loop execution
      def pause_loop
        return error_result("Loop is not running") unless ralph_loop.can_pause?

        deactivate_run_all_if_active
        ralph_loop.pause!
        success_result(loop: ralph_loop.loop_summary, message: "Loop paused successfully")
      rescue StandardError => e
        error_result("Failed to pause loop: #{e.message}")
      end

      # Resume a paused loop
      def resume_loop
        return error_result("Loop is not paused") unless ralph_loop.can_resume?

        ralph_loop.resume!
        success_result(loop: ralph_loop.loop_summary, message: "Loop resumed successfully")
      rescue StandardError => e
        error_result("Failed to resume loop: #{e.message}")
      end

      # Cancel the loop
      def cancel_loop(reason: nil)
        return error_result("Loop cannot be cancelled") unless ralph_loop.can_cancel?

        deactivate_run_all_if_active
        ralph_loop.cancel!(reason: reason)
        success_result(loop: ralph_loop.loop_summary, message: "Loop cancelled")
      rescue StandardError => e
        error_result("Failed to cancel loop: #{e.message}")
      end

      # Run all remaining iterations
      # When parallel: true, uses git worktrees for parallel execution
      def run_all(stop_on_error: true, parallel: false, max_parallel: 4, merge_strategy: "sequential")
        return error_result("Loop is not running") unless ralph_loop.status == "running"
        return error_result("Run All is already active") if ralph_loop.configuration&.dig("run_all_active")

        if parallel
          return run_all_parallel(max_parallel: max_parallel, merge_strategy: merge_strategy)
        end

        config = ralph_loop.configuration || {}
        config["run_all_active"] = true
        ralph_loop.update!(configuration: config)

        ::Ai::RalphLoopRunAllJob.perform_later(ralph_loop.id, stop_on_error: stop_on_error)

        success_result(loop: ralph_loop.loop_summary, message: "Run All started")
      rescue StandardError => e
        error_result("Failed to start Run All: #{e.message}")
      end

      # Stop Run All execution
      def stop_run_all
        deactivate_run_all_if_active
        success_result(loop: ralph_loop.reload.loop_summary, message: "Run All stopped")
      rescue StandardError => e
        error_result("Failed to stop Run All: #{e.message}")
      end

      # Run a single iteration of the loop
      def run_iteration
        return error_result("Loop is not running") unless ralph_loop.status == "running"
        return complete_loop_result if ralph_loop.all_tasks_completed?
        return max_iterations_result if ralph_loop.max_iterations_reached?

        task = select_next_task
        return no_task_result unless task

        iteration = execute_iteration(task)
        success_result(
          iteration: iteration.iteration_summary,
          loop: ralph_loop.reload.loop_summary,
          next_action: determine_next_action
        )
      rescue StandardError => e
        Rails.logger.error("Ralph iteration failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
        error_result("Iteration failed: #{e.message}")
      end

      # Select the next task to work on
      def select_next_task
        # First, check for any in-progress tasks
        in_progress = ralph_loop.ralph_tasks.in_progress.first
        return in_progress if in_progress

        # Update blocked status for all tasks
        update_blocked_tasks

        # Get next pending task by priority
        ralph_loop.ralph_tasks
                  .pending
                  .by_priority
                  .find { |t| t.dependencies_satisfied? }
      end

      # Update the progress text for the loop
      def update_progress(text)
        ralph_loop.update!(progress_text: text)
        success_result(progress_text: text)
      end

      # Parse PRD JSON and create tasks
      def parse_prd(prd_data)
        return error_result("PRD data is required") if prd_data.blank?

        ActiveRecord::Base.transaction do
          ralph_loop.update!(prd_json: prd_data)

          # Clear existing tasks if reparsing
          ralph_loop.ralph_tasks.destroy_all

          tasks = extract_tasks_from_prd(prd_data)
          created_tasks = tasks.map.with_index do |task_data, index|
            ralph_loop.ralph_tasks.create!(
              task_key: task_data[:key] || "task_#{index + 1}",
              description: task_data[:description],
              priority: task_data[:priority] || 0,
              position: index + 1,
              dependencies: task_data[:dependencies] || [],
              acceptance_criteria: task_data[:acceptance_criteria],
              metadata: task_data[:metadata] || {}
            )
          end

          ralph_loop.update!(total_tasks: created_tasks.count)

          success_result(
            tasks_created: created_tasks.count,
            tasks: created_tasks.map(&:task_summary)
          )
        end
      rescue StandardError => e
        error_result("Failed to parse PRD: #{e.message}")
      end

      # Get current loop status
      def status
        {
          loop: ralph_loop.loop_summary,
          tasks: ralph_loop.ralph_tasks.ordered.map(&:task_summary),
          recent_iterations: ralph_loop.ralph_iterations.recent.limit(5).map(&:iteration_summary),
          next_task: select_next_task&.task_summary
        }
      end

      # Get accumulated learnings
      def learnings
        {
          learnings: ralph_loop.learnings || [],
          total_count: (ralph_loop.learnings || []).count,
          by_iteration: learnings_by_iteration
        }
      end

      private

      def run_all_parallel(max_parallel:, merge_strategy:)
        repo_path = ralph_loop.repository_url
        return error_result("Repository path is required for parallel execution") if repo_path.blank?
        return error_result("Repository path does not exist") unless File.directory?(repo_path)

        # Validate branch protection
        protection = Ai::Git::BranchProtectionService.new(account: account)
        if protection.protection_summary[:enabled]
          Rails.logger.info "[Ralph] Branch protection active — parallel execution will use worktrees"
        end

        # Gather pending tasks with satisfied dependencies
        update_blocked_tasks
        pending_tasks = ralph_loop.ralph_tasks.pending.by_priority.select(&:dependencies_satisfied?)
        return error_result("No pending tasks available") if pending_tasks.empty?

        # Build task configs with agent resolution
        task_configs = pending_tasks.map do |task|
          agent = resolve_agent_for_task(task)
          {
            task: task,
            agent_id: agent&.id,
            branch_suffix: task.task_key.parameterize,
            metadata: { task_key: task.task_key, task_id: task.id }
          }
        end

        service = ::Ai::ParallelExecutionService.new(account: account, user: user)
        result = service.start_session(
          source: ralph_loop,
          tasks: task_configs,
          repository_path: repo_path,
          options: {
            base_branch: ralph_loop.branch || "main",
            merge_strategy: merge_strategy,
            max_parallel: max_parallel,
            configuration: { failure_policy: "continue" }
          }
        )

        if result[:success]
          config = ralph_loop.configuration || {}
          config["parallel_session_id"] = result.dig(:session, :id)
          ralph_loop.update!(configuration: config)
        end

        result
      rescue StandardError => e
        error_result("Failed to start parallel execution: #{e.message}")
      end

      def resolve_agent_for_task(task)
        executor = task.find_matching_executor
        return executor if executor.is_a?(::Ai::Agent)

        ralph_loop.default_agent
      end

      def deactivate_run_all_if_active
        return unless ralph_loop.configuration&.dig("run_all_active")

        config = ralph_loop.configuration || {}
        config["run_all_active"] = false
        ralph_loop.update_column(:configuration, config)
      end

      def execute_iteration(task)
        task.start!

        iteration = ralph_loop.create_iteration(task: task)
        iteration.start!

        prompt = build_task_prompt(task)
        iteration.update!(ai_prompt: prompt)

        executor = Ai::Ralph::TaskExecutor.new(task: task, ralph_loop: ralph_loop)
        result = executor.execute

        if result[:success]
          process_successful_iteration(iteration, task, result)
        else
          process_failed_iteration(iteration, task, result)
        end

        iteration
      end

      def build_task_prompt(task)
        context = {
          task_key: task.task_key,
          description: task.description,
          acceptance_criteria: task.acceptance_criteria,
          repository: ralph_loop.repository_url,
          branch: ralph_loop.branch,
          previous_learnings: ralph_loop.recent_learnings(limit: 5),
          iteration: ralph_loop.current_iteration + 1
        }

        # Inject shared learnings from global pool
        shared_learnings_text = inject_shared_learnings(task)

        # Build structured prompt
        <<~PROMPT
          ## Task: #{task.task_key}

          #{task.description}

          ### Acceptance Criteria
          #{task.acceptance_criteria || "No specific criteria defined"}

          ### Context
          - Repository: #{context[:repository] || "Not specified"}
          - Branch: #{context[:branch]}
          - Iteration: #{context[:iteration]}

          ### Previous Learnings
          #{format_learnings(context[:previous_learnings])}

          #{shared_learnings_text}

          ### Instructions
          Complete this task according to the acceptance criteria.
          Provide clear output showing what was done.
          Mark discoveries with `Discovery:`, patterns with `Pattern:`, warnings with `Anti-pattern:`, and best practices with `Best practice:`.
        PROMPT
      end

      def format_learnings(learnings)
        return "No previous learnings" if learnings.blank?

        learnings.map { |l| "- #{l['text']}" }.join("\n")
      end

      def process_successful_iteration(iteration, task, result)
        iteration.complete!(
          output: result[:output],
          checks_passed: result[:checks_passed],
          commit_sha: result[:commit_sha],
          learning: extract_learning(result[:output])
        )

        iteration.record_token_usage(
          input: result.dig(:tokens, :input) || 0,
          output: result.dig(:tokens, :output) || 0,
          cost: result[:cost]
        )

        if result[:checks_passed]
          task.pass!(iteration_number: iteration.iteration_number)
        else
          # Checks failed, task needs retry
          update_progress("Task #{task.task_key}: Checks failed, will retry")
        end

        ralph_loop.increment_iteration!

        # Extract and store shared learnings
        store_iteration_learnings(result[:output])

        # Broadcast real-time updates
        broadcast_iteration_completed(iteration)
        broadcast_task_status_changed(task)
        broadcast_progress
      end

      def process_failed_iteration(iteration, task, result)
        iteration.fail!(
          error_message: result[:error],
          error_code: result[:error_code],
          error_details: result[:error_details] || {}
        )

        task.fail!(
          error_message: result[:error],
          error_code: result[:error_code]
        )

        ralph_loop.increment_iteration!

        # Broadcast real-time updates
        broadcast_iteration_completed(iteration)
        broadcast_task_status_changed(task)
        broadcast_progress
      end

      def extract_learning(output)
        # Extract learning from AI output
        # This could be enhanced with more sophisticated extraction
        return nil if output.blank?

        # Look for explicit learning markers
        if output.include?("Learning:") || output.include?("Learned:")
          output.scan(/(?:Learning|Learned):\s*(.+?)(?:\n|$)/i).flatten.first
        end
      end

      def store_iteration_learnings(output)
        pool = ensure_ralph_learning_pool
        return unless pool

        storage = Ai::Memory::StorageService.new(account: account)
        count = storage.process_completed_task(
          pool: pool,
          output: output,
          agent_id: ralph_loop.default_agent&.id
        )
        Rails.logger.info("[Ralph] Stored #{count} learnings from iteration") if count.positive?
      rescue StandardError => e
        Rails.logger.warn("[Ralph] Learning storage failed: #{e.message}")
      end

      def ensure_ralph_learning_pool
        @ralph_pool ||= Ai::MemoryPool.find_or_create_by!(
          account: account,
          name: "Ralph Loop: #{ralph_loop.name}",
          pool_type: "shared",
          scope: "persistent"
        ) do |pool|
          pool.data = { "learnings" => [] }
          pool.access_control = { "public" => true, "agents" => [] }
          pool.persist_across_executions = true
        end
      rescue ActiveRecord::RecordInvalid
        # Pool already exists, find it
        Ai::MemoryPool.find_by(
          account: account,
          name: "Ralph Loop: #{ralph_loop.name}",
          pool_type: "shared",
          scope: "persistent"
        )
      end

      def inject_shared_learnings(task)
        storage = Ai::Memory::StorageService.new(account: account)
        context = storage.build_learning_context(
          query: task.description,
          max_chars: 1500
        )
        context || ""
      rescue StandardError => e
        Rails.logger.warn("[Ralph] Shared learning injection failed: #{e.message}")
        ""
      end

      def update_blocked_tasks
        ralph_loop.ralph_tasks.blocked.find_each do |task|
          task.update!(status: "pending") if task.dependencies_satisfied?
        end

        ralph_loop.ralph_tasks.pending.find_each do |task|
          next if task.dependencies_satisfied?

          task.update!(status: "blocked", error_message: "Waiting for: #{task.blocking_dependencies.join(', ')}")
        end
      end

      def extract_tasks_from_prd(prd_data)
        # Convert ActionController::Parameters to hash if needed
        prd_data = prd_data.to_unsafe_h if prd_data.respond_to?(:to_unsafe_h)

        # Handle different PRD formats
        if prd_data.is_a?(Array)
          prd_data.map { |item| normalize_task_data(item) }
        elsif prd_data.respond_to?(:[]) && prd_data["tasks"]
          prd_data["tasks"].map { |item| normalize_task_data(item) }
        elsif prd_data.is_a?(Hash)
          [ normalize_task_data(prd_data) ]
        else
          []
        end
      end

      def normalize_task_data(data)
        data = data.deep_stringify_keys if data.respond_to?(:deep_stringify_keys)

        {
          key: data["key"] || data["task_key"] || data["id"],
          description: data["description"] || data["title"] || data["name"],
          priority: data["priority"]&.to_i || 0,
          dependencies: Array(data["dependencies"] || data["depends_on"]),
          acceptance_criteria: data["acceptance_criteria"] || data["criteria"],
          metadata: data["metadata"] || {}
        }
      end

      def determine_next_action
        return "completed" if ralph_loop.all_tasks_completed?
        return "max_iterations_reached" if ralph_loop.max_iterations_reached?
        return "paused" if ralph_loop.status == "paused"

        "continue"
      end

      def learnings_by_iteration
        (ralph_loop.learnings || []).group_by { |l| l["iteration"] }
      end

      def complete_loop_result
        ralph_loop.complete!
        success_result(
          loop: ralph_loop.loop_summary,
          message: "All tasks completed successfully",
          completed: true
        )
      end

      def max_iterations_result
        ralph_loop.fail!(
          error_message: "Maximum iterations (#{ralph_loop.max_iterations}) reached",
          error_code: "MAX_ITERATIONS_REACHED"
        )
        error_result("Maximum iterations reached", completed: true)
      end

      def no_task_result
        # Check if there are blocked tasks
        blocked_count = ralph_loop.ralph_tasks.blocked.count
        if blocked_count.positive?
          error_result("All remaining tasks are blocked (#{blocked_count} tasks)")
        else
          complete_loop_result
        end
      end

      # =============================================================================
      # BROADCASTING
      # =============================================================================

      def broadcast_iteration_completed(iteration)
        AiOrchestrationChannel.broadcast_ralph_loop_iteration_completed(
          ralph_loop.reload, iteration.iteration_number
        )
      rescue StandardError => e
        Rails.logger.warn("Failed to broadcast iteration completed: #{e.message}")
      end

      def broadcast_task_status_changed(task)
        AiOrchestrationChannel.broadcast_ralph_loop_task_status_changed(
          ralph_loop, task
        )
      rescue StandardError => e
        Rails.logger.warn("Failed to broadcast task status changed: #{e.message}")
      end

      def broadcast_progress
        AiOrchestrationChannel.broadcast_ralph_loop_progress(ralph_loop)
      rescue StandardError => e
        Rails.logger.warn("Failed to broadcast progress: #{e.message}")
      end

      def success_result(data = {})
        { success: true }.merge(data)
      end

      def error_result(message, data = {})
        { success: false, error: message }.merge(data)
      end
    end
  end
end
