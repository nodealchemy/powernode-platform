# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # ExternalAgent - Executes tasks on external A2A-compliant agents
    # Enables multi-agent orchestration across platforms
    class ExternalAgent < Base
      protected

      def perform_execution
        external_agent = fetch_external_agent
        skill_id = configuration["skill_id"]
        input = build_input

        log_info("Sending task to external agent: #{external_agent.name}, skill: #{skill_id}")

        # Create A2A client and send task
        client = A2a::Client::TaskClient.new(external_agent)

        if configuration["stream"]
          result = execute_streaming(client, skill_id, input)
        else
          result = execute_sync(client, skill_id, input, external_agent)
        end

        build_output(result, external_agent)
      end

      private

      def fetch_external_agent
        agent_id = configuration["external_agent_id"]
        agent_url = configuration["agent_card_url"]

        external_agent = if agent_id.present?
                           ExternalAgent.find_by(id: agent_id, account_id: account.id)
                         elsif agent_url.present?
                           find_or_create_agent_by_url(agent_url)
                         end

        unless external_agent
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "External agent not found: #{agent_id || agent_url}"
        end

        unless external_agent.status == "active"
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "External agent is not active: #{external_agent.name}"
        end

        external_agent
      end

      def find_or_create_agent_by_url(url)
        agent = ExternalAgent.find_by(agent_card_url: url, account_id: account.id)
        return agent if agent

        # Discover and create the agent
        result = A2a::Client::AgentDiscovery.fetch_card(url)
        return nil unless result[:success]

        card = result[:card]
        ExternalAgent.create!(
          account_id: account.id,
          name: card["name"],
          description: card["description"],
          agent_card_url: url,
          cached_card: card,
          card_cached_at: Time.current,
          skills: card["skills"] || [],
          capabilities: card["capabilities"] || {}
        )
      end

      def build_input
        input = {}

        # Add static input from configuration
        if configuration["static_input"].present?
          input.merge!(configuration["static_input"].deep_dup)
        end

        # Apply input mapping from workflow variables
        if configuration["input_mapping"].present?
          configuration["input_mapping"].each do |agent_key, workflow_path|
            value = resolve_workflow_value(workflow_path)
            input[agent_key] = value if value.present?
          end
        end

        # Add previous node output if configured
        if configuration["include_previous_output"] && previous_results.present?
          input["context"] ||= {}
          input["context"]["previous_output"] = previous_results
        end

        # Add text prompt if configured
        if configuration["prompt_template"].present?
          input["text"] = render_template(configuration["prompt_template"])
        end

        input
      end

      def execute_sync(client, skill_id, input, external_agent)
        result = client.send_message(
          skill: skill_id,
          input: input,
          metadata: build_task_metadata
        )

        unless result[:success]
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "External agent task failed: #{result[:error]}"
        end

        task = result[:task]

        # If task is not immediately completed, wait for it
        status = task["status"] || task.dig("state", "status")
        unless %w[completed failed canceled].include?(status)
          timeout = configuration["timeout"] || 300
          wait_result = client.wait_for_task(task["id"] || task["taskId"], timeout: timeout)

          unless wait_result[:success] && wait_result[:completed]
            raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                  "External agent task timed out or failed"
          end

          task = wait_result[:task]
        end

        {
          task: task,
          output: extract_task_output(task),
          artifacts: task["artifacts"] || []
        }
      end

      def execute_streaming(client, skill_id, input)
        events = []
        final_task = nil

        client.stream_message(skill: skill_id, input: input) do |event|
          events << event
          log_debug("Stream event: #{event[:type]}")

          if event[:type] == "task.complete" || event[:type] == "task.failed"
            final_task = event[:data]
          end
        end

        unless final_task
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "External agent stream did not complete"
        end

        {
          task: final_task,
          output: extract_task_output(final_task),
          artifacts: final_task["artifacts"] || [],
          events: events
        }
      end

      def extract_task_output(task)
        # Try various output locations
        task["output"] ||
          task.dig("result", "output") ||
          task["artifacts"]&.first&.dig("parts", 0, "text") ||
          task["message"]&.dig("parts", 0, "text") ||
          {}
      end

      def build_task_metadata
        {
          workflow_run_id: @orchestrator.workflow_run.run_id,
          node_id: node.id,
          node_type: node.node_type,
          source: "powernode"
        }
      end

      def build_output(result, external_agent)
        output = result[:output]

        # Apply output mapping if configured
        if configuration["output_mapping"].present?
          configuration["output_mapping"].each do |workflow_var, agent_path|
            value = output.dig(*agent_path.split("."))
            set_variable(workflow_var, value) if value.present?
          end
        end

        # Store in configured output variable
        if configuration["output_variable"].present?
          set_variable(configuration["output_variable"], output)
        end

        {
          output: output,
          data: {
            external_agent_id: external_agent.id,
            external_agent_name: external_agent.name,
            task_id: result[:task]["id"] || result[:task]["taskId"],
            artifacts_count: result[:artifacts]&.size || 0,
            execution_successful: true
          },
          result: output,
          metadata: {
            node_id: node.id,
            node_type: node.node_type,
            external_agent: external_agent.name,
            skill_id: configuration["skill_id"],
            executed_at: Time.current.iso8601
          },
          artifacts: result[:artifacts]
        }
      end

      def resolve_workflow_value(path)
        parts = path.to_s.split(".")
        return get_variable(path) if parts.size == 1

        # Handle nested paths like "previous.output.data"
        result = case parts.first
                 when "previous"
                   previous_results&.dig(*parts[1..].map(&:to_s))
                 when "input"
                   input_data&.dig(*parts[1..].map(&:to_s))
                 else
                   get_variable(parts.first)&.dig(*parts[1..].map(&:to_s))
                 end

        result
      end

      def render_template(template)
        return template unless template.include?("{{")

        template.gsub(/\{\{(\w+(?:\.\w+)*)\}\}/) do |match|
          var_path = Regexp.last_match(1)
          value = resolve_workflow_value(var_path)
          value.to_s
        end
      end

      def account
        @orchestrator.workflow_run.account
      end
    end
  end
end
