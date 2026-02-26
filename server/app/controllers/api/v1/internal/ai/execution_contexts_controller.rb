# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class ExecutionContextsController < InternalBaseController
          # POST /api/v1/internal/ai/execution_contexts
          #
          # Returns a memory-enriched execution context for an agent.
          # Reuses McpAgentExecutor::ContextAndFormatting logic.
          def create
            agent = ::Ai::Agent.find(params[:agent_id])
            account = agent.account

            input = params[:input].to_s
            context = params[:context]&.to_unsafe_h || {}
            memory_token_budget = params[:memory_token_budget] || 4000

            # Hydrate working memory
            begin
              ::Ai::Memory::WorkingMemoryService.new(agent: agent, account: account).load_from_database
            rescue StandardError => e
              Rails.logger.warn "[ExecutionContexts] Working memory hydration failed: #{e.message}"
            end

            # Build base context
            execution_context = {
              agent_id: agent.id,
              agent_name: agent.name,
              agent_type: agent.agent_type,
              account_id: account.id,
              input: input
            }
            execution_context.merge!(context.symbolize_keys)

            # Memory context injection
            begin
              injector = ::Ai::Memory::ContextInjectorService.new(agent: agent, account: account)
              memory_result = injector.build_context(query: input, token_budget: memory_token_budget.to_i)

              if memory_result[:context].present?
                execution_context[:additional_context] = memory_result[:context]
                execution_context[:memory_breakdown] = memory_result[:breakdown]
                execution_context[:memory_tokens_used] = memory_result[:token_estimate]
              end
            rescue StandardError => e
              Rails.logger.warn "[ExecutionContexts] Memory injection failed: #{e.message}"
            end

            # Skill graph enrichment
            begin
              if account.ai_knowledge_graph_nodes.active.skill_nodes.exists?
                enrichment = ::Ai::SkillGraph::ContextEnrichmentService.new(account).enrich(
                  agent: agent, input_text: input,
                  mode: :auto, token_budget: 2000
                )
                if enrichment[:context_block].present?
                  execution_context[:additional_context] = [
                    execution_context[:additional_context], enrichment[:context_block]
                  ].compact.join("\n\n")
                end
              end
            rescue StandardError => e
              Rails.logger.warn "[ExecutionContexts] Skill graph enrichment failed: #{e.message}"
            end

            # Resolve model config
            model_config = agent.mcp_metadata&.dig("model_config") || {}
            model = model_config["model"] ||
                    agent.mcp_tool_manifest&.dig("model") ||
                    agent.provider.supported_models.first&.dig("id")

            system_prompt = agent.build_system_prompt_with_profile.presence ||
                            agent.mcp_metadata&.dig("system_prompt")

            render_success(
              execution_context: execution_context,
              system_prompt: system_prompt,
              model: model,
              max_tokens: model_config["max_tokens"] || 2000,
              temperature: model_config["temperature"] || 0.7
            )
          rescue ActiveRecord::RecordNotFound
            render_error("Agent not found", status: :not_found)
          rescue StandardError => e
            render_error("Failed to build execution context: #{e.message}", status: :unprocessable_entity)
          end
        end
      end
    end
  end
end
