# frozen_string_literal: true

module Ai
  module A2a
    # Unified A2A Service - Handles all agent-to-agent communication
    # Combines discovery, task management, routing, and execution
    class Service
      # ==================== Error Classes ====================
      class A2aError < StandardError
        attr_reader :code, :details

        def initialize(message, code: "A2A_ERROR", details: {})
          @code = code
          @details = details
          super(message)
        end
      end

      class TaskNotFoundError < A2aError
        def initialize(task_id)
          super("Task not found: #{task_id}", code: "TASK_NOT_FOUND")
        end
      end

      class AgentNotFoundError < A2aError
        def initialize(agent_identifier)
          super("Agent not found: #{agent_identifier}", code: "AGENT_NOT_FOUND")
        end
      end

      class InvalidTaskError < A2aError
        def initialize(message, details: {})
          super(message, code: "INVALID_TASK", details: details)
        end
      end

      class ExecutionError < A2aError
        def initialize(message, details: {})
          super(message, code: "EXECUTION_ERROR", details: details)
        end
      end

      def initialize(account:, user: nil, workflow_run: nil)
        @account = account
        @user = user
        @workflow_run = workflow_run
      end

      # ==================== Discovery ====================

      def discover_agents(filter = {})
        scope = Ai::AgentCard.for_discovery(@account.id)

        scope = scope.with_capability(filter[:skill]) if filter[:skill].present?
        scope = scope.with_tag(filter[:tag]) if filter[:tag].present?
        scope = scope.where("name ILIKE ?", "%#{filter[:query]}%") if filter[:query].present?
        scope = scope.by_protocol_version(filter[:protocol_version]) if filter[:protocol_version].present?

        page = filter[:page] || 1
        per_page = [ filter[:per_page] || 20, 100 ].min

        {
          agents: scope.offset((page - 1) * per_page).limit(per_page).map(&:to_a2a_json),
          total: scope.count,
          page: page,
          per_page: per_page
        }
      end

      def get_agent_card(agent_card_id)
        find_agent_card(agent_card_id).to_a2a_json
      end

      def find_agents_for_task(task_description, limit: 10)
        Ai::AgentCard.find_agents_for_task(task_description, account_id: @account.id, limit: limit)
                     .map(&:to_a2a_json)
      end

      # ==================== Task Submission ====================

      def submit_task(to_agent_card:, message:, from_agent: nil, metadata: {}, sync: false)
        card = resolve_agent_card(to_agent_card)
        validate_message(message)

        task = Ai::A2aTask.create!(
          account: @account,
          from_agent_id: from_agent&.id,
          to_agent_id: card.ai_agent_id,
          to_agent_card_id: card.id,
          ai_workflow_run_id: @workflow_run&.id,
          message: normalize_message(message),
          input: extract_input(message),
          metadata: build_metadata(metadata),
          is_external: false
        )

        if sync || @workflow_run.present?
          execute_task_sync(task)
        else
          ::AiA2aTaskExecutionJob.perform_later(task.id)
        end

        task
      end

      def submit_external_task(endpoint_url:, message:, authentication: {}, from_agent: nil, metadata: {})
        validate_message(message)

        task = Ai::A2aTask.create!(
          account: @account,
          from_agent_id: from_agent&.id,
          ai_workflow_run_id: @workflow_run&.id,
          message: normalize_message(message),
          input: extract_input(message),
          metadata: build_metadata(metadata),
          is_external: true,
          external_endpoint_url: endpoint_url,
          external_authentication: authentication
        )

        ::AiA2aExternalTaskJob.perform_later(task.id)
        task
      end

      # ==================== Task Status & Control ====================

      def get_task_status(task_id)
        find_task(task_id).to_a2a_json
      end

      def get_task_details(task_id)
        find_task(task_id).task_details
      end

      def cancel_task(task_id, reason: nil)
        task = find_task(task_id)

        unless task.can_cancel?
          raise InvalidTaskError.new("Task cannot be cancelled in #{task.status} status")
        end

        task.cancel!(reason: reason)
        { task: task.to_a2a_json }
      end

      def provide_input(task_id, input_data)
        task = find_task(task_id)

        unless task.status == "input_required"
          raise InvalidTaskError.new("Task is not waiting for input", details: { status: task.status })
        end

        task.provide_input!(input_data)
        ::AiA2aTaskExecutionJob.perform_later(task.id)

        { task: task.to_a2a_json }
      end

      def get_task_events(task_id, since: nil, limit: 50)
        task = find_task(task_id)
        scope = task.events.chronological
        scope = scope.since(since) if since.present?

        {
          events: scope.limit(limit).map(&:to_a2a_json),
          task_status: task.a2a_status
        }
      end

      def get_artifact(task_id, artifact_id)
        task = find_task(task_id)
        artifact = task.artifacts.find { |a| a["id"] == artifact_id }
        raise A2aError.new("Artifact not found: #{artifact_id}", code: "ARTIFACT_NOT_FOUND") unless artifact
        artifact
      end

      # ==================== Task Execution ====================

      def execute_task_sync(task)
        task.start!

        begin
          result = execute_agent(task)
          task.complete!(result: result[:output], artifacts: result[:artifacts] || [])
        rescue StandardError => e
          # Only fail if task is not already in a terminal state
          unless task.terminal?
            task.fail!(
              error_message: e.message,
              error_code: e.class.name,
              error_details: { backtrace: e.backtrace&.first(5) }
            )
          end
          store_execution_memory(task, success: false, error: e.message)
          raise ExecutionError.new(e.message)
        end

        # Store success memory outside the try block to avoid state conflicts
        store_execution_memory(task, success: true)
        task
      end

      def wait_for_task(task, timeout: 300)
        deadline = Time.current + timeout

        loop do
          task.reload
          return task if task.terminal?

          if Time.current > deadline
            task.fail!(error_message: "Task timed out", error_code: "TIMEOUT")
            return task
          end

          sleep 0.5
        end
      end

      # ==================== Multi-Agent Coordination ====================

      def execute_sequence(tasks_config)
        results = []
        previous_output = nil

        tasks_config.each do |config|
          message = config[:message]
          message = merge_with_previous(message, previous_output) if previous_output.present? && config[:chain_output]

          task = submit_task(
            to_agent_card: config[:to_agent_card],
            message: message,
            from_agent: config[:from_agent],
            metadata: config[:metadata] || {},
            sync: true
          )

          results << task
          break if task.status == "failed"
          previous_output = task.output
        end

        results
      end

      def execute_parallel(tasks_config)
        tasks = tasks_config.map do |config|
          submit_task(
            to_agent_card: config[:to_agent_card],
            message: config[:message],
            from_agent: config[:from_agent],
            metadata: config[:metadata] || {}
          )
        end

        tasks.map { |task| wait_for_task(task) }
      end

      private

      def find_agent_card(identifier)
        card = Ai::AgentCard.for_discovery(@account.id).find_by(id: identifier)
        card ||= Ai::AgentCard.for_discovery(@account.id).find_by(name: identifier)
        raise AgentNotFoundError.new(identifier) unless card
        card
      end

      alias_method :resolve_agent_card, :find_agent_card

      def find_task(task_id)
        task = Ai::A2aTask.find_by(task_id: task_id, account_id: @account.id)
        task ||= Ai::A2aTask.find_by(id: task_id, account_id: @account.id)
        raise TaskNotFoundError.new(task_id) unless task
        task
      end

      def validate_message(message)
        return if message.blank?
        raise InvalidTaskError.new("Message must be an object") unless message.is_a?(Hash)

        return unless message[:parts].present?
        raise InvalidTaskError.new("Message parts must be an array") unless message[:parts].is_a?(Array)

        message[:parts].each_with_index do |part, index|
          raise InvalidTaskError.new("Message part #{index} must be an object") unless part.is_a?(Hash)

          part_type = part[:type] || part["type"]
          unless %w[text file data].include?(part_type)
            raise InvalidTaskError.new("Invalid part type at index #{index}: #{part_type}")
          end
        end
      end

      def normalize_message(message)
        return {} if message.blank?

        parts = message[:parts] || message["parts"] || [ message[:content] || message["content"] ].compact
        normalized_parts = parts.map do |part|
          part.is_a?(String) ? { "type" => "text", "text" => part } : part.deep_stringify_keys
        end

        {
          "role" => message[:role] || message["role"] || "user",
          "parts" => normalized_parts
        }
      end

      def extract_input(message)
        return {} if message.blank?

        if message.is_a?(String)
          { "text" => message }
        elsif message.is_a?(Hash)
          parts = message["parts"] || message[:parts] || []
          text = parts.select { |p| (p["type"] || p[:type]) == "text" }
                      .map { |p| p["text"] || p[:text] }
                      .join("\n")
          { "text" => text, "raw" => message }
        else
          { "raw" => message }
        end
      end

      def build_metadata(metadata)
        metadata.merge(
          "submitted_by_user_id" => @user&.id,
          "submitted_at" => Time.current.iso8601,
          "workflow_run_id" => @workflow_run&.run_id
        )
      end

      def merge_with_previous(message, previous_output)
        context = "Previous step output: #{previous_output.to_json.truncate(1000)}"

        if message.is_a?(String)
          "#{context}\n\n#{message}"
        elsif message.is_a?(Hash)
          parts = message["parts"] || message[:parts] || []
          parts.unshift({ "type" => "text", "text" => context })
          message.merge("parts" => parts)
        else
          { "parts" => [ { "type" => "text", "text" => context } ] }
        end
      end

      def execute_agent(task)
        agent = task.to_agent
        raise ExecutionError.new("No agent associated with task") unless agent

        execution_context = build_execution_context(task, agent)

        executor = Ai::McpAgentExecutor.new(
          agent: agent,
          account: @account
        )

        # Build input parameters for MCP executor
        # Extract text from message parts or use input directly
        input_text = extract_input_text(task)

        input_parameters = {
          "input" => input_text,
          "context" => execution_context
        }

        mcp_result = executor.execute(input_parameters)

        # Ensure mcp_result is a Hash before calling dig
        mcp_result = {} unless mcp_result.is_a?(Hash)

        # Extract output from MCP response format
        # MCP returns: { "result" => { "output" => "...", "metadata" => {...} }, "telemetry" => {...} }
        # Handle both success and error cases
        result_data = mcp_result["result"] || mcp_result[:result]
        output_text = if result_data.is_a?(Hash)
                        result_data["output"] || result_data[:output] || ""
                      elsif result_data.is_a?(String)
                        result_data
                      else
                        ""
                      end

        # Extract metadata safely
        metadata = if result_data.is_a?(Hash)
                     result_data["metadata"] || result_data[:metadata] || {}
                   else
                     {}
                   end

        # Return in format expected by execute_task_sync
        {
          output: { "text" => output_text, "raw" => mcp_result },
          artifacts: [],
          metadata: metadata,
          telemetry: mcp_result["telemetry"] || mcp_result[:telemetry] || {}
        }
      end

      def extract_input_text(task)
        # Try to extract text from message parts first
        if task.message.is_a?(Hash)
          parts = task.message["parts"] || task.message[:parts] || []
          text_parts = parts.select { |p| p["type"] == "text" || p[:type] == "text" }
          if text_parts.any?
            return text_parts.map { |p| p["text"] || p[:text] }.join("\n")
          end
        end

        # Fall back to input text field
        if task.input.is_a?(Hash)
          task.input["text"] || task.input[:text] || task.input.to_json
        else
          task.input.to_s
        end
      end

      def build_execution_context(task, agent)
        context = {
          task_id: task.task_id,
          workflow_run_id: @workflow_run&.run_id,
          history: task.history,
          from_agent: task.from_agent&.name
        }

        if agent.present?
          injector = Memory::ContextInjectorService.new(agent: agent, account: @account)
          context[:memories] = injector.build_context(task: task, token_budget: 2000)
        end

        context
      end

      def store_execution_memory(task, success:, error: nil)
        agent = task.to_agent
        return unless agent

        # Safely extract task_type from message parts
        task_type = if task.message.is_a?(Hash) && task.message["parts"].is_a?(Array)
                      task.message["parts"].first&.dig("type") || "unknown"
                    else
                      "unknown"
                    end

        # Safely extract input text
        input_text = if task.input.is_a?(Hash)
                       task.input["text"] || task.input[:text] || task.input.to_json
                     elsif task.input.is_a?(String)
                       task.input
                     else
                       task.input.to_s
                     end

        # Safely extract output
        output_json = task.output.is_a?(Hash) ? task.output.to_json : task.output.to_s

        Memory::ExperientialMemoryService.new(agent: agent, account: @account).store(
          content: {
            "task_type" => task_type,
            "input_summary" => input_text&.truncate(200),
            "output_summary" => output_json.truncate(200),
            "success" => success,
            "error" => error,
            "duration_ms" => task.duration_ms
          },
          context: {
            "task_id" => task.task_id,
            "workflow_run_id" => task.ai_workflow_run_id,
            "from_agent_id" => task.from_agent_id
          },
          outcome_success: success,
          importance: success ? 0.5 : 0.7
        )
      rescue StandardError => e
        Rails.logger.warn "Failed to store execution memory: #{e.message}"
      end
    end
  end
end
