# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        # Tool bridge controller for worker → server tool operations.
        #
        # LLM completion endpoints have been removed — the worker now calls
        # AI providers directly via its own LLM client. Only tool-related
        # endpoints remain, as tool definitions and execution live server-side.
        class LlmProxyController < InternalBaseController
          before_action :load_agent

          # POST /api/v1/internal/ai/llm/tool_definitions
          def tool_definitions
            bridge = ::Ai::AgentToolBridgeService.new(agent: @agent, account: @agent.account)
            definitions = bridge.tool_definitions_for_llm

            render_success(tools: definitions, tools_enabled: bridge.tools_enabled?)
          rescue StandardError => e
            render_error("Failed to fetch tool definitions: #{e.message}", status: :unprocessable_entity)
          end

          # POST /api/v1/internal/ai/llm/dispatch_tool
          def dispatch_tool
            bridge = ::Ai::AgentToolBridgeService.new(agent: @agent, account: @agent.account)
            tool_call = (params[:tool_call]&.to_unsafe_h || {}).deep_symbolize_keys

            result_json = bridge.dispatch_tool_call(tool_call)

            render_success(result: JSON.parse(result_json))
          rescue JSON::ParserError
            render_success(result: result_json)
          rescue StandardError => e
            render_error("Tool dispatch failed: #{e.message}", status: :unprocessable_entity)
          end

          # POST /api/v1/internal/ai/llm/execute_with_reasoning
          #
          # Reasoning orchestration is kept server-side because it involves
          # complex services (STAR reasoning, evaluation, reflection) that
          # are tightly coupled to the server's service layer.
          def execute_with_reasoning
            gate = enforce_execution_gate
            return if gate

            llm_client = build_llm_client
            model, opts = resolve_model_config
            messages = params_messages

            bridge = ::Ai::AgentToolBridgeService.new(agent: @agent, account: @agent.account)

            reasoning_mode = params[:reasoning_mode]&.to_sym
            reflection_enabled = params[:reflection_enabled] == true || params[:reflection_enabled] == "true"
            evaluation_config = params[:evaluation_config]&.to_unsafe_h

            result = bridge.execute_with_reasoning(
              llm_client: llm_client, messages: messages, model: model,
              reasoning_mode: reasoning_mode,
              reflection_enabled: reflection_enabled,
              evaluation_config: evaluation_config,
              **opts
            )

            render_success(
              content: result[:content],
              usage: result[:usage],
              tool_calls_log: result[:tool_calls_log],
              finish_reason: result[:finish_reason],
              reasoning: result[:reasoning],
              reflection: result[:reflection],
              evaluation: result[:evaluation]
            )
          rescue StandardError => e
            render_error("Reasoning execution failed: #{e.message}", status: :unprocessable_entity)
          end

          private

          # Pre-execution governance gate
          # Returns nil if execution should proceed, renders error otherwise
          def enforce_execution_gate
            gate_service = ::Ai::Autonomy::ExecutionGateService.new(account: @agent.account)
            gate_result = gate_service.check(agent: @agent, action_type: "execute")

            case gate_result[:decision]
            when :denied
              render_error("Execution denied: #{gate_result[:reason]}", status: :forbidden)
              return true
            when :requires_approval
              render_error(
                "Execution requires approval: #{gate_result[:reason]}",
                status: :accepted
              )
              return true
            end

            nil
          rescue StandardError => e
            Rails.logger.warn "[LlmProxy] Execution gate check failed (allowing): #{e.message}"
            nil
          end

          def load_agent
            @agent = ::Ai::Agent.find(params[:agent_id])
          rescue ActiveRecord::RecordNotFound
            render_error("Agent not found", status: :not_found)
          end

          def build_llm_client
            unless @agent.provider&.is_active?
              raise "AI provider is not active for agent: #{@agent.name}"
            end

            ::WorkerLlmClient.new(agent_id: @agent.id)
          end

          def resolve_model_config
            model_config = @agent.mcp_metadata&.dig("model_config") || {}
            model = params[:model] ||
                    model_config["model"] ||
                    @agent.mcp_tool_manifest&.dig("model") ||
                    @agent.provider.supported_models.first&.dig("id")

            max_tokens = params[:max_tokens] || model_config["max_tokens"] || 2000
            temperature = params[:temperature] || model_config["temperature"] || 0.7

            system_prompt = params[:system_prompt] ||
                            @agent.build_system_prompt_with_profile.presence ||
                            @agent.mcp_metadata&.dig("system_prompt")

            opts = { max_tokens: max_tokens.to_i, temperature: temperature.to_f,
                     system_prompt: system_prompt }.compact

            [model, opts]
          end

          def params_messages
            raw = params[:messages]
            return [] unless raw

            raw.map do |msg|
              m = msg.respond_to?(:to_unsafe_h) ? msg.to_unsafe_h : msg.to_h
              { role: m["role"] || m[:role], content: m["content"] || m[:content] }
            end
          end
        end
      end
    end
  end
end
