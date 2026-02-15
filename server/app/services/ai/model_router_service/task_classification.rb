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

      # Build an Ai::Llm::Client from a routing result
      # @param routing [Hash] result from #route or #route_for_task
      # @return [Ai::Llm::Client]
      def client_for_routing(routing)
        provider = routing[:provider]
        credential = provider.provider_credentials.where(is_active: true).first

        raise RoutingError, "No active credentials for provider #{provider.name}" unless credential

        Ai::Llm::Client.new(provider: provider, credential: credential)
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
          month_cost = Ai::WorkflowRun.joins(:workflow)
                                       .where(ai_workflows: { account_id: @account.id })
                                       .where("ai_workflow_runs.created_at >= ?", Time.current.beginning_of_month)
                                       .sum(:total_cost).to_f
          if month_cost >= monthly_budget * 0.9
            @logger.info "[ModelRouter] Account monthly budget >90% consumed, downgrading to economy tier"
            return "economy"
          end
        end

        tier
      end

      def models_for_tier(tier, provider)
        tier_patterns = MODEL_TIERS[tier] || MODEL_TIERS["standard"]
        provider_type = provider.provider_type.to_s.downcase

        # Get available models from provider's synced model list
        available = provider.ai_models&.active&.pluck(:model_id) || []
        return available.first(3) if available.empty?

        # Match tier patterns against available models
        matched = available.select do |model_id|
          downcased = model_id.downcase
          tier_patterns.any? { |pattern| downcased.include?(pattern) }
        end

        matched.presence || available.first(3)
      end
    end
  end
end
