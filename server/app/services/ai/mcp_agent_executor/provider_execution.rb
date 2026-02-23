# frozen_string_literal: true

class Ai::McpAgentExecutor
  # Provider execution via Ai::Llm::Client with optional tool-calling loop.
  #
  # Replaces the legacy ProviderClientService path with the unified
  # Ai::Llm::Client adapter. When tools are enabled (default for all agent
  # types except mcp_client), execution runs through AgentToolBridgeService's
  # shared agentic loop.
  #
  module ProviderExecution
    extend ActiveSupport::Concern

    private

    def execute_with_provider(_provider_client, execution_context)
      @logger.info "[MCP_AGENT_EXECUTOR] Executing with provider #{@agent.provider.provider_type}"

      llm_client = build_llm_client
      messages = build_messages_for_llm(execution_context)
      model, opts = resolve_model_config(execution_context)

      tool_bridge = Ai::AgentToolBridgeService.new(agent: @agent, account: @account)

      if tool_bridge.tools_enabled? && tool_bridge.tool_definitions_for_llm.any?
        result = tool_bridge.execute_tool_loop(
          llm_client: llm_client, messages: messages, model: model, **opts
        )
        format_tool_loop_result(result, model)
      else
        response = llm_client.complete(messages: messages, model: model, **opts)
        unless response.success?
          raise ProviderError, "Provider returned no content (finish_reason: #{response.finish_reason})"
        end
        format_simple_result(response, model)
      end
    end

    # Build an Ai::Llm::Client from the agent's provider and active credential
    def build_llm_client
      provider = @agent.provider
      credential = provider.provider_credentials
                           .where(account: @account)
                           .active
                           .first

      unless credential
        raise ProviderError, "No active credentials found for provider: #{provider.name}"
      end

      Ai::Llm::Client.new(provider: provider, credential: credential)
    end

    # Convert execution context into the messages array that Ai::Llm::Client expects
    def build_messages_for_llm(execution_context)
      messages = []

      if execution_context[:conversation_history].is_a?(Array)
        execution_context[:conversation_history].each do |msg|
          role = msg["role"] || msg[:role]
          content = msg["content"] || msg[:content]
          messages << { role: role.to_s, content: content.to_s }
        end
      end

      user_content = execution_context[:input].to_s
      if execution_context[:additional_context].present?
        user_content += "\n\nAdditional Context:\n#{execution_context[:additional_context]}"
      end

      messages << { role: "user", content: user_content }
      messages
    end

    # Resolve model, temperature, max_tokens, and system prompt from agent config
    def resolve_model_config(execution_context)
      model_config = @agent.mcp_metadata&.dig("model_config") || {}
      model = model_config["model"] ||
              @agent.mcp_tool_manifest&.dig("model") ||
              @agent.provider.supported_models.first&.dig("id")
      max_tokens = execution_context.dig(:context, "max_tokens") ||
                   model_config["max_tokens"] || 2000
      temperature = execution_context.dig(:context, "temperature") ||
                    model_config["temperature"] || 0.7

      system_prompt = @agent.build_system_prompt_with_profile.presence ||
                      @agent.mcp_metadata&.dig("system_prompt") ||
                      @agent.mcp_tool_manifest&.dig("system_prompt")

      opts = { max_tokens: max_tokens, temperature: temperature,
               system_prompt: system_prompt }.compact

      [model, opts]
    end

    def format_tool_loop_result(result, model)
      {
        "output" => result[:content],
        "metadata" => {
          "tokens_used" => result[:usage][:total_tokens],
          "prompt_tokens" => result[:usage][:prompt_tokens],
          "completion_tokens" => result[:usage][:completion_tokens],
          "processing_time_ms" => ((Time.current - @start_time) * 1000).round,
          "model_used" => model,
          "provider" => @agent.provider.provider_type,
          "tool_calls" => result[:tool_calls_log],
          "tool_call_count" => result[:tool_calls_log].size
        }
      }
    end

    def format_simple_result(response, model)
      {
        "output" => response.content,
        "metadata" => {
          "tokens_used" => response.total_tokens,
          "prompt_tokens" => response.prompt_tokens,
          "completion_tokens" => response.completion_tokens,
          "processing_time_ms" => ((Time.current - @start_time) * 1000).round,
          "model_used" => model,
          "provider" => @agent.provider.provider_type
        }
      }
    end
  end
end
