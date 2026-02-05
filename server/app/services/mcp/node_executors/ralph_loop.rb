# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Ralph Loop node executor - integrates Ralph Loops into AI Workflows
    #
    # Ralph Loops are iterative AI-driven development cycles that parse PRDs,
    # execute tasks, and accumulate learnings. This executor allows workflows
    # to create, manage, and execute Ralph Loops.
    #
    # Configuration options:
    #   operation: The operation to perform (required)
    #     - create: Create a new Ralph Loop
    #     - start: Start an existing Ralph Loop
    #     - run_iteration: Run a single iteration
    #     - run_to_completion: Run until done or max iterations
    #     - pause: Pause a running loop
    #     - resume: Resume a paused loop
    #     - cancel: Cancel a loop
    #     - status: Get current loop status
    #     - get_learnings: Get accumulated learnings
    #     - add_task: Add a task to the loop
    #     - parse_prd: Parse PRD and create tasks
    #
    #   loop_id: ID of existing Ralph Loop (for operations on existing loops)
    #   loop_variable: Variable name containing loop ID (alternative to loop_id)
    #   output_variable: Variable name to store the result/loop ID
    #
    # Create operation options:
    #   name: Loop name (required)
    #   description: Loop description
    #   default_agent_id: ID of the default agent for execution
    #   max_iterations: Maximum iterations allowed
    #   repository_url: Git repository URL
    #   branch: Git branch
    #   prd_json: Initial PRD data
    #   configuration: Additional loop configuration
    #
    # Run operation options:
    #   max_iterations: Override max iterations for this run
    #   timeout_seconds: Timeout for run_to_completion
    #   stop_on_error: Stop on first error (default: true)
    #
    # Add task options:
    #   task_key: Unique task identifier (required)
    #   description: Task description (required)
    #   priority: Task priority (0-10)
    #   dependencies: Array of task keys this depends on
    #   acceptance_criteria: Criteria for task completion
    #
    class RalphLoop < Base
      protected

      def perform_execution
        operation = configuration["operation"]
        log_info "Executing Ralph Loop operation: #{operation}"

        case operation
        when "create"
          perform_create
        when "start"
          perform_start
        when "run_iteration"
          perform_run_iteration
        when "run_to_completion"
          perform_run_to_completion
        when "pause"
          perform_pause
        when "resume"
          perform_resume
        when "cancel"
          perform_cancel
        when "status"
          perform_status
        when "get_learnings"
          perform_get_learnings
        when "add_task"
          perform_add_task
        when "parse_prd"
          perform_parse_prd
        else
          error_result("Unknown operation: #{operation}")
        end
      end

      private

      # =============================================================================
      # Operations
      # =============================================================================

      def perform_create
        account = @orchestrator.account

        loop_attrs = {
          account: account,
          name: resolve_value(configuration["name"]),
          description: resolve_value(configuration["description"]),
          default_agent_id: resolve_value(configuration["default_agent_id"]),
          status: "pending",
          max_iterations: configuration["max_iterations"] || 10,
          current_iteration: 0,
          scheduling_mode: configuration["scheduling_mode"] || "manual",
          repository_url: resolve_value(configuration["repository_url"]),
          branch: resolve_value(configuration["branch"]) || "main",
          prd_json: resolve_value(configuration["prd_json"]),
          configuration: resolve_value(configuration["loop_configuration"]) || {}
        }

        ralph_loop = Ai::RalphLoop.create!(loop_attrs)

        # Store in variable if specified
        store_output_variable(ralph_loop.id)

        log_info "Created Ralph Loop: #{ralph_loop.name} (ID: #{ralph_loop.id})"

        success_result(
          loop_id: ralph_loop.id,
          loop: ralph_loop.loop_summary,
          message: "Ralph Loop created successfully"
        )
      rescue ActiveRecord::RecordInvalid => e
        error_result("Failed to create Ralph Loop: #{e.message}")
      end

      def perform_start
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        service = Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @orchestrator.account
        )

        result = service.start_loop

        if result[:success]
          log_info "Started Ralph Loop: #{ralph_loop.name}"
          success_result(
            loop_id: ralph_loop.id,
            loop: result[:loop],
            message: result[:message]
          )
        else
          error_result(result[:error])
        end
      end

      def perform_run_iteration
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        service = Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @orchestrator.account
        )

        result = service.run_iteration

        if result[:success]
          log_info "Completed iteration for Ralph Loop: #{ralph_loop.name}"
          success_result(
            loop_id: ralph_loop.id,
            loop: result[:loop],
            iteration: result[:iteration],
            next_action: result[:next_action],
            completed: result[:completed] || false
          )
        else
          error_result(result[:error], completed: result[:completed])
        end
      end

      def perform_run_to_completion
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        max_iterations = configuration["max_iterations"] || ralph_loop.max_iterations
        timeout_seconds = configuration["timeout_seconds"] || 3600
        stop_on_error = configuration.fetch("stop_on_error", true)

        service = Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @orchestrator.account
        )

        # Start if pending
        if ralph_loop.status == "pending"
          start_result = service.start_loop
          return error_result(start_result[:error]) unless start_result[:success]
        end

        start_time = Time.current
        iterations_run = 0
        last_result = nil

        loop do
          # Check timeout
          if Time.current - start_time > timeout_seconds
            log_info "Ralph Loop timed out after #{timeout_seconds} seconds"
            break
          end

          # Check max iterations
          if iterations_run >= max_iterations
            log_info "Ralph Loop reached max iterations: #{max_iterations}"
            break
          end

          # Run iteration
          result = service.run_iteration
          last_result = result
          iterations_run += 1

          unless result[:success]
            log_error "Iteration failed: #{result[:error]}"
            break if stop_on_error
          end

          # Check if complete
          break if result[:next_action] == "completed"
          break if result[:next_action] == "max_iterations_reached"
          break if result[:completed]
        end

        ralph_loop.reload

        log_info "Ralph Loop run complete: #{ralph_loop.status} after #{iterations_run} iterations"

        success_result(
          loop_id: ralph_loop.id,
          loop: ralph_loop.loop_summary,
          iterations_run: iterations_run,
          final_status: ralph_loop.status,
          completed: ralph_loop.terminal?,
          learnings: ralph_loop.learnings
        )
      end

      def perform_pause
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        service = Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @orchestrator.account
        )

        result = service.pause_loop

        if result[:success]
          log_info "Paused Ralph Loop: #{ralph_loop.name}"
          success_result(
            loop_id: ralph_loop.id,
            loop: result[:loop],
            message: result[:message]
          )
        else
          error_result(result[:error])
        end
      end

      def perform_resume
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        service = Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @orchestrator.account
        )

        result = service.resume_loop

        if result[:success]
          log_info "Resumed Ralph Loop: #{ralph_loop.name}"
          success_result(
            loop_id: ralph_loop.id,
            loop: result[:loop],
            message: result[:message]
          )
        else
          error_result(result[:error])
        end
      end

      def perform_cancel
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        reason = resolve_value(configuration["reason"])

        service = Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @orchestrator.account
        )

        result = service.cancel_loop(reason: reason)

        if result[:success]
          log_info "Cancelled Ralph Loop: #{ralph_loop.name}"
          success_result(
            loop_id: ralph_loop.id,
            loop: result[:loop],
            message: result[:message]
          )
        else
          error_result(result[:error])
        end
      end

      def perform_status
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        service = Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @orchestrator.account
        )

        status = service.status

        log_info "Retrieved status for Ralph Loop: #{ralph_loop.name}"

        success_result(
          loop_id: ralph_loop.id,
          loop: status[:loop],
          tasks: status[:tasks],
          recent_iterations: status[:recent_iterations],
          next_task: status[:next_task]
        )
      end

      def perform_get_learnings
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        service = Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @orchestrator.account
        )

        learnings = service.learnings

        log_info "Retrieved #{learnings[:total_count]} learnings from Ralph Loop: #{ralph_loop.name}"

        success_result(
          loop_id: ralph_loop.id,
          learnings: learnings[:learnings],
          total_count: learnings[:total_count],
          by_iteration: learnings[:by_iteration]
        )
      end

      def perform_add_task
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        task_attrs = {
          task_key: resolve_value(configuration["task_key"]),
          description: resolve_value(configuration["description"]),
          priority: configuration["priority"] || 0,
          position: ralph_loop.ralph_tasks.count + 1,
          dependencies: configuration["dependencies"] || [],
          acceptance_criteria: resolve_value(configuration["acceptance_criteria"]),
          status: "pending",
          metadata: configuration["task_metadata"] || {}
        }

        task = ralph_loop.ralph_tasks.create!(task_attrs)
        ralph_loop.update!(total_tasks: ralph_loop.ralph_tasks.count)

        log_info "Added task #{task.task_key} to Ralph Loop: #{ralph_loop.name}"

        success_result(
          loop_id: ralph_loop.id,
          task: task.task_summary,
          total_tasks: ralph_loop.total_tasks,
          message: "Task added successfully"
        )
      rescue ActiveRecord::RecordInvalid => e
        error_result("Failed to add task: #{e.message}")
      end

      def perform_parse_prd
        ralph_loop = find_ralph_loop
        return ralph_loop if ralph_loop.is_a?(Hash) && !ralph_loop[:success]

        prd_data = if configuration["prd_variable"].present?
                     get_variable(configuration["prd_variable"])
        else
                     resolve_value(configuration["prd_data"])
        end

        service = Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @orchestrator.account
        )

        result = service.parse_prd(prd_data)

        if result[:success]
          log_info "Parsed PRD for Ralph Loop: #{ralph_loop.name}, created #{result[:tasks_created]} tasks"
          success_result(
            loop_id: ralph_loop.id,
            tasks_created: result[:tasks_created],
            tasks: result[:tasks],
            message: "PRD parsed successfully"
          )
        else
          error_result(result[:error])
        end
      end

      # =============================================================================
      # Helper Methods
      # =============================================================================

      def find_ralph_loop
        loop_id = if configuration["loop_variable"].present?
                    get_variable(configuration["loop_variable"])
        else
                    configuration["loop_id"]
        end

        if loop_id.blank?
          return error_result("No loop_id or loop_variable specified")
        end

        ralph_loop = @orchestrator.account.ai_ralph_loops.find_by(id: loop_id)

        unless ralph_loop
          return error_result("Ralph Loop not found: #{loop_id}")
        end

        ralph_loop
      end

      def resolve_value(value)
        return nil if value.nil?
        return value unless value.is_a?(String)

        # Handle variable references
        if value.start_with?("{{") && value.end_with?("}}")
          variable_name = value[2..-3].strip
          return get_variable(variable_name)
        end

        # Handle $ prefix variables
        if value.start_with?("$")
          variable_name = value[1..]
          return get_variable(variable_name)
        end

        value
      end

      def store_output_variable(value)
        output_var = configuration["output_variable"]
        set_variable(output_var, value) if output_var.present?
      end

      def success_result(data = {})
        {
          output: data,
          result: {
            operation: configuration["operation"],
            success: true
          },
          data: data,
          metadata: {
            node_id: @node.node_id,
            node_type: "ralph_loop",
            operation: configuration["operation"],
            executed_at: Time.current.iso8601
          }
        }
      end

      def error_result(message, extra = {})
        {
          output: { error: message }.merge(extra),
          result: {
            operation: configuration["operation"],
            success: false,
            error: message
          },
          data: extra,
          metadata: {
            node_id: @node.node_id,
            node_type: "ralph_loop",
            operation: configuration["operation"],
            executed_at: Time.current.iso8601,
            error: true
          },
          success: false
        }
      end
    end
  end
end
