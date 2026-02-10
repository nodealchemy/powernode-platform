# frozen_string_literal: true

module Ai
  class ModelRouterService
    include ActiveModel::Model

    class NoProvidersAvailableError < StandardError; end
    class RoutingError < StandardError; end

    # Available routing strategies
    STRATEGIES = %w[
      cost_optimized
      latency_optimized
      quality_optimized
      round_robin
      weighted
      hybrid
      ml_based
    ].freeze

    # Default weights for hybrid strategy
    DEFAULT_WEIGHTS = {
      cost: 0.4,
      latency: 0.3,
      quality: 0.2,
      reliability: 0.1
    }.freeze

    # Model tier definitions for automatic routing
    MODEL_TIERS = {
      "economy" => %w[gpt-4.1-nano haiku claude-3-5-haiku claude-haiku-4-5].freeze,
      "standard" => %w[gpt-4.1-mini o4-mini claude-sonnet claude-sonnet-4 claude-sonnet-4-5].freeze,
      "premium" => %w[gpt-4.1 o3 claude-opus claude-opus-4 claude-opus-4-5 claude-opus-4-6].freeze
    }.freeze

    # Task type → default model tier mapping
    TASK_TIER_MAP = {
      "classification" => "economy",
      "extraction" => "economy",
      "formatting" => "economy",
      "routing" => "economy",
      "simple_qa" => "economy",
      "summarization" => "standard",
      "translation" => "standard",
      "analysis" => "standard",
      "code_review" => "standard",
      "agent_task" => "standard",
      "reasoning" => "premium",
      "code_generation" => "premium",
      "creative" => "premium",
      "critical_decision" => "premium"
    }.freeze

    def initialize(account:, strategy: "cost_optimized", custom_weights: nil)
      @account = account
      @strategy = strategy
      @custom_weights = custom_weights || DEFAULT_WEIGHTS
      @logger = Rails.logger
      @redis = Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")

      raise ArgumentError, "Invalid strategy: #{strategy}" unless STRATEGIES.include?(strategy)
    end

    # ==========================================================================
    # MAIN ROUTING METHOD
    # ==========================================================================

    # Route a request to the optimal provider
    def route(request_context)
      start_time = Time.current

      # Find matching routing rules
      matching_rules = find_matching_rules(request_context)

      # Get available providers
      available_providers = get_available_providers(request_context)

      raise NoProvidersAvailableError, "No providers available for request" if available_providers.empty?

      # Score and select provider
      selected_provider, scoring_details = select_optimal_provider(
        providers: available_providers,
        request_context: request_context,
        matching_rules: matching_rules
      )

      # Record the routing decision
      decision = record_routing_decision(
        provider: selected_provider,
        request_context: request_context,
        matching_rule: matching_rules.first,
        scoring_details: scoring_details,
        start_time: start_time
      )

      {
        provider: selected_provider,
        decision_id: decision.id,
        strategy_used: @strategy,
        scoring: scoring_details,
        estimated_cost: scoring_details[:estimated_cost_usd],
        estimated_latency_ms: scoring_details[:estimated_latency_ms]
      }
    end

    # ==========================================================================
    # EXECUTE WITH ROUTING
    # ==========================================================================

    # Route and execute a request with automatic fallback
    def route_and_execute(request_context, max_retries: 3)
      attempted_providers = []
      last_error = nil
      decision = nil

      max_retries.times do |attempt|
        begin
          # Get routing decision, excluding already attempted providers
          routing = route(request_context.merge(exclude_providers: attempted_providers))
          provider = routing[:provider]
          decision = Ai::RoutingDecision.find(routing[:decision_id])

          attempted_providers << provider.id

          # Execute the request
          execution_start = Time.current
          result = yield(provider)
          execution_time = ((Time.current - execution_start) * 1000).to_i

          # Record successful outcome
          decision.record_outcome!(
            outcome: "succeeded",
            cost_usd: result[:cost_usd],
            latency_ms: execution_time,
            tokens_used: result[:tokens_used],
            quality_score: result[:quality_score]
          )

          # Record provider metrics
          record_provider_metrics(provider, result.merge(latency_ms: execution_time, success: true))

          return {
            result: result,
            provider: provider,
            decision: decision,
            attempts: attempt + 1
          }

        rescue StandardError => e
          last_error = e
          @logger.error "Routing attempt #{attempt + 1} failed: #{e.message}"

          # Record failure
          decision&.record_outcome!(outcome: "failed")

          # Record provider metrics
          if provider
            record_provider_metrics(provider, { success: false, error: e.message })
          end

          next if attempt < max_retries - 1
        end
      end

      raise RoutingError, "All routing attempts failed. Last error: #{last_error&.message}"
    end

    # ==========================================================================
    # TASK-BASED ROUTING
    # ==========================================================================

    # Route based on task type — automatically selects model tier
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

    # ==========================================================================
    # COST OPTIMIZATION ANALYSIS
    # ==========================================================================

    # Analyze potential cost savings
    def analyze_cost_savings(time_range: 30.days)
      decisions = Ai::RoutingDecision.for_account(@account)
                                      .where("created_at >= ?", time_range.ago)
                                      .where.not(actual_cost_usd: nil)

      return nil if decisions.empty?

      total_actual_cost = decisions.sum(:actual_cost_usd)
      total_alternative_cost = decisions.sum(:alternative_cost_usd)
      total_savings = decisions.sum(:savings_usd)

      {
        period_days: (time_range / 1.day).to_i,
        total_decisions: decisions.count,
        total_actual_cost_usd: total_actual_cost.to_f.round(4),
        total_alternative_cost_usd: total_alternative_cost.to_f.round(4),
        total_savings_usd: total_savings.to_f.round(4),
        savings_percentage: total_alternative_cost > 0 ?
          ((total_savings / total_alternative_cost) * 100).round(2) : 0,
        avg_savings_per_request: decisions.count > 0 ?
          (total_savings / decisions.count).to_f.round(6) : 0,
        by_strategy: decisions.group(:strategy_used).sum(:savings_usd),
        by_provider: decisions.group(:selected_provider_id)
                              .sum(:savings_usd)
                              .transform_keys { |id| Ai::Provider.find_by(id: id)&.name || id }
      }
    end

    # Get optimization recommendations
    def get_optimization_recommendations
      recommendations = []

      # Analyze recent routing decisions
      recent_decisions = Ai::RoutingDecision.for_account(@account)
                                             .recent(7.days)
                                             .where.not(actual_cost_usd: nil)

      return recommendations if recent_decisions.count < 10

      # High-cost provider recommendation
      provider_costs = recent_decisions.group(:selected_provider_id)
                                        .sum(:actual_cost_usd)
                                        .sort_by { |_, cost| -cost }

      if provider_costs.length > 1
        expensive_provider_id, expensive_cost = provider_costs.first
        expensive_provider = Ai::Provider.find_by(id: expensive_provider_id)

        if expensive_provider && expensive_cost > provider_costs.values.sum * 0.5
          recommendations << {
            type: "cost_optimization",
            priority: "high",
            title: "High concentration on expensive provider",
            description: "#{expensive_provider.name} accounts for >50% of costs",
            potential_savings_percentage: 20,
            action: "Consider enabling cost_optimized routing strategy"
          }
        end
      end

      # Latency optimization
      slow_decisions = recent_decisions.where("actual_latency_ms > ?", 5000)
      if slow_decisions.count > recent_decisions.count * 0.2
        recommendations << {
          type: "performance_optimization",
          priority: "medium",
          title: "High latency detected",
          description: "#{(slow_decisions.count.to_f / recent_decisions.count * 100).round(1)}% of requests have latency > 5s",
          action: "Consider latency_optimized or hybrid routing strategy"
        }
      end

      # Quality issues
      failed_decisions = recent_decisions.where(outcome: %w[failed timeout error])
      if failed_decisions.count > recent_decisions.count * 0.05
        recommendations << {
          type: "reliability_improvement",
          priority: "high",
          title: "High failure rate",
          description: "#{(failed_decisions.count.to_f / recent_decisions.count * 100).round(1)}% failure rate",
          action: "Review provider health and consider quality_optimized routing"
        }
      end

      recommendations
    end

    # ==========================================================================
    # ROUTING STATISTICS
    # ==========================================================================

    # Get routing statistics
    def statistics(time_range: 24.hours)
      Ai::RoutingDecision.stats_for_period(account: @account, period: time_range)
    end

    # Get provider performance rankings
    def provider_rankings
      providers = @account.ai_providers.active

      providers.map do |provider|
        recent_decisions = Ai::RoutingDecision.for_account(@account)
                                               .for_provider(provider)
                                               .recent(7.days)

        total = recent_decisions.count
        successful = recent_decisions.successful.count
        avg_cost = recent_decisions.average(:actual_cost_usd)&.to_f || 0
        avg_latency = recent_decisions.average(:actual_latency_ms)&.to_f || 0

        {
          provider_id: provider.id,
          provider_name: provider.name,
          total_requests: total,
          success_rate: total > 0 ? (successful.to_f / total * 100).round(2) : 100,
          avg_cost_usd: avg_cost.round(6),
          avg_latency_ms: avg_latency.round(2),
          score: calculate_provider_score(provider, total, successful, avg_cost, avg_latency)
        }
      end.sort_by { |p| -p[:score] }
    end

    private

    # ==========================================================================
    # PRIVATE METHODS
    # ==========================================================================

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

    def find_matching_rules(request_context)
      Ai::ModelRoutingRule.for_account(@account)
                          .active
                          .by_priority
                          .select { |rule| rule.matches?(request_context) }
    end

    def get_available_providers(request_context)
      providers = @account.ai_providers.active

      # Filter by capability if specified
      if request_context[:capabilities].present?
        required_capabilities = Array(request_context[:capabilities])
        providers = providers.select do |p|
          (required_capabilities - p.capabilities).empty?
        end
      end

      # Exclude already attempted providers
      if request_context[:exclude_providers].present?
        exclude_ids = Array(request_context[:exclude_providers])
        providers = providers.where.not(id: exclude_ids)
      end

      # Filter by circuit breaker status
      providers.select do |provider|
        circuit_breaker = Ai::ProviderCircuitBreakerService.new(provider)
        circuit_breaker.provider_available?
      end
    end

    def select_optimal_provider(providers:, request_context:, matching_rules:)
      # Apply rule-based filtering first
      if matching_rules.any?
        rule = matching_rules.first
        target_provider_ids = rule.target_provider_ids

        if target_provider_ids.any?
          filtered = providers.select { |p| target_provider_ids.include?(p.id.to_s) }
          providers = filtered if filtered.any?
        end
      end

      # Score all providers
      scored_providers = providers.map do |provider|
        score = calculate_composite_score(provider, request_context)
        {
          provider: provider,
          score: score[:total],
          breakdown: score
        }
      end

      # Select based on strategy
      selected = case @strategy
      when "cost_optimized"
        scored_providers.min_by { |p| p[:breakdown][:cost_score] }
      when "latency_optimized"
        scored_providers.min_by { |p| p[:breakdown][:latency_score] }
      when "quality_optimized"
        scored_providers.max_by { |p| p[:breakdown][:quality_score] }
      when "round_robin"
        select_round_robin(scored_providers)
      when "weighted"
        select_weighted(scored_providers)
      else
        scored_providers.max_by { |p| p[:score] }
      end

      [
        selected[:provider],
        {
          total_score: selected[:score],
          breakdown: selected[:breakdown],
          candidates: scored_providers.map { |p| { provider_id: p[:provider].id, score: p[:score] } },
          estimated_cost_usd: selected[:breakdown][:estimated_cost],
          estimated_latency_ms: selected[:breakdown][:estimated_latency]
        }
      ]
    end

    def calculate_composite_score(provider, request_context)
      estimated_tokens = request_context[:estimated_tokens] || 1000

      # Cost score (lower is better, so invert for final score)
      cost_per_1k = get_provider_cost_per_1k(provider)
      estimated_cost = (cost_per_1k * estimated_tokens / 1000.0)
      cost_score = 1.0 / (1.0 + estimated_cost)

      # Latency score (lower is better)
      avg_latency = get_provider_avg_latency(provider)
      latency_score = 1.0 / (1.0 + (avg_latency / 1000.0))

      # Quality/reliability score (higher is better)
      success_rate = get_provider_success_rate(provider)
      quality_score = success_rate / 100.0

      # Availability score
      availability_score = provider.is_active? ? 1.0 : 0.0

      # Calculate weighted total
      total = (cost_score * @custom_weights[:cost]) +
              (latency_score * @custom_weights[:latency]) +
              (quality_score * @custom_weights[:quality]) +
              (availability_score * @custom_weights[:reliability])

      {
        total: total.round(4),
        cost_score: cost_score.round(4),
        latency_score: latency_score.round(4),
        quality_score: quality_score.round(4),
        availability_score: availability_score,
        estimated_cost: estimated_cost.round(6),
        estimated_latency: avg_latency.round(2)
      }
    end

    def get_provider_cost_per_1k(provider)
      # Check recent metrics first
      recent_metric = Ai::ProviderMetric.for_provider(provider)
                                         .for_account(@account)
                                         .recent(1.hour)
                                         .order(recorded_at: :desc)
                                         .first

      return recent_metric.cost_per_1k_tokens if recent_metric&.cost_per_1k_tokens.present?

      # Fall back to provider configuration
      provider.configuration&.dig("pricing", "per_1k_tokens") || 0.002
    end

    def get_provider_avg_latency(provider)
      recent_metric = Ai::ProviderMetric.for_provider(provider)
                                         .for_account(@account)
                                         .recent(1.hour)
                                         .order(recorded_at: :desc)
                                         .first

      recent_metric&.avg_latency_ms || 1000.0
    end

    def get_provider_success_rate(provider)
      recent_metric = Ai::ProviderMetric.for_provider(provider)
                                         .for_account(@account)
                                         .recent(1.hour)
                                         .order(recorded_at: :desc)
                                         .first

      recent_metric&.success_rate || 100.0
    end

    def select_round_robin(scored_providers)
      counter = @redis.incr("router:#{@account.id}:rr_counter")
      @redis.expire("router:#{@account.id}:rr_counter", 1.hour)
      scored_providers[counter % scored_providers.length]
    end

    def select_weighted(scored_providers)
      total_score = scored_providers.sum { |p| p[:score] }
      return scored_providers.first if total_score.zero?

      random = rand * total_score
      cumulative = 0

      scored_providers.each do |provider|
        cumulative += provider[:score]
        return provider if random <= cumulative
      end

      scored_providers.last
    end

    def calculate_provider_score(provider, total, successful, avg_cost, avg_latency)
      return 0 if total.zero?

      success_weight = (successful.to_f / total) * 40
      cost_weight = avg_cost > 0 ? (1.0 / (1.0 + avg_cost)) * 30 : 30
      latency_weight = avg_latency > 0 ? (1.0 / (1.0 + (avg_latency / 1000))) * 20 : 20
      availability_weight = provider.is_active? ? 10 : 0

      (success_weight + cost_weight + latency_weight + availability_weight).round(2)
    end

    def record_routing_decision(provider:, request_context:, matching_rule:, scoring_details:, start_time:)
      Ai::RoutingDecision.create!(
        account: @account,
        routing_rule: matching_rule,
        selected_provider: provider,
        workflow_run_id: request_context[:workflow_run_id],
        agent_execution_id: request_context[:agent_execution_id],
        request_type: request_context[:request_type] || "completion",
        request_metadata: request_context.except(:exclude_providers),
        estimated_tokens: request_context[:estimated_tokens],
        strategy_used: @strategy,
        candidates_evaluated: scoring_details[:candidates],
        scoring_breakdown: scoring_details[:breakdown],
        decision_reason: "Selected based on #{@strategy} strategy",
        estimated_cost_usd: scoring_details[:estimated_cost_usd],
        alternative_cost_usd: calculate_alternative_cost(scoring_details[:candidates], provider.id)
      )
    end

    def calculate_alternative_cost(candidates, selected_id)
      alternatives = candidates.reject { |c| c[:provider_id] == selected_id }
      return nil if alternatives.empty?

      # Return the cost of the most expensive alternative
      alternatives.map { |c| c[:score] }.max
    end

    def record_provider_metrics(provider, result)
      Ai::ProviderMetric.record_metrics(
        provider: provider,
        account: @account,
        metrics_data: {
          requests: 1,
          successes: result[:success] ? 1 : 0,
          failures: result[:success] ? 0 : 1,
          input_tokens: result[:input_tokens] || 0,
          output_tokens: result[:output_tokens] || 0,
          cost_usd: result[:cost_usd] || 0,
          latency_ms: result[:latency_ms],
          error_type: result[:error]&.class&.name,
          model_name: result[:model_name]
        }
      )
    end
  end
end
