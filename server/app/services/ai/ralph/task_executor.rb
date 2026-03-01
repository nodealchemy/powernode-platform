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
      include Ai::Concerns::PromptTemplateLookup

      SYSTEM_PROMPT_SLUG = "ai-ralph-executor-default"
      FALLBACK_SYSTEM_PROMPT = <<~LIQUID
        You are an AI assistant helping with software development tasks.
        You are part of a Ralph Loop - an iterative development cycle.

        Current loop: {{ loop_name }}
        Repository: {{ repository_url }}
        Branch: {{ branch }}
        Iteration: {{ current_iteration }} of {{ max_iterations }}

        Instructions:
        1. Complete the task according to the acceptance criteria
        2. Provide clear, actionable output
        3. If you learn something useful for future iterations, include it with "Learning:" prefix
        4. Be concise but thorough
      LIQUID

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
      # Priority: explicit executor > loop default_agent > capability match > nil
      def resolve_executor
        return task.executor if task.executor.present?

        # Prefer the loop's configured default agent over arbitrary capability match
        default = ralph_loop.default_agent
        return default if default

        executor = task.find_matching_executor
        return executor if executor

        nil
      end

      # Execute task via AI agent with agentic tool-calling loop
      def execute_via_agent(agent)
        provider = agent.provider
        credential = provider.provider_credentials.active.first
        raise "No active credentials for provider #{provider.name}" unless credential

        client = WorkerLlmClient.new(agent_id: agent.id)
        provider_type = provider.provider_type
        messages = build_agent_messages(agent)
        options = build_agent_options(agent, provider)

        # Initialize git tool executor if repository is available
        git_executor = nil
        if GitToolExecutor.available?(ralph_loop)
          git_executor = GitToolExecutor.new(ralph_loop: ralph_loop)
          git_tools = GitToolDefinitions.for_provider(provider_type)
          options[:tools] = (options[:tools] || []) + git_tools
        end

        # Add MCP tools
        mcp_tools = ralph_loop.available_mcp_tools
        if mcp_tools.any?
          mcp_defs = mcp_tools.map { |t| mcp_tool_definition_for_provider(t, provider_type) }
          options[:tools] = (options[:tools] || []) + mcp_defs
        end

        # Run agentic loop
        loop_runner = AgenticLoop.new(
          client: client,
          provider_type: provider_type,
          account: account,
          git_tool_executor: git_executor,
          mcp_tools: mcp_tools
        )

        result = loop_runner.execute(messages, options)
        normalize_result(result, agent)
      rescue StandardError => e
        Rails.logger.error("Agent execution failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        { success: false, error: e.message, executor_type: "agent", executor_id: agent.id }
      end

      # Execute task via workflow
      def execute_via_workflow(workflow)
        run = workflow.runs.create!(
          account: account,
          triggered_by_user: ralph_loop.created_by || account.users.first,
          status: "pending",
          input_data: {
            ralph_task_id: task.id,
            ralph_task_key: task.task_key,
            task_details: task.task_details
          }
        )

        # Dispatch workflow execution to worker
        WorkerJobService.enqueue_ai_workflow_execution(run.id)

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
          triggered_by_user: ralph_loop.created_by || account.users.first,
          status: "pending",
          parameters: {
            ralph_task_id: task.id,
            ralph_task_key: task.task_key
          }
        )

        # Execute pipeline asynchronously via worker
        WorkerJobService.enqueue_job(
          "Devops::PipelineExecutionJob",
          args: [execution.id],
          queue: "devops_default"
        )

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
          user: ralph_loop.created_by || account.users.first
        )

        timeout = task.execution_timeout

        # Use worktree path as working directory if task has an associated worktree
        working_dir = resolve_worktree_path

        input = {
          ralph_task_id: task.id,
          ralph_task_key: task.task_key,
          task_details: task.task_details,
          prompt: build_prompt
        }
        input[:working_directory] = working_dir if working_dir

        instance = orchestration.execute(
          template: template,
          input_parameters: input,
          timeout_seconds: timeout
        )

        {
          success: true,
          container_instance_id: instance.id,
          message: "Container execution started",
          executor_type: "container",
          executor_id: template.id
        }
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
        prompt = <<~PROMPT
          ## Task: #{task.task_key}

          #{task.description}

          ### Acceptance Criteria
          #{task.acceptance_criteria || "Complete the task as described."}

          ### Context
          - Ralph Loop: #{ralph_loop.name}
          - Iteration: #{ralph_loop.current_iteration + 1}
          - Repository: #{ralph_loop.repository_url || "Not specified"}
          - Branch: #{ralph_loop.branch}
        PROMPT

        # Add mission objective context if available
        if ralph_loop.mission&.objective.present?
          prompt += <<~MISSION

            ### Mission Objective
            #{ralph_loop.mission.objective}
          MISSION
        end

        prompt += <<~REST

          ### Previous Learnings
          #{format_learnings}

          ### Instructions
          Complete this task according to the acceptance criteria.
          Provide clear output showing what was done.
          Extract any learnings that could help future iterations.
        REST

        prompt
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
        metadata = agent.mcp_metadata || {}
        model_config = metadata.dig("ollama_config") || metadata.dig("model_config") || metadata
        {
          model: model_config["model"] || provider.default_model,
          max_tokens: model_config["max_tokens"] || 4096,
          temperature: model_config["temperature"] || 0.7
        }
      end

      def default_system_prompt
        base = resolve_prompt_template(
          SYSTEM_PROMPT_SLUG,
          account: account,
          variables: {
            loop_name: ralph_loop.name,
            repository_url: ralph_loop.repository_url || "Not specified",
            branch: ralph_loop.branch || "main",
            current_iteration: (ralph_loop.current_iteration + 1).to_s,
            max_iterations: ralph_loop.max_iterations.to_s
          },
          fallback: FALLBACK_SYSTEM_PROMPT
        ) || ""

        # Inject repository context from mission analysis
        base += build_repo_context

        # Inject PRD task overview
        base += build_prd_context

        if GitToolExecutor.available?(ralph_loop)
          base += <<~GIT_INSTRUCTIONS

            Git Tool Usage:
            You have access to git tools that operate directly on the repository. Follow this workflow:
            1. Start by exploring the repo: use `get_repo_info` and `list_files` to understand structure
            2. Read existing files before modifying: use `read_file` to understand current code
            3. Write complete files: use `write_file` with the ENTIRE file content (not diffs)
            4. Use meaningful commit messages that describe the change clearly
            5. Use `search_code` to find relevant patterns and existing implementations
            6. After making changes, verify with `read_file` if needed
          GIT_INSTRUCTIONS
        end

        base
      end

      def build_repo_context
        analysis = ralph_loop.mission&.analysis_result
        return "" if analysis.blank?

        context = "\n"

        # Tech stack
        if analysis["tech_stack"].present?
          tech = analysis["tech_stack"]
          context += "Tech Stack:\n"
          context += "  Dependencies: #{Array(tech['dependencies']).first(15).join(', ')}\n" if tech["dependencies"]
          context += "  Dev deps: #{Array(tech['dev_dependencies']).first(10).join(', ')}\n" if tech["dev_dependencies"]
        end

        # File tree
        if analysis.dig("structure", "entries").present?
          entries = analysis["structure"]["entries"]
          context += "\nRepository Structure:\n"
          entries.first(30).each do |entry|
            prefix = entry["type"] == "tree" ? "[dir]" : "[file]"
            context += "  #{prefix} #{entry['path']}\n"
          end
        end

        context
      end

      def build_prd_context
        prd = ralph_loop.prd_json
        return "" if prd.blank? || prd["tasks"].blank?

        tasks = prd["tasks"]
        completed_keys = ralph_loop.ralph_tasks.where(status: "passed").pluck(:task_key)

        context = "\nPRD Task Overview:\n"
        tasks.each do |t|
          key = t["key"] || t["task_key"]
          status_marker = completed_keys.include?(key) ? "[DONE]" : "[TODO]"
          context += "  #{status_marker} #{key}: #{t['name'] || t['description']}\n"
        end

        context
      end

      def normalize_result(result, agent)
        unless result[:success]
          return { success: false, error: result[:error], error_code: result[:error_type] }
        end

        output = result[:content] || extract_content(result[:response])

        {
          success: true,
          output: output,
          checks_passed: true,
          commit_sha: result[:last_commit_sha],
          file_changes: result[:file_changes] || [],
          tokens: {
            input: result.dig(:metadata, :usage, :prompt_tokens) || result.dig(:metadata, :tokens_used) || 0,
            output: result.dig(:metadata, :usage, :completion_tokens) || 0
          },
          cost: result.dig(:metadata, :cost) || 0,
          executor_type: "agent",
          executor_id: agent.id
        }
      end

      def mcp_tool_definition_for_provider(tool, provider_type)
        case provider_type
        when "anthropic"
          {
            name: tool.name,
            description: tool.description || tool.name,
            input_schema: tool.input_schema || { type: "object", properties: {}, required: [] }
          }
        else
          {
            type: "function",
            function: {
              name: tool.name,
              description: tool.description || tool.name,
              parameters: tool.input_schema || { type: "object", properties: {}, required: [] }
            }
          }
        end
      end

      def resolve_worktree_path
        worktree = ::Ai::Worktree.find_by(assignee: task, status: %w[ready in_use])
        worktree&.worktree_path
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
