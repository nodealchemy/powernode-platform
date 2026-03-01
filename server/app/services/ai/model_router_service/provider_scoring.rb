# frozen_string_literal: true

module Ai
  class ModelRouterService
    module ProviderScoring
      extend ActiveSupport::Concern

      private

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
    end
  end
end
