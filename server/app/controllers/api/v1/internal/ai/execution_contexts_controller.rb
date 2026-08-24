# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class ExecutionContextsController < InternalBaseController
          include Api::V1::Internal::WorkerTenancy

          # POST /api/v1/internal/ai/execution_contexts
          #
          # Returns a memory-enriched execution context for an agent.
          # Reuses McpAgentExecutor::ContextAndFormatting logic.
          def create
            agent = resolve_agent
            account = agent.account

            input = params[:input].to_s
            context = params[:context]&.to_unsafe_h || {}
            memory_token_budget = params[:memory_token_budget] || 4000

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

            # Resolve model + provider + credential from the agent's coherent
            # resolution triple (Ai::Agent#model_resolution): a pinned model keeps
            # the agent's own provider; otherwise the selector picks the best model
            # across ANY active, credentialed provider in the account.
            model_config = agent.mcp_metadata&.dig("model_config") || {}
            model      = agent.resolved_model
            provider   = agent.resolved_provider
            credential = agent.resolved_credential

            system_prompt = agent.build_system_prompt_with_profile

            render_success(
              execution_context: execution_context,
              system_prompt: system_prompt,
              model: model,
              max_tokens: model_config["max_tokens"] || 2000,
              temperature: model_config["temperature"] || 0.7,
              provider_type: provider&.provider_type,
              provider_credential_id: credential&.id,
              provider_base_url: provider&.api_base_url,
              provider_name: provider&.name
            )
          rescue ActiveRecord::RecordNotFound
            render_error("Agent not found", status: :not_found)
          rescue StandardError => e
            render_error("Failed to build execution context: #{e.message}", status: :unprocessable_content)
          end

          # POST /api/v1/internal/ai/provider_config
          #
          # Returns lightweight provider configuration for an agent.
          # Used by the worker to build direct LLM clients without needing
          # the full execution context (memory injection, skill enrichment).
          def provider_config
            agent = resolve_agent
            # Coherent resolution triple — when the agent has no pinned model the
            # selector picks the best model across ANY active, credentialed
            # provider; the matching credential is resolved for whichever wins.
            provider   = agent.resolved_provider
            credential = agent.resolved_credential
            model      = agent.resolved_model

            render_success(
              provider_type: provider&.provider_type,
              provider_credential_id: credential&.id,
              provider_base_url: provider&.api_base_url,
              provider_name: provider&.name,
              model: model,
              # Non-Fable reasoning fallbacks for the worker's refusal handler.
              # Resolved SERVER-side (no hardcoded id), and ONLY computed for
              # refusal-capable models so the hot path stays cheap for everything
              # else.
              fallback_models: refusal_fallbacks_for(agent, model)
            )
          rescue ActiveRecord::RecordNotFound
            render_error("Agent not found", status: :not_found)
          end

          # GET /api/v1/internal/ai/embedding_config
          #
          # Returns the embedding provider configuration for an account.
          # Used by the worker to build its Ai::EmbeddingService with the right credentials.
          def embedding_config
            account = account_scope.find(params[:account_id])

            # Prefer the designated embedding agent's provider for consistent routing.
            # Falls back to any provider with text_embedding capability.
            embedding_agent = ::Ai::Agent
              .where(account_id: account.id, status: "active")
              .where("name ILIKE ?", "%embedding%")
              .first

            provider = if embedding_agent&.provider&.is_active
                         embedding_agent.provider
                       else
                         ::Ai::Provider
                           .where(account_id: account.id)
                           .where("capabilities @> ?", ["text_embedding"].to_json)
                           .active
                           .first || ::Ai::Provider.where(account_id: account.id).active.first
                       end

            credential = account.ai_provider_credentials
              .where(ai_provider_id: provider&.id, is_active: true)
              .first if provider

            render_success(
              provider_type: provider&.provider_type || "openai",
              credential_id: credential&.id,
              ollama_url: provider&.configuration&.dig("base_url"),
              ollama_model: provider&.configuration&.dig("embedding_model"),
              agent_id: embedding_agent&.id
            )
          rescue ActiveRecord::RecordNotFound
            render_error("Account not found", status: :not_found)
          end

          private

          # ------------------------------------------------------------------
          # Tenancy anchors for this controller's caller-supplied lookups.
          #
          # Every action here renders account-derived material — the agent's
          # resolved provider, its `provider_credential_id` (which the worker
          # then POSTs to credentials#decrypt for the plaintext key), the
          # account's id and its memory/skill-graph context. Loading the agent or
          # account by bare id disclosed one tenant's provider wiring, and a
          # decryptable credential handle, to any other.
          #
          # Same anchor as Internal::Ai::CredentialsController#credential_scope
          # and e9352723d — the authenticated Worker principal's own account,
          # with NO `is_system` exemption. See that controller for why an
          # exemption would be inert in production (workers are account-bound by
          # worker_provision.rake) and actively harmful in a dev-bootstrapped
          # database (the system worker's CN is a published constant).
          # ------------------------------------------------------------------

          # Load the agent, then bind the RESOLVING account for a GLOBAL one.
          #
          # `for_account`, not a bare `where(account_id:)`, because
          # `ai_agents.account_id` is NULLABLE: GLOBAL (platform-provided) agents
          # belong to no account and are legitimately visible to every one of them
          # (GloballyScopable => `account_id IN (NULL, :id)`). A bare equality
          # scope would 404 every global agent and break each chat driven by one.
          #
          # Admitting globals alone would be INCOHERENT with credential_scope,
          # which is strict equality (there are no global credentials —
          # `ai_provider_credentials.account_id` is NOT NULL). A global agent has
          # no provider of its own, so Ai::Agent#compute_model_resolution would
          # fall through to `fallback_resolution` and hand back a credential
          # belonging to whichever account seeded the agent's provider — both a
          # cross-tenant handle disclosure in its own right AND a handle this
          # worker cannot then decrypt, turning every global-agent chat into
          # "Failed to decrypt credentials". `using_account` is the seam the model
          # already provides for exactly this: a global agent used BY an account
          # derives all provider characteristics from THAT account. It is a no-op
          # for account-owned agents, which resolve under their own account.
          def resolve_agent
            agent = agent_scope.find(params[:agent_id])
            agent.global? ? agent.using_account(current_account) : agent
          end

          # The tenancy VALUE is the worker's own `account_id` COLUMN, never
          # `current_worker.account`, so a nil/half-provisioned principal narrows
          # to globals only and reaches no tenant-owned row.
          def agent_scope
            # Shared anchor definition — see Api::V1::Internal::WorkerTenancy.
            ::Ai::Agent.for_account(worker_account_id)
          end

          # `accounts.id` is never NULL, so a nil worker account_id matches no
          # row — the nil principal is denied rather than granted.
          def account_scope
            Account.where(id: worker_account_id)
          end

          # Ordered non-Fable reasoning fallbacks for the worker's refusal handler.
          # Gated on refusal_capable? — non-Fable models never pay the resolution
          # cost. Best-effort: a resolution failure must never break the config call.
          def refusal_fallbacks_for(agent, model)
            return [] unless ::Ai::Llm::ModelCapabilities.refusal_capable?(model)

            ::Ai::ModelFallbackResolver.reasoning_fallbacks(
              account: agent.account, agent_type: agent.agent_type, exclude: model
            )
          rescue StandardError => e
            Rails.logger.warn("[provider_config] refusal fallback resolution failed: #{e.message}")
            []
          end
        end
      end
    end
  end
end
