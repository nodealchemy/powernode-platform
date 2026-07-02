# frozen_string_literal: true

module Ai
  class ModelRouterService
    module TaskClassification
      extend ActiveSupport::Concern

      # Route based on task type -- automatically selects model tier
      # @param task_type [String] one of TASK_TIER_MAP keys
      # @param request_context [Hash] additional routing context
      # @return [Hash] routing result with :provider, :model_tier, :recommended_models
      def route_for_task(task_type:, **request_context)
        # Use complexity classifier for intelligent tier selection
        tier = classify_task_tier(task_type, request_context)

        # Budget-aware auto-downgrade: force economy tier if budget >90% consumed
        tier = budget_aware_downgrade(tier, request_context)

        routing = route(request_context.merge(model_tier: tier, task_type: task_type))

        routing.merge(
          model_tier: tier,
          recommended_models: models_for_tier(tier, routing[:provider])
        )
      end

      # Build a WorkerLlmClient from a routing result
      # @param routing [Hash] result from #route or #route_for_task
      # @return [WorkerLlmClient]
      def client_for_routing(routing)
        provider = routing[:provider]
        credential = provider.provider_credentials.where(is_active: true).first

        raise RoutingError, "No active credentials for provider #{provider.name}" unless credential

        WorkerLlmClient.new(provider: provider, credential: credential)
      end

      # Convenience: route for task and return a ready-to-use client + model
      # @param task_type [String]
      # @param request_context [Hash]
      # @return [Hash] { client:, model:, routing: }
      def route_and_build_client(task_type:, **request_context)
        routing = route_for_task(task_type: task_type, **request_context)
        client = client_for_routing(routing)
        model = routing[:recommended_models]&.first

        { client: client, model: model, routing: routing }
      end

      private

      # Classify task complexity and return recommended tier
      def classify_task_tier(task_type, request_context)
        # Fall back to static mapping if no messages provided
        messages = request_context[:messages]
        return TASK_TIER_MAP[task_type.to_s] || "standard" unless messages.present?

        begin
          classifier = Ai::Routing::TaskComplexityClassifierService.new(account: @account)
          result = classifier.classify(
            task_type: task_type,
            messages: messages,
            tools: request_context[:tools] || [],
            context: request_context.slice(:force_tier)
          )
          result[:recommended_tier]
        rescue StandardError => e
          @logger.warn "[ModelRouter] Complexity classification failed, using static map: #{e.message}"
          TASK_TIER_MAP[task_type.to_s] || "standard"
        end
      end

      # Downgrade tier if agent/account budget is >90% consumed
      def budget_aware_downgrade(tier, request_context)
        return tier if tier == "economy"

        agent_id = request_context[:agent_id]
        if agent_id.present?
          budget = Ai::AgentBudget.where(account: @account, agent_id: agent_id).active.first
          if budget&.nearly_exceeded?(threshold: 0.9)
            @logger.info "[ModelRouter] Budget >90% consumed for agent #{agent_id}, downgrading to economy tier"
            return "economy"
          end
        end

        # Check account-level budget
        monthly_budget = @account.settings&.dig("ai_monthly_budget")
        if monthly_budget.present?
          month_cost = Ai::AgentExecution.joins(:agent)
                                         .where(ai_agents: { account_id: @account.id })
                                         .where("ai_agent_executions.created_at >= ?", Time.current.beginning_of_month)
                                         .sum(:cost_usd).to_f
          if month_cost >= monthly_budget * 0.9
            @logger.info "[ModelRouter] Account monthly budget >90% consumed, downgrading to economy tier"
            return "economy"
          end
        end

        tier
      end

      # Resolve the provider's models for a router tier LABEL (economy/standard/
      # premium), derived live from Ai::ModelTiers.classify over the provider's
      # synced catalog — NOT a static model-name list. Label→ladder mapping:
      # economy→:light, standard→:standard, premium→:reasoning. Frontier (Fable/
      # Mythos) is admitted into "premium" ONLY when the Fable framework is enabled
      # for the account; otherwise frontier stays out of every tier (mirrors the
      # candidacy gate below), so a "premium" request can never silently route to a
      # gated frontier model.
      def models_for_tier(tier, provider)
        ladder = ::Ai::ModelTiers.from_label(tier)
        fable_on = ::Ai::FableRouting.enabled_for?(@account)
        wanted = [ladder]
        wanted << :frontier if ladder == :reasoning && fable_on

        # Get available models from the provider's synced model list.
        available = Array(provider.available_models).compact
        # Fable-5 CANDIDACY gate (mirrors Ai::AgentModelSelector): when the Fable
        # framework is OFF for this account, Fable/Mythos are not selectable — drop
        # them from the tier pool (and the default fallback below) so an
        # unavailable model can never be routed to. Read the toggle only when a
        # Fable model is actually present.
        if available.any? { |m| ::Ai::FableRouting.fable_model?(m) } && !fable_on
          available = available.reject { |m| ::Ai::FableRouting.fable_model?(m) }
        end
        if available.empty?
          # No synced models: fall back to the provider's configured default so
          # downstream callers (route_and_build_client) never receive a nil model.
          default = provider.default_model
          default = nil if default.present? && ::Ai::FableRouting.fable_model?(default) && !fable_on
          return default.present? ? [default] : []
        end

        # Match by unified tier classification (price-ladder aware, no hardcoded ids).
        matched = available.select { |model_id| wanted.include?(::Ai::ModelTiers.classify(model_id)) }

        matched.presence || available.first(3)
      end
    end
  end
end
