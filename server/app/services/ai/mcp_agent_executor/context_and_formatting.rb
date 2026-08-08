# frozen_string_literal: true

class Ai::McpAgentExecutor
  module ContextAndFormatting
    extend ActiveSupport::Concern

    private

    def build_execution_context(input_parameters)
      base_context = {
        agent_id: @agent.id,
        agent_name: @agent.name,
        agent_type: @agent.agent_type,
        account_id: @account.id,
        execution_id: @execution&.execution_id || SecureRandom.uuid,
        input: input_parameters["input"],
        started_at: @start_time
      }

      # Merge context from input parameters
      if input_parameters["context"].is_a?(Hash)
        base_context.merge!(input_parameters["context"].symbolize_keys)
      end

      # Add agent-specific configuration
      agent_config = @agent.mcp_tool_manifest["configuration"] || {}
      base_context.merge!(agent_config.symbolize_keys)

      # Full memory context injection (all 7 types)
      begin
        injector = Ai::Memory::ContextInjectorService.new(agent: @agent, account: @account)
        memory_token_budget = input_parameters.dig("context", "memory_token_budget") || 4000
        query_text = input_parameters["input"]

        memory_result = injector.build_context(query: query_text, token_budget: memory_token_budget)

        if memory_result[:context].present?
          base_context[:additional_context] = [
            base_context[:additional_context], memory_result[:context]
          ].compact.join("\n\n")
          base_context[:memory_breakdown] = memory_result[:breakdown]
          base_context[:memory_tokens_used] = memory_result[:token_estimate]
          persist_context_metrics(memory_result)
        end
      rescue StandardError => e
        Rails.logger.warn "[ContextAndFormatting] Memory context injection failed: #{e.message}"
      end

      # Skill graph context enrichment (additive — skill navigation maps)
      begin
        if @account.ai_knowledge_graph_nodes.active.skill_nodes.exists?
          mode = input_parameters.dig("context", "skill_graph_mode") || :auto
          skill_budget = input_parameters.dig("context", "skill_token_budget") || 2000
          enrichment = Ai::SkillGraph::ContextEnrichmentService.new(@account).enrich(
            agent: @agent, input_text: input_parameters["input"],
            mode: mode.to_sym, token_budget: skill_budget
          )
          context_block = enrichment[:context_block].presence
          if context_block
            base_context[:additional_context] = [
              base_context[:additional_context], context_block
            ].compact.join("\n\n")
          end

          # F4: skills dynamically surfaced into this execution's context (auto
          # mode only) are a real usage signal even though they aren't attached
          # to the agent — carried through to MemoryWriteback so
          # SelfLearningService#record_skill_outcomes isn't limited to
          # agent.skills.active.
          base_context[:resolved_skill_ids] = Array(enrichment.dig(:metadata, :skill_ids))
        end
      rescue StandardError => e
        Rails.logger.warn "[ContextAndFormatting] Skill graph enrichment failed: #{e.message}"
      end

      base_context
    end

    def build_prompt_from_context(context)
      base_prompt = context[:input]

      # NOTE: system_prompt is passed separately via API parameter (line 82)
      # DO NOT duplicate it in the user message

      # Add conversation history if available for multi-turn context
      if context[:conversation_history].is_a?(Array) && context[:conversation_history].any?
        history_text = context[:conversation_history].map do |msg|
          role = msg["role"] || msg[:role]
          content = msg["content"] || msg[:content]
          "[#{role.upcase}]: #{content}"
        end.join("\n\n")

        base_prompt = "Previous conversation:\n#{history_text}\n\n[USER]: #{base_prompt}"
      end

      # Add context information if available
      if context[:additional_context].present?
        base_prompt += "\n\nAdditional Context: #{context[:additional_context]}"
      end

      # Agent role/behavior is already defined in system_prompt
      # No need to add role-based prefixes here

      base_prompt
    end

    def format_mcp_response(result)
      @logger.debug "[MCP_AGENT_EXECUTOR] Formatting MCP response"

      # Ensure response follows MCP tool response format
      mcp_response = {
        "result" => result,
        "tool_id" => @agent.mcp_tool_id,
        "execution_id" => @execution&.execution_id || SecureRandom.uuid,
        "timestamp" => Time.current.iso8601,
        "agent_info" => {
          "agent_id" => @agent.id,
          "agent_name" => @agent.name,
          "agent_version" => @agent.version
        }
      }

      # Add telemetry data
      mcp_response["telemetry"] = {
        "execution_time_ms" => ((Time.current - @start_time) * 1000).round,
        "tokens_used" => result.dig("metadata", "tokens_used") || 0,
        "provider_used" => @agent.provider.provider_type
      }

      mcp_response
    end

    def handle_execution_error(error)
      @logger.error "[MCP_AGENT_EXECUTOR] Execution error: #{error.message}"
      @logger.error error.backtrace.join("\n") if error.backtrace

      # Update execution record if available
      if @execution
        @execution.update!(
          status: "failed",
          error_message: error.message,
          completed_at: Time.current
        )
      end

      # Return MCP error response
      {
        "error" => {
          "code" => map_error_code(error),
          "message" => error.message,
          "type" => error.class.name,
          "timestamp" => Time.current.iso8601
        },
        "tool_id" => @agent.mcp_tool_id,
        "execution_id" => @execution&.execution_id || SecureRandom.uuid
      }
    end

    def handle_timeout_error(error)
      @logger.error "[MCP_AGENT_EXECUTOR] Timeout error: #{error.message}"

      # Update execution record if available
      if @execution
        @execution.update!(
          status: "timeout",
          error_message: "Execution timed out",
          completed_at: Time.current
        )
      end

      {
        "error" => {
          "code" => -32603, # Internal error
          "message" => "Execution timed out",
          "type" => "TimeoutError",
          "timestamp" => Time.current.iso8601
        },
        "tool_id" => @agent.mcp_tool_id,
        "execution_id" => @execution&.execution_id || SecureRandom.uuid
      }
    end

    def map_error_code(error)
      case error
      when ValidationError
        -32602 # Invalid params
      when ProviderError
        -32603 # Internal error
      when TimeoutError
        -32603 # Internal error
      else
        -32603 # Internal error
      end
    end

    # IMP-e55984da015d — the injector's token metrics were computed and
    # discarded, leaving per-operation context size unmeasurable. Persisted
    # into the execution's performance_metrics jsonb (no new table).
    # update_columns deliberately: the execution is mid-flight and a
    # metrics write must neither fire completed-execution validations nor
    # bump callbacks. Best-effort — a metrics write must never fail the
    # execution. Only real AgentExecution records qualify (specs pass
    # doubles; guard on update_columns support + persistence).
    def persist_context_metrics(memory_result)
      return unless @execution.respond_to?(:update_columns) && @execution.respond_to?(:persisted?) && @execution.persisted?

      merged = (@execution.performance_metrics || {}).merge(
        "context" => {
          "total_tokens" => memory_result[:token_estimate],
          "sections" => (memory_result[:breakdown] || {}).transform_keys(&:to_s)
        }
      )
      @execution.update_columns(performance_metrics: merged)
    rescue StandardError => e
      Rails.logger.warn "[ContextAndFormatting] context metrics persistence failed: #{e.message}"
    end
  end
end
