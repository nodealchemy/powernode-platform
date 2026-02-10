# frozen_string_literal: true

module Ai
  module Finops
    # Service for token usage analytics, waste analysis, forecasting, and optimization scoring.
    #
    # Provides comprehensive FinOps intelligence for AI token consumption including:
    # - Usage summaries with breakdowns by model and tier
    # - Waste analysis identifying redundant context and cache misses
    # - Multi-month forecasting with trend analysis
    # - Composite optimization scoring (0-100)
    #
    # Usage:
    #   service = Ai::Finops::TokenAnalyticsService.new(account: account)
    #   summary = service.usage_summary(period: 30.days)
    #   waste = service.waste_analysis
    #   forecast = service.forecast(months: 3)
    #   score = service.optimization_score
    #
    class TokenAnalyticsService
      include Ai::Concerns::AccountScoped

      # Tier definitions for grouping models
      MODEL_TIERS = Ai::ModelRouterService::MODEL_TIERS

      # Default forecasting parameters
      DEFAULT_FORECAST_MONTHS = 3
      DEFLATION_FACTOR = 0.95 # 5% cost deflation per month (model prices trend down)

      # Optimization score weights
      OPTIMIZATION_WEIGHTS = {
        cache_hit_rate: 0.30,
        tier_utilization: 0.25,
        waste_ratio: 0.25,
        budget_efficiency: 0.20
      }.freeze

      # ==========================================================================
      # USAGE SUMMARY
      # ==========================================================================

      # Get comprehensive token usage summary for a period.
      #
      # @param period [ActiveSupport::Duration] Time period (default 30 days)
      # @return [Hash] Token usage summary with breakdowns
      def usage_summary(period: 30.days)
        start_time = period.ago

        metrics = provider_metrics_for_period(start_time)
        decisions = routing_decisions_for_period(start_time)

        total_input = metrics.sum(:total_input_tokens)
        total_output = metrics.sum(:total_output_tokens)
        total_tokens = metrics.sum(:total_tokens)
        total_cost = metrics.sum(:total_cost_usd).to_f
        cached_tokens = decisions.sum(:cached_tokens)

        {
          period_days: (period / 1.day).to_i,
          total_tokens: total_tokens,
          prompt_tokens: total_input,
          completion_tokens: total_output,
          cached_tokens: cached_tokens,
          total_cost: total_cost.round(4),
          avg_cost_per_1k_tokens: total_tokens > 0 ? (total_cost / (total_tokens / 1000.0)).round(6) : 0,
          by_model: usage_by_model(metrics),
          by_tier: usage_by_tier(decisions),
          daily_usage: daily_token_usage(start_time)
        }
      end

      # ==========================================================================
      # WASTE ANALYSIS
      # ==========================================================================

      # Analyze token waste and inefficiencies.
      #
      # @return [Hash] Waste analysis with recommendations
      def waste_analysis
        period_start = 30.days.ago
        decisions = routing_decisions_for_period(period_start)
        metrics = provider_metrics_for_period(period_start)

        total_tokens = metrics.sum(:total_tokens)
        cached_decisions = decisions.where(was_cached: true)
        compressed_decisions = decisions.where(was_compressed: true)
        total_decisions = decisions.count

        # Calculate cache miss rate
        cacheable_decisions = decisions.where("estimated_tokens >= ?", 1024)
        cache_miss_rate = if cacheable_decisions.count > 0
                           uncached = cacheable_decisions.where(was_cached: false).count
                           (uncached.to_f / cacheable_decisions.count * 100).round(2)
                         else
                           0.0
                         end

        # Estimate redundant context ratio
        # Look at large requests that could have been compressed
        large_requests = decisions.where("estimated_tokens > ?", 2000)
        compressed_large = large_requests.where(was_compressed: true)
        redundant_ratio = if large_requests.count > 0
                           uncompressed = large_requests.count - compressed_large.count
                           (uncompressed.to_f / large_requests.count * 100).round(2)
                         else
                           0.0
                         end

        # Estimate formatting overhead (tokens in tool/system vs user content)
        overhead_ratio = estimate_formatting_overhead(metrics)

        recommendations = generate_waste_recommendations(
          cache_miss_rate: cache_miss_rate,
          redundant_ratio: redundant_ratio,
          overhead_ratio: overhead_ratio,
          total_decisions: total_decisions
        )

        {
          redundant_context_ratio: redundant_ratio,
          verbose_formatting_overhead: overhead_ratio,
          cache_miss_rate: cache_miss_rate,
          compression_usage_rate: total_decisions > 0 ? (compressed_decisions.count.to_f / total_decisions * 100).round(2) : 0,
          cache_usage_rate: total_decisions > 0 ? (cached_decisions.count.to_f / total_decisions * 100).round(2) : 0,
          estimated_wasted_tokens: (total_tokens * (redundant_ratio / 100.0)).round(0),
          estimated_wasted_cost: (metrics.sum(:total_cost_usd).to_f * (redundant_ratio / 100.0)).round(4),
          recommendations: recommendations
        }
      end

      # ==========================================================================
      # FORECASTING
      # ==========================================================================

      # Forecast future token usage and costs.
      #
      # @param months [Integer] Number of months to forecast (default 3)
      # @return [Hash] Forecast with projections and trend analysis
      def forecast(months: DEFAULT_FORECAST_MONTHS)
        # Collect historical daily data for trend analysis
        daily_data = collect_daily_data(90.days.ago)

        return insufficient_data_response if daily_data.length < 7

        # Calculate trend
        tokens_trend = calculate_trend(daily_data.map { |d| d[:tokens] })
        cost_trend = calculate_trend(daily_data.map { |d| d[:cost] })

        avg_daily_tokens = daily_data.map { |d| d[:tokens] }.sum.to_f / daily_data.length
        avg_daily_cost = daily_data.map { |d| d[:cost] }.sum.to_f / daily_data.length

        projections = (1..months).map do |month|
          days = month * 30
          deflation = DEFLATION_FACTOR**month

          projected_daily_tokens = avg_daily_tokens + (tokens_trend * days / 2)
          projected_daily_cost = (avg_daily_cost + (cost_trend * days / 2)) * deflation

          {
            month: month,
            projected_tokens: (projected_daily_tokens * 30).round(0),
            projected_cost: (projected_daily_cost * 30).round(2),
            deflation_applied: deflation.round(4),
            confidence: month <= 1 ? "high" : (month <= 2 ? "medium" : "low")
          }
        end

        {
          based_on_days: daily_data.length,
          avg_daily_tokens: avg_daily_tokens.round(0),
          avg_daily_cost: avg_daily_cost.round(4),
          tokens_trend_per_day: tokens_trend.round(2),
          cost_trend_per_day: cost_trend.round(6),
          deflation_factor: DEFLATION_FACTOR,
          projections: projections
        }
      end

      # ==========================================================================
      # OPTIMIZATION SCORE
      # ==========================================================================

      # Calculate a composite optimization score (0-100).
      #
      # @return [Hash] Optimization score with breakdown
      def optimization_score
        waste = waste_analysis
        decisions = routing_decisions_for_period(30.days.ago)

        # Cache hit rate score (0-100)
        cache_score = [waste[:cache_usage_rate], 100].min

        # Tier utilization score: how well are we using appropriate tiers?
        tier_score = calculate_tier_utilization_score(decisions)

        # Waste ratio score: lower waste = higher score
        waste_ratio = waste[:redundant_context_ratio]
        waste_score = [(100 - waste_ratio), 0].max

        # Budget efficiency score
        budget_score = calculate_budget_efficiency_score

        # Weighted composite
        composite = (
          cache_score * OPTIMIZATION_WEIGHTS[:cache_hit_rate] +
          tier_score * OPTIMIZATION_WEIGHTS[:tier_utilization] +
          waste_score * OPTIMIZATION_WEIGHTS[:waste_ratio] +
          budget_score * OPTIMIZATION_WEIGHTS[:budget_efficiency]
        ).round(1)

        {
          score: composite,
          grade: score_to_grade(composite),
          breakdown: {
            cache_hit_rate: { score: cache_score.round(1), weight: OPTIMIZATION_WEIGHTS[:cache_hit_rate] },
            tier_utilization: { score: tier_score.round(1), weight: OPTIMIZATION_WEIGHTS[:tier_utilization] },
            waste_ratio: { score: waste_score.round(1), weight: OPTIMIZATION_WEIGHTS[:waste_ratio] },
            budget_efficiency: { score: budget_score.round(1), weight: OPTIMIZATION_WEIGHTS[:budget_efficiency] }
          },
          recommendations: generate_optimization_recommendations(
            cache_score: cache_score,
            tier_score: tier_score,
            waste_score: waste_score,
            budget_score: budget_score
          )
        }
      end

      private

      # ==========================================================================
      # DATA QUERIES
      # ==========================================================================

      def provider_metrics_for_period(start_time)
        Ai::ProviderMetric.for_account(account).where("recorded_at >= ?", start_time)
      end

      def routing_decisions_for_period(start_time)
        Ai::RoutingDecision.for_account(account).where("created_at >= ?", start_time)
      end

      def usage_by_model(metrics)
        model_data = {}

        metrics.pluck(:model_breakdown).each do |breakdown|
          next unless breakdown.is_a?(Hash)

          breakdown.each do |model_name, data|
            model_data[model_name] ||= { tokens: 0, cost: 0.0, requests: 0 }
            model_data[model_name][:tokens] += data["tokens"].to_i
            model_data[model_name][:cost] += data["cost"].to_f
            model_data[model_name][:requests] += data["requests"].to_i
          end
        end

        model_data.map do |model, data|
          {
            model: model,
            tokens: data[:tokens],
            cost: data[:cost].round(4),
            requests: data[:requests],
            tier: detect_tier(model)
          }
        end.sort_by { |m| -m[:tokens] }
      end

      def usage_by_tier(decisions)
        tier_counts = decisions.where.not(model_tier: nil).group(:model_tier).count
        tier_costs = decisions.where.not(model_tier: nil).group(:model_tier).sum(:actual_cost_usd)

        %w[economy standard premium].map do |tier|
          {
            tier: tier,
            request_count: tier_counts[tier] || 0,
            total_cost: (tier_costs[tier] || 0).to_f.round(4)
          }
        end
      end

      def daily_token_usage(start_time)
        Ai::ProviderMetric.for_account(account)
                          .where("recorded_at >= ?", start_time)
                          .by_granularity("day")
                          .order(:recorded_at)
                          .pluck(:recorded_at, :total_tokens, :total_cost_usd)
                          .map do |recorded_at, tokens, cost|
                            {
                              date: recorded_at.to_date.to_s,
                              tokens: tokens,
                              cost: cost.to_f.round(4)
                            }
                          end
      end

      def collect_daily_data(start_time)
        Ai::ProviderMetric.for_account(account)
                          .where("recorded_at >= ?", start_time)
                          .by_granularity("day")
                          .order(:recorded_at)
                          .pluck(:recorded_at, :total_tokens, :total_cost_usd)
                          .map do |recorded_at, tokens, cost|
                            { date: recorded_at.to_date, tokens: tokens, cost: cost.to_f }
                          end
      end

      # ==========================================================================
      # CALCULATION HELPERS
      # ==========================================================================

      def detect_tier(model_name)
        downcased = model_name.to_s.downcase
        MODEL_TIERS.each do |tier, patterns|
          return tier if patterns.any? { |p| downcased.include?(p) }
        end
        "standard"
      end

      def estimate_formatting_overhead(metrics)
        # Estimate based on ratio of input tokens to output tokens
        # High input:output ratio suggests verbose prompts/context
        total_input = metrics.sum(:total_input_tokens)
        total_output = metrics.sum(:total_output_tokens)

        return 0.0 if total_output.zero? || total_input.zero?

        ratio = total_input.to_f / total_output
        # Typical ratio is 2-3x; above 5x suggests overhead
        if ratio > 10
          25.0
        elsif ratio > 5
          15.0
        elsif ratio > 3
          5.0
        else
          0.0
        end
      end

      def calculate_trend(values)
        return 0.0 if values.length < 2

        n = values.length
        x_sum = (0...n).sum.to_f
        y_sum = values.sum.to_f
        xy_sum = values.each_with_index.sum { |y, x| x * y }.to_f
        x2_sum = (0...n).sum { |x| x * x }.to_f

        denominator = n * x2_sum - x_sum * x_sum
        return 0.0 if denominator.zero?

        (n * xy_sum - x_sum * y_sum) / denominator
      end

      def calculate_tier_utilization_score(decisions)
        # Check if assessments match actual tier usage
        assessments = Ai::TaskComplexityAssessment.for_account(account)
                                                   .where("created_at >= ?", 30.days.ago)
                                                   .where.not(actual_tier_used: nil)

        return 75.0 if assessments.count.zero? # Default score if no data

        matched = assessments.where("actual_tier_used = recommended_tier").count
        (matched.to_f / assessments.count * 100).round(1)
      end

      def calculate_budget_efficiency_score
        budgets = Ai::AgentBudget.where(account: account).active
        return 80.0 if budgets.empty? # Default if no budgets set

        # Average utilization - ideal is 60-80%
        avg_utilization = budgets.average("(spent_cents::float / NULLIF(total_budget_cents, 0)) * 100").to_f

        if avg_utilization.between?(50, 85)
          90.0
        elsif avg_utilization.between?(30, 50) || avg_utilization.between?(85, 95)
          70.0
        elsif avg_utilization < 30
          50.0 # Under-utilizing budget
        else
          40.0 # Over-budget
        end
      end

      def score_to_grade(score)
        case score
        when 90..100 then "A"
        when 80..89 then "B"
        when 70..79 then "C"
        when 60..69 then "D"
        else "F"
        end
      end

      # ==========================================================================
      # RECOMMENDATION GENERATORS
      # ==========================================================================

      def generate_waste_recommendations(cache_miss_rate:, redundant_ratio:, overhead_ratio:, total_decisions:)
        recs = []

        if cache_miss_rate > 30
          recs << {
            type: "caching",
            priority: "high",
            title: "Enable prefix caching",
            description: "#{cache_miss_rate}% cache miss rate detected. Enable prefix caching to reduce costs.",
            potential_savings: "up to 50% on repeated prompts"
          }
        end

        if redundant_ratio > 20
          recs << {
            type: "compression",
            priority: "high",
            title: "Enable context compression",
            description: "#{redundant_ratio}% of large requests lack compression. Enable context compression.",
            potential_savings: "20-40% token reduction on large contexts"
          }
        end

        if overhead_ratio > 10
          recs << {
            type: "prompt_optimization",
            priority: "medium",
            title: "Optimize prompt verbosity",
            description: "#{overhead_ratio}% estimated formatting overhead. Consider streamlining prompts.",
            potential_savings: "10-20% token reduction"
          }
        end

        if total_decisions > 100 && recs.empty?
          recs << {
            type: "general",
            priority: "low",
            title: "Token usage is well optimized",
            description: "No significant waste patterns detected.",
            potential_savings: "maintain current practices"
          }
        end

        recs
      end

      def generate_optimization_recommendations(cache_score:, tier_score:, waste_score:, budget_score:)
        recs = []

        if cache_score < 50
          recs << "Enable prefix caching to improve cache hit rate (currently #{cache_score.round(0)}%)"
        end

        if tier_score < 70
          recs << "Review tier assignments - #{(100 - tier_score).round(0)}% of tasks use non-optimal tiers"
        end

        if waste_score < 70
          recs << "Reduce context waste through compression and prompt optimization"
        end

        if budget_score < 60
          recs << "Adjust budget allocations for better utilization"
        end

        recs << "Overall optimization is good - maintain current practices" if recs.empty?

        recs
      end

      def insufficient_data_response
        {
          based_on_days: 0,
          avg_daily_tokens: 0,
          avg_daily_cost: 0,
          tokens_trend_per_day: 0,
          cost_trend_per_day: 0,
          deflation_factor: DEFLATION_FACTOR,
          projections: [],
          message: "Insufficient data for forecasting. Need at least 7 days of metrics."
        }
      end
    end
  end
end
