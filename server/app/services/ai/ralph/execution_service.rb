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

        ralph_loop.cancel!(reason: reason)
        success_result(loop: ralph_loop.loop_summary, message: "Loop cancelled")
      rescue StandardError => e
        error_result("Failed to cancel loop: #{e.message}")
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

      def execute_iteration(task)
        task.start!

        iteration = ralph_loop.create_iteration(task: task)
        iteration.start!

        # Execute the AI tool
        result = execute_ai_tool(task, iteration)

        if result[:success]
          process_successful_iteration(iteration, task, result)
        else
          process_failed_iteration(iteration, task, result)
        end

        iteration
      end

      def execute_ai_tool(task, iteration)
        # Build the prompt for the AI tool
        prompt = build_task_prompt(task)
        iteration.update!(ai_prompt: prompt)

        # Execute based on configured AI tool
        case ralph_loop.ai_tool
        when "amp"
          execute_amp(prompt, task, iteration)
        when "claude_code"
          execute_claude_code(prompt, task, iteration)
        when "ollama"
          execute_ollama(prompt, task, iteration)
        else
          { success: false, error: "Unknown AI tool: #{ralph_loop.ai_tool}" }
        end
      end

      def execute_amp(prompt, task, iteration)
        template = Mcp::ContainerTemplate.find_by(slug: "amp-executor")
        return amp_not_configured_error unless template

        execute_container_template(
          template: template,
          prompt: prompt,
          task: task,
          iteration: iteration
        )
      end

      def execute_claude_code(prompt, task, iteration)
        template = Mcp::ContainerTemplate.find_by(slug: "claude-code-executor")
        return claude_code_not_configured_error unless template

        execute_container_template(
          template: template,
          prompt: prompt,
          task: task,
          iteration: iteration
        )
      end

      def execute_ollama(prompt, task, iteration)
        provider = account.ai_providers.find_by(provider_type: "ollama")
        provider ||= account.ai_providers.find_by(slug: "ollama")
        provider ||= account.ai_providers.find_by(slug: "remote-ollama-server")
        return ollama_not_configured_error unless provider

        credential = provider.provider_credentials.active.first
        return ollama_not_configured_error unless credential

        client = Ai::ProviderClientService.new(credential)

        # Build system prompt with context
        system_prompt = build_ollama_system_prompt

        result = client.send_message(
          [
            { role: "system", content: system_prompt },
            { role: "user", content: prompt }
          ],
          model: ralph_loop.configuration&.dig("model") || provider.default_model || "llama3.2",
          max_tokens: ralph_loop.configuration&.dig("max_tokens") || 4096,
          temperature: ralph_loop.configuration&.dig("temperature") || 0.7
        )

        parse_ollama_result(result, task, iteration)
      rescue StandardError => e
        Rails.logger.error("Ollama execution failed: #{e.message}")
        { success: false, error: e.message, error_code: "OLLAMA_EXECUTION_FAILED" }
      end

      def execute_container_template(template:, prompt:, task:, iteration:)
        service = Mcp::ContainerOrchestrationService.new(account: account)

        result = service.execute_from_template(
          template: template,
          inputs: {
            prompt: prompt,
            task_key: task.task_key,
            repository: ralph_loop.repository_url,
            branch: ralph_loop.branch,
            working_directory: ralph_loop.config&.dig("working_directory"),
            iteration_number: iteration.iteration_number
          }
        )

        parse_container_result(result)
      rescue StandardError => e
        Rails.logger.error("Container execution failed: #{e.message}")
        { success: false, error: e.message, error_code: "CONTAINER_EXECUTION_FAILED" }
      end

      def parse_container_result(result)
        {
          success: result[:success],
          output: result[:outputs]&.dig("output") || result[:logs],
          checks_passed: result[:outputs]&.dig("checks_passed"),
          commit_sha: result[:outputs]&.dig("commit_sha"),
          tokens: result[:outputs]&.dig("tokens") || { input: 0, output: 0 },
          cost: result[:outputs]&.dig("cost") || 0,
          error: result[:error],
          error_code: result[:error_code]
        }
      end

      def amp_not_configured_error
        {
          success: false,
          error: "AMP executor template not configured",
          error_code: "AMP_NOT_CONFIGURED"
        }
      end

      def claude_code_not_configured_error
        {
          success: false,
          error: "Claude Code executor template not configured",
          error_code: "CLAUDE_CODE_NOT_CONFIGURED"
        }
      end

      def ollama_not_configured_error
        {
          success: false,
          error: "Ollama provider not configured for this account",
          error_code: "OLLAMA_NOT_CONFIGURED"
        }
      end

      def build_ollama_system_prompt
        <<~SYSTEM
          You are an AI assistant helping with software development tasks.
          You are part of a Ralph Loop - an iterative development cycle.

          Current loop: #{ralph_loop.name}
          Repository: #{ralph_loop.repository_url || 'Not specified'}
          Branch: #{ralph_loop.branch || 'main'}
          Iteration: #{ralph_loop.current_iteration + 1} of #{ralph_loop.max_iterations}

          Instructions:
          1. Complete the task according to the acceptance criteria
          2. Provide clear, actionable output
          3. If you learn something useful for future iterations, include it with "Learning:" prefix
          4. Be concise but thorough
        SYSTEM
      end

      def parse_ollama_result(result, task, iteration)
        unless result[:success]
          return {
            success: false,
            error: result[:error] || "Ollama request failed",
            error_code: result[:error_type] || "OLLAMA_REQUEST_FAILED"
          }
        end

        # Extract content from Ollama response
        response = result[:response]
        content = extract_ollama_content(response)

        # Extract learning from the response
        learning = extract_learning_from_output(content)

        # Add learning to the loop if found
        ralph_loop.add_learning(learning, context: { task_key: task.task_key, iteration: iteration.iteration_number }) if learning.present?

        {
          success: true,
          output: content,
          checks_passed: true, # Ollama doesn't run checks, assume success
          tokens: extract_ollama_tokens(result),
          cost: 0 # Ollama is typically free/local
        }
      end

      def extract_ollama_content(response)
        return "" unless response.is_a?(Hash)

        # Handle different response structures
        if response[:choices]&.first
          response.dig(:choices, 0, :message, :content) || ""
        elsif response[:message]
          response[:message][:content] || ""
        elsif response[:content]
          response[:content]
        else
          response.to_s
        end
      end

      def extract_ollama_tokens(result)
        metadata = result[:metadata] || {}
        {
          input: metadata[:tokens_used] || 0,
          output: 0
        }
      end

      def extract_learning_from_output(output)
        return nil if output.blank?

        # Look for explicit learning markers
        if output.match?(/(?:Learning|Learned|Insight|Takeaway):/i)
          match = output.match(/(?:Learning|Learned|Insight|Takeaway):\s*(.+?)(?:\n\n|\z)/im)
          match[1]&.strip if match
        end
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

          ### Instructions
          Complete this task according to the acceptance criteria.
          Provide clear output showing what was done.
          Extract any learnings that could help future iterations.
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
          [normalize_task_data(prd_data)]
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

      def success_result(data = {})
        { success: true }.merge(data)
      end

      def error_result(message, data = {})
        { success: false, error: message }.merge(data)
      end
    end
  end
end
