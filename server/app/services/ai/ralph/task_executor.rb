# frozen_string_literal: true

module Ai
  module Ralph
    # TaskExecutor - Polymorphic task execution service
    #
    # Routes Ralph tasks to various executor types:
    # - agent: Internal AI agent execution
    # - workflow: Multi-step workflow execution
    # - pipeline: CI/CD pipeline execution
    # - a2a_task: A2A protocol delegation
    # - container: Sandboxed container execution
    # - human: Human review queue
    # - community: Community agent invocation
    #
    class TaskExecutor
      attr_reader :task, :ralph_loop, :account

      def initialize(task:, ralph_loop: nil)
        @task = task
        @ralph_loop = ralph_loop || task.ralph_loop
        @account = @ralph_loop.account
      end

      # Execute the task using the appropriate executor
      def execute
        executor = resolve_executor
        return fallback_execution if executor.nil?

        # Record execution attempt
        task.record_execution_attempt!(executor)

        # Route to appropriate execution method
        result = case task.execution_type
        when "agent"
                   execute_via_agent(executor)
        when "workflow"
                   execute_via_workflow(executor)
        when "pipeline"
                   execute_via_pipeline(executor)
        when "a2a_task"
                   execute_via_a2a(executor)
        when "container"
                   execute_via_container(executor)
        when "human"
                   queue_for_human_review(executor)
        when "community"
                   execute_via_community_agent(executor)
        else
                   { success: false, error: "Unknown execution type: #{task.execution_type}" }
        end

        # Update task with executor if successful
        task.update!(executor: executor) if result[:success] && executor

        result
      rescue StandardError => e
        Rails.logger.error("TaskExecutor failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
        { success: false, error: "Execution failed: #{e.message}" }
      end

      private

      # Resolve the executor to use
      def resolve_executor
        return task.executor if task.executor.present?

        executor = task.find_matching_executor
        return executor if executor

        default = ralph_loop.default_agent
        return default if default

        nil
      end

      MAX_TOOL_CALLS = 5

      # Execute task via AI agent with MCP tool-calling loop
      def execute_via_agent(agent)
        provider = agent.provider
        credential = provider.provider_credentials.active.first
        raise "No active credentials for provider #{provider.name}" unless credential

        client = Ai::ProviderClientService.new(credential)
        messages = build_agent_messages(agent)
        options = build_agent_options(agent, provider)

        # MCP tool-calling loop
        mcp_tools = ralph_loop.available_mcp_tools
        if mcp_tools.any?
          options[:functions] = mcp_tools.map { |t| mcp_tool_definition(t) }
        end

        result = execute_with_tool_calls(client, messages, options, mcp_tools)
        normalize_result(result, agent)
      rescue StandardError => e
        Rails.logger.error("Agent execution failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        { success: false, error: e.message, executor_type: "agent", executor_id: agent.id }
      end

      # Execute task via workflow
      def execute_via_workflow(workflow)
        run = workflow.runs.create!(
          account: account,
          triggered_by: ralph_loop.created_by || account.users.first,
          status: "pending",
          input_data: {
            ralph_task_id: task.id,
            ralph_task_key: task.task_key,
            task_details: task.task_details
          }
        )

        # Execute workflow asynchronously
        ::Ai::WorkflowExecutionJob.perform_later(run.id)

        {
          success: true,
          workflow_run_id: run.id,
          message: "Workflow execution queued",
          executor_type: "workflow",
          executor_id: workflow.id
        }
      rescue StandardError => e
        { success: false, error: "Workflow execution error: #{e.message}" }
      end

      # Execute task via DevOps pipeline
      def execute_via_pipeline(pipeline)
        execution = Devops::PipelineExecution.create!(
          pipeline: pipeline,
          account: account,
          triggered_by: ralph_loop.created_by || account.users.first,
          status: "pending",
          parameters: {
            ralph_task_id: task.id,
            ralph_task_key: task.task_key
          }
        )

        # Execute pipeline asynchronously
        Devops::PipelineExecutionJob.perform_later(execution.id)

        {
          success: true,
          pipeline_execution_id: execution.id,
          message: "Pipeline execution queued",
          executor_type: "pipeline",
          executor_id: pipeline.id
        }
      rescue StandardError => e
        { success: false, error: "Pipeline execution error: #{e.message}" }
      end

      # Execute task via A2A protocol
      def execute_via_a2a(agent_or_card)
        agent = agent_or_card.is_a?(Ai::AgentCard) ? agent_or_card.agent : agent_or_card

        a2a_service = ::Ai::A2a::Service.new(account: account)

        result = a2a_service.submit_task(
          agent: agent,
          task: {
            input: {
              ralph_task_id: task.id,
              ralph_task_key: task.task_key,
              task_details: task.task_details
            },
            skill: "ralph.execute_task"
          }
        )

        if result[:success]
          {
            success: true,
            a2a_task_id: result[:task]&.id,
            message: "A2A task submitted",
            executor_type: "a2a_task",
            executor_id: agent.id
          }
        else
          { success: false, error: result[:error] || "A2A task submission failed" }
        end
      rescue StandardError => e
        { success: false, error: "A2A execution error: #{e.message}" }
      end

      # Execute task via container
      def execute_via_container(template)
        orchestration = ::Devops::ContainerOrchestrationService.new(
          account: account,
          template: template
        )

        timeout = task.execution_timeout

        result = orchestration.execute(
          input: {
            ralph_task_id: task.id,
            ralph_task_key: task.task_key,
            task_details: task.task_details,
            prompt: build_prompt
          },
          timeout: timeout
        )

        if result[:success]
          {
            success: true,
            container_instance_id: result[:instance]&.id,
            message: "Container execution started",
            executor_type: "container",
            executor_id: template.id
          }
        else
          { success: false, error: result[:error] || "Container execution failed" }
        end
      rescue StandardError => e
        { success: false, error: "Container execution error: #{e.message}" }
      end

      # Queue task for human review
      def queue_for_human_review(user)
        # Create notification/assignment for human review
        notification = Notification.create!(
          account: account,
          user: user,
          notification_type: "ralph_task_review",
          title: "Task Review Required: #{task.task_key}",
          body: "Please review and complete task: #{task.description&.truncate(200)}",
          data: {
            ralph_task_id: task.id,
            ralph_loop_id: ralph_loop.id,
            task_key: task.task_key
          },
          read: false
        )

        # Update task status to indicate awaiting review
        task.update!(
          status: "blocked",
          error_message: "Awaiting human review"
        )

        {
          success: true,
          notification_id: notification.id,
          message: "Task queued for human review",
          executor_type: "human",
          executor_id: user.id
        }
      rescue StandardError => e
        { success: false, error: "Human review queue error: #{e.message}" }
      end

      # Execute task via community agent
      def execute_via_community_agent(community_agent)
        a2a_service = ::Ai::A2a::Service.new(account: account)

        result = a2a_service.submit_external_task(
          endpoint: community_agent.endpoint_url,
          task: {
            input: {
              ralph_task_id: task.id,
              ralph_task_key: task.task_key,
              task_details: task.task_details
            },
            skill: "execute_task"
          },
          authentication: {
            type: "bearer",
            token: community_agent.api_token
          }
        )

        if result[:success]
          # Increment community agent task count
          community_agent.increment!(:task_count)

          {
            success: true,
            a2a_task_id: result[:task]&.id,
            community_agent_id: community_agent.id,
            message: "Community agent task submitted",
            executor_type: "community",
            executor_id: community_agent.id
          }
        else
          { success: false, error: result[:error] || "Community agent execution failed" }
        end
      rescue StandardError => e
        { success: false, error: "Community agent execution error: #{e.message}" }
      end

      # Handle fallback execution
      def fallback_execution
        return no_executor_error unless task.has_fallback?

        fallback = task.fallback_config
        Rails.logger.info("TaskExecutor: Falling back to #{fallback[:executor_type]}")

        task.update!(
          execution_type: fallback[:executor_type],
          executor_id: fallback[:executor_id]
        )

        execute
      end

      def no_executor_error
        {
          success: false,
          error: "No executor found. Set a default agent on the loop or configure task executors.",
          task_id: task.id,
          execution_type: task.execution_type
        }
      end

      # Build the prompt for AI execution
      def build_prompt
        <<~PROMPT
          ## Task: #{task.task_key}

          #{task.description}

          ### Acceptance Criteria
          #{task.acceptance_criteria || "Complete the task as described."}

          ### Context
          - Ralph Loop: #{ralph_loop.name}
          - Iteration: #{ralph_loop.current_iteration + 1}
          - Repository: #{ralph_loop.repository_url || "Not specified"}
          - Branch: #{ralph_loop.branch}

          ### Previous Learnings
          #{format_learnings}

          ### Instructions
          Complete this task according to the acceptance criteria.
          Provide clear output showing what was done.
          Extract any learnings that could help future iterations.
        PROMPT
      end

      # Format recent learnings for prompt
      def format_learnings
        learnings = ralph_loop.recent_learnings(limit: 5)
        return "No previous learnings" if learnings.blank?

        learnings.map { |l| "- #{l['text']}" }.join("\n")
      end

      # ==================== Agent + MCP Helpers ====================

      def build_agent_messages(agent)
        system_prompt = agent.mcp_metadata&.dig("ollama_config", "system_prompt") ||
                        agent.mcp_metadata&.dig("system_prompt") ||
                        default_system_prompt

        [
          { role: "system", content: system_prompt },
          { role: "user", content: build_prompt }
        ]
      end

      def build_agent_options(agent, provider)
        model_config = agent.mcp_metadata&.dig("ollama_config") || agent.mcp_metadata || {}
        {
          model: model_config["model"] || provider.default_model,
          max_tokens: model_config["max_tokens"] || 4096,
          temperature: model_config["temperature"] || 0.7
        }
      end

      def default_system_prompt
        <<~SYSTEM
          You are an AI assistant helping with software development tasks.
          You are part of a Ralph Loop - an iterative development cycle.

          Current loop: #{ralph_loop.name}
          Repository: #{ralph_loop.repository_url || "Not specified"}
          Branch: #{ralph_loop.branch || "main"}
          Iteration: #{ralph_loop.current_iteration + 1} of #{ralph_loop.max_iterations}

          Instructions:
          1. Complete the task according to the acceptance criteria
          2. Provide clear, actionable output
          3. If you learn something useful for future iterations, include it with "Learning:" prefix
          4. Be concise but thorough
        SYSTEM
      end

      def execute_with_tool_calls(client, messages, options, mcp_tools)
        MAX_TOOL_CALLS.times do
          result = client.send_message(messages, options)
          return result unless has_tool_call?(result)

          tool_call = extract_tool_call(result)
          mcp_tool = mcp_tools.find { |t| t.name == tool_call[:name] }
          raise "Unknown tool: #{tool_call[:name]}" unless mcp_tool

          tool_result = Mcp::SyncExecutionService.new(
            server: mcp_tool.mcp_server,
            tool: mcp_tool,
            parameters: tool_call[:arguments],
            user: nil,
            account: account
          ).execute

          messages << { role: "assistant", content: nil, function_call: tool_call }
          messages << { role: "function", name: tool_call[:name], content: tool_result.to_json }
        end

        # Final call without tools after max tool calls
        client.send_message(messages, options.except(:functions))
      end

      def normalize_result(result, agent)
        unless result[:success]
          return { success: false, error: result[:error], error_code: result[:error_type] }
        end

        {
          success: true,
          output: extract_content(result[:response]),
          checks_passed: true,
          commit_sha: nil,
          tokens: {
            input: result.dig(:metadata, :prompt_tokens) || result.dig(:metadata, :tokens_used) || 0,
            output: result.dig(:metadata, :completion_tokens) || 0
          },
          cost: result.dig(:metadata, :cost) || 0,
          executor_type: "agent",
          executor_id: agent.id
        }
      end

      def mcp_tool_definition(tool)
        {
          name: tool.name,
          description: tool.description || tool.name,
          parameters: tool.input_schema || {}
        }
      end

      def has_tool_call?(result)
        return false unless result[:success] && result[:response].is_a?(Hash)

        response = result[:response]
        response[:function_call].present? ||
          response.dig(:choices, 0, :message, :function_call).present? ||
          response.dig(:choices, 0, :message, :tool_calls).present?
      end

      def extract_tool_call(result)
        response = result[:response]

        fc = response[:function_call] ||
             response.dig(:choices, 0, :message, :function_call) ||
             response.dig(:choices, 0, :message, :tool_calls, 0, :function)

        return { name: fc[:name], arguments: fc[:arguments] } if fc

        raise "Could not extract tool call from response"
      end

      def extract_content(response)
        return "" unless response.is_a?(Hash)

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
    end
  end
end
