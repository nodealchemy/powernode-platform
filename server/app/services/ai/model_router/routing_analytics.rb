# frozen_string_literal: true

module Ai
  class ModelRouterService
    module RoutingAnalytics
      extend ActiveSupport::Concern

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
end
