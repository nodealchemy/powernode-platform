# frozen_string_literal: true

module Ai
  module Ralph
    class ExecutionService
      module IterationExecution
        extend ActiveSupport::Concern

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

        private

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

          # Set git_branch when commits were made
          if result[:commit_sha].present?
            iteration.update_columns(git_branch: ralph_loop.branch)
          end

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
          return nil if output.blank?

          # Look for explicit learning markers
          if output.include?("Learning:") || output.include?("Learned:")
            output.scan(/(?:Learning|Learned):\s*(.+?)(?:\n|$)/i).flatten.first
          end
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
      end
    end
  end
end
