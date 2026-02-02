# frozen_string_literal: true

module A2a
  module Skills
    # RalphSkills - A2A skill implementations for Ralph Loop operations
    #
    # Provides skills for managing AI-driven development loops:
    # - Create and configure Ralph loops
    # - Start, pause, resume, cancel execution
    # - Monitor progress and status
    # - Query tasks and learnings
    #
    class RalphSkills
      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # Create a new Ralph loop
      def create_loop(input, task = nil)
        ralph_loop = @account.ai_ralph_loops.new(
          name: input["name"],
          description: input["description"],
          repository_url: input["repository_url"],
          branch: input["branch"] || "main",
          ai_tool: input["ai_tool"] || "claude_code",
          max_iterations: input["max_iterations"] || 100,
          configuration: input["configuration"] || {}
        )

        if ralph_loop.save
          # Parse PRD if provided
          if input["prd"].present?
            service = build_execution_service(ralph_loop)
            parse_result = service.parse_prd(input["prd"])

            unless parse_result[:success]
              ralph_loop.destroy
              return { output: { success: false, error: parse_result[:error] } }
            end
          end

          {
            output: {
              success: true,
              loop_id: ralph_loop.id,
              loop: ralph_loop.loop_summary
            }
          }
        else
          {
            output: {
              success: false,
              error: ralph_loop.errors.full_messages.join(", ")
            }
          }
        end
      end

      # Start a Ralph loop
      def start_loop(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        service = build_execution_service(ralph_loop)
        result = service.start_loop

        { output: result }
      end

      # Pause a running Ralph loop
      def pause_loop(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        service = build_execution_service(ralph_loop)
        result = service.pause_loop

        { output: result }
      end

      # Resume a paused Ralph loop
      def resume_loop(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        service = build_execution_service(ralph_loop)
        result = service.resume_loop

        { output: result }
      end

      # Cancel a Ralph loop
      def cancel_loop(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        service = build_execution_service(ralph_loop)
        result = service.cancel_loop(reason: input["reason"])

        { output: result }
      end

      # Run a single iteration
      def run_iteration(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        service = build_execution_service(ralph_loop)
        result = service.run_iteration

        { output: result }
      end

      # Get Ralph loop status
      def get_status(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        service = build_execution_service(ralph_loop)

        {
          output: {
            success: true,
            **service.status
          }
        }
      end

      # List Ralph loops
      def list_loops(input, task = nil)
        scope = @account.ai_ralph_loops.order(created_at: :desc)

        scope = scope.where(status: input["status"]) if input["status"].present?
        scope = scope.where(ai_tool: input["ai_tool"]) if input["ai_tool"].present?

        page = (input["page"] || 1).to_i
        per_page = [(input["per_page"] || 20).to_i, 100].min

        loops = scope.offset((page - 1) * per_page).limit(per_page)

        {
          output: {
            loops: loops.map(&:loop_summary),
            total: scope.count,
            page: page,
            per_page: per_page
          }
        }
      end

      # List tasks for a Ralph loop
      def list_tasks(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        scope = ralph_loop.ralph_tasks.ordered
        scope = scope.where(status: input["status"]) if input["status"].present?

        {
          output: {
            tasks: scope.map(&:task_summary),
            total: scope.count
          }
        }
      end

      # Get task details
      def get_task(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        ralph_task = ralph_loop.ralph_tasks.find_by(task_key: input["task_key"])
        ralph_task ||= ralph_loop.ralph_tasks.find_by(id: input["task_id"])
        return not_found_error("Task") unless ralph_task

        {
          output: {
            task: ralph_task.task_details
          }
        }
      end

      # Get learnings and progress
      def get_progress(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        service = build_execution_service(ralph_loop)

        {
          output: {
            success: true,
            progress: ralph_loop.loop_summary,
            progress_text: ralph_loop.progress_text,
            **service.learnings
          }
        }
      end

      # Get iterations for a Ralph loop
      def list_iterations(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        scope = ralph_loop.ralph_iterations.recent
        scope = scope.where(status: input["status"]) if input["status"].present?
        scope = scope.where(ralph_task_id: input["task_id"]) if input["task_id"].present?

        limit = [(input["limit"] || 20).to_i, 100].min

        {
          output: {
            iterations: scope.limit(limit).map(&:iteration_summary),
            total: scope.count
          }
        }
      end

      # Parse PRD and create tasks
      def parse_prd(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        return { output: { success: false, error: "PRD data is required" } } if input["prd"].blank?

        service = build_execution_service(ralph_loop)
        result = service.parse_prd(input["prd"])

        { output: result }
      end

      # Update progress text
      def update_progress(input, task = nil)
        ralph_loop = find_loop(input["loop_id"])
        return not_found_error("Loop") unless ralph_loop

        service = build_execution_service(ralph_loop)
        result = service.update_progress(input["progress_text"])

        { output: result }
      end

      private

      def find_loop(id)
        @account.ai_ralph_loops.find_by(id: id)
      end

      def build_execution_service(ralph_loop)
        ::Ai::Ralph::ExecutionService.new(
          ralph_loop: ralph_loop,
          account: @account,
          user: @user
        )
      end

      def not_found_error(resource)
        { output: { success: false, error: "#{resource} not found" } }
      end
    end
  end
end
