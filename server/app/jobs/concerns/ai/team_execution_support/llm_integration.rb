# frozen_string_literal: true

module Ai
  module TeamExecutionSupport
    module LlmIntegration
      extend ActiveSupport::Concern

      private

      def call_agent_llm(agent, messages, purpose: "general")
        provider = agent.provider
        credential = provider&.provider_credentials&.active
                            &.where(account_id: @team&.account_id)&.first
        credential ||= provider&.provider_credentials&.active&.first

        unless credential
          log_execution("[LlmIntegration] No active credential for agent #{agent.name} (provider: #{provider&.name})")
          return nil
        end

        model = resolve_model_for_agent(agent)

        log_execution("[LlmIntegration] Calling LLM for #{agent.name} (#{purpose}) with model #{model}")

        start_time = Time.current
        client = Ai::ProviderClientService.new(credential)
        result = client.send_message(messages, model: model, max_tokens: 4096, temperature: 0.7)

        duration = Time.current - start_time

        unless result[:success]
          log_execution("[LlmIntegration] LLM call unsuccessful for #{agent.name} (#{purpose}): #{result[:error]}")
          return nil
        end

        response = result[:response] || {}
        usage = result.dig(:metadata, :usage) || {}
        tokens_used = usage[:total_tokens] || 0
        cost = calculate_cost(provider, model, usage)

        track_llm_call(agent, purpose, tokens_used, cost, duration)

        # Track tokens/cost on the execution
        @execution&.add_tokens!(tokens_used) if tokens_used.positive?
        @execution&.add_cost!(cost) if cost.positive?

        extract_llm_response_text(response)
      rescue StandardError => e
        log_execution("[LlmIntegration] LLM call failed for #{agent.name} (#{purpose}): #{e.message}")
        nil
      end

      def generate_work_plan(lead_agent, workers, input)
        worker_descriptions = workers.map do |member|
          agent = member.agent
          "- #{agent.name} (role: #{member.role}): #{agent.system_prompt&.truncate(200)}"
        end.join("\n")

        task_description = input.is_a?(Hash) ? (input[:task] || input["task"] || input.to_json) : input.to_s

        messages = [
          {
            role: "system",
            content: "You are a team lead planning work distribution. Respond ONLY with valid JSON."
          },
          {
            role: "user",
            content: <<~PROMPT
              Plan the following task for your team. Assign specific, actionable instructions to each worker.

              TASK: #{task_description}

              AVAILABLE WORKERS:
              #{worker_descriptions}

              Respond with JSON in this exact format:
              {
                "plan_summary": "Brief description of overall approach",
                "assignments": [
                  {
                    "worker_name": "Exact agent name",
                    "instructions": "Specific task instructions for this worker",
                    "priority": "high|medium|low",
                    "expected_output": "What this worker should produce"
                  }
                ],
                "synthesis_notes": "How to combine worker outputs into final result"
              }
            PROMPT
          }
        ]

        response_text = call_agent_llm(lead_agent, messages, purpose: "planning")
        return nil unless response_text

        parse_work_plan(response_text, workers)
      rescue StandardError => e
        log_execution("[LlmIntegration] Work plan generation failed: #{e.message}")
        nil
      end

      def parse_work_plan(response_text, workers)
        # Extract JSON from response (may be wrapped in markdown code blocks)
        json_text = response_text.match(/\{[\s\S]*\}/)&.to_s
        return nil unless json_text

        plan = JSON.parse(json_text)
        worker_map = workers.index_by { |m| m.agent.name }

        # Validate and map assignments to actual workers
        assignments = (plan["assignments"] || []).filter_map do |assignment|
          worker_name = assignment["worker_name"]
          member = worker_map[worker_name] || workers.find { |m| m.agent.name.include?(worker_name) || worker_name.include?(m.agent.name) }
          next unless member

          assignment.merge("member" => member, "agent_id" => member.agent.id)
        end

        {
          "plan_summary" => plan["plan_summary"],
          "assignments" => assignments,
          "synthesis_notes" => plan["synthesis_notes"]
        }
      rescue JSON::ParserError => e
        log_execution("[LlmIntegration] Failed to parse work plan JSON: #{e.message}")
        nil
      end

      def synthesize_results(lead_agent, worker_results, original_input)
        results_text = worker_results.map do |result|
          output_text = result[:output].is_a?(Hash) ? (result[:output][:response] || result[:output].to_json) : result[:output].to_s
          "## #{result[:agent_name]} (#{result[:role]})\n#{output_text.truncate(3000)}"
        end.join("\n\n---\n\n")

        task_description = original_input.is_a?(Hash) ? (original_input[:task] || original_input["task"] || original_input.to_json) : original_input.to_s

        messages = [
          {
            role: "system",
            content: "You are a team lead synthesizing your team's work outputs into a coherent final deliverable."
          },
          {
            role: "user",
            content: <<~PROMPT
              Original task: #{task_description}

              Your team produced the following outputs:

              #{results_text}

              Synthesize these outputs into a single, coherent, comprehensive response that addresses the original task.
              Resolve any conflicts between worker outputs. Ensure completeness and quality.
            PROMPT
          }
        ]

        call_agent_llm(lead_agent, messages, purpose: "synthesis")
      end

      def resolve_model_for_agent(agent)
        # Check for task-specific model override
        task_type = @input.is_a?(Hash) ? (@input[:task_type] || @input["task_type"]) : nil
        if task_type.present?
          override = agent.mcp_metadata&.dig("task_model_overrides", task_type)
          if override.present?
            log_execution("[LlmIntegration] Using task override model '#{override}' for #{agent.name} (task_type: #{task_type})")
            return override
          end
        end

        # Fall back to agent's configured model
        agent.model || agent.mcp_tool_manifest&.dig("model") || agent.provider&.supported_models&.first&.dig("id") || "default"
      end

      def track_llm_call(agent, purpose, tokens, cost, duration)
        @execution_tokens = (@execution_tokens || 0) + tokens
        @execution_cost = (@execution_cost || 0.0) + cost

        log_execution("[LlmIntegration] #{agent.name}/#{purpose}: #{tokens} tokens, $#{'%.4f' % cost}, #{duration.round(2)}s")
      end

      def extract_llm_response_text(response)
        return response.to_s unless response.is_a?(Hash)

        # OpenAI format: { choices: [{ message: { content: "..." } }] }
        text = response.dig(:choices, 0, :message, :content)
        return text if text.is_a?(String)

        # Anthropic format: { content: [{ type: "text", text: "..." }] }
        content = response[:content]
        if content.is_a?(Array)
          texts = content.select { |c| c[:type] == "text" }.map { |c| c[:text] }
          return texts.join("\n") if texts.any?
        end

        return content if content.is_a?(String)

        response[:text] || response.to_s
      end

      def calculate_cost(provider, model, usage)
        model_info = provider.supported_models&.find { |m| m["id"] == model || m["name"] == model }
        return 0.0 unless model_info

        input_cost = (usage[:prompt_tokens] || usage[:input_tokens] || 0) * (model_info.dig("cost_per_1k_tokens", "input") || 0) / 1000.0
        output_cost = (usage[:completion_tokens] || usage[:output_tokens] || 0) * (model_info.dig("cost_per_1k_tokens", "output") || 0) / 1000.0
        input_cost + output_cost
      end
    end
  end
end
