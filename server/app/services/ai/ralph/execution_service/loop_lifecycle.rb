# frozen_string_literal: true

module Ai
  module Ralph
    class ExecutionService
      module LoopLifecycle
        extend ActiveSupport::Concern

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

          WorkerJobService.enqueue_ai_ralph_loop_run_all(ralph_loop.id, stop_on_error: stop_on_error)

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
            # Safety: reset failed repeating tasks instead of completing the loop
            failed_repeating = ralph_loop.ralph_tasks.where(status: "failed", repeating: true)
            if failed_repeating.exists?
              failed_repeating.find_each(&:reset!)
              error_result("Reset #{failed_repeating.count} failed repeating task(s) — will retry next iteration")
            else
              complete_loop_result
            end
          end
        end
      end
    end
  end
end
