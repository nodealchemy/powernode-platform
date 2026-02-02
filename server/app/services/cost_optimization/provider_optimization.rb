# frozen_string_literal: true

module CostOptimization
  module ProviderOptimization
    def recommend_provider(requirements)
      requirements = requirements.to_h.symbolize_keys
      budget_priority = requirements[:budget_priority] || "balanced"
      complexity = requirements[:complexity] || "medium"
      max_tokens = requirements[:max_tokens] || 500
      quality_threshold = requirements[:quality_threshold] || 0.8
      max_cost = requirements[:max_cost]
      max_response_time_ms = requirements[:max_response_time_ms]

      credentials = @account.ai_provider_credentials.includes(:provider).active
      return empty_recommendation if credentials.empty?

      scored_providers = credentials.map do |cred|
        provider = cred.provider
        cost_per_token = provider_cost_per_token(provider)
        estimated_cost = calculate_estimated_cost(cost_per_token, max_tokens, complexity)
        quality_score = provider_quality_score(provider)
        response_time = provider_avg_response_time(provider)

        value_score = case budget_priority
        when "cost_optimized"
          (1.0 - normalized_cost(estimated_cost)) * 0.7 + quality_score * 0.3
        when "quality_first"
          quality_score * 0.9 + (estimated_cost > 0 ? 0.1 : 0)
        else
          base_score = (1.0 - normalized_cost(estimated_cost)) * 0.4 + quality_score * 0.6
          estimated_cost > 0 ? base_score : base_score * 0.5
        end

        {
          provider: provider,
          credential: cred,
          estimated_cost: estimated_cost,
          quality_score: quality_score,
          response_time: response_time,
          value_score: value_score
        }
      end

      if budget_priority == "quality_first"
        scored_providers = scored_providers.select { |p| p[:quality_score] >= quality_threshold * 0.95 }
      end

      if max_cost
        scored_providers = scored_providers.select { |p| p[:estimated_cost] <= max_cost }
      end

      if max_response_time_ms
        scored_providers = scored_providers.select { |p| p[:response_time] <= max_response_time_ms * 1.5 }
      end

      scored_providers.sort_by! { |p| -p[:value_score] }

      warnings = []
      paid_providers_before = credentials.select { |cred| provider_cost_per_token(cred.provider) > 0 }
      paid_providers_remaining = scored_providers.select { |p| p[:estimated_cost] > 0 }

      if max_cost && paid_providers_before.any? && paid_providers_remaining.empty?
        warnings << "Budget insufficient for requested task complexity"
      end

      if scored_providers.empty? && max_cost
        scored_providers = credentials.map do |cred|
          provider = cred.provider
          {
            provider: provider,
            credential: cred,
            estimated_cost: calculate_estimated_cost(provider_cost_per_token(provider), max_tokens, complexity),
            quality_score: provider_quality_score(provider),
            response_time: provider_avg_response_time(provider),
            value_score: 0.5
          }
        end.sort_by { |p| p[:estimated_cost] }
      end

      best = scored_providers.first
      return empty_recommendation if best.nil?

      alternatives = scored_providers.drop(1).first(3).map do |alt|
        {
          provider_id: alt[:provider].id,
          estimated_cost: alt[:estimated_cost],
          trade_offs: generate_trade_offs(best, alt)
        }
      end

      result = {
        provider_id: best[:provider].id,
        estimated_cost: best[:estimated_cost],
        confidence_score: best[:value_score],
        reasoning: generate_recommendation_reasoning(best, budget_priority),
        alternative_options: alternatives,
        estimated_response_time_ms: best[:response_time]
      }
      result[:warnings] = warnings if warnings.any?
      result
    end

    def cost_comparison(requirements)
      requirements = requirements.to_h.symbolize_keys
      estimated_tokens = requirements[:estimated_tokens] || 1000
      monthly_volume = requirements[:monthly_volume] || 1000
      quality_weight = requirements[:quality_weight] || 0.5
      cost_weight = requirements[:cost_weight] || 0.5

      providers = Ai::Provider.active

      comparisons = providers.map do |provider|
        cost_per_token = provider_cost_per_token(provider)
        cost_per_request = cost_per_token * estimated_tokens
        monthly_cost = cost_per_request * monthly_volume
        quality_score = provider_quality_score(provider)

        normalized_monthly_cost = monthly_cost > 0 ? [ 1.0 - (monthly_cost / 1000.0), 0 ].max : 1.0
        value_score = (normalized_monthly_cost * cost_weight + quality_score * quality_weight).round(3)

        {
          provider_name: provider.name,
          cost_per_request: cost_per_request.round(6),
          monthly_cost: monthly_cost.round(2),
          cost_rank: 0,
          value_score: value_score
        }
      end

      comparisons.sort_by! { |c| c[:monthly_cost] }
      comparisons.each_with_index { |c, i| c[:cost_rank] = i + 1 }

      comparisons
    end

    def optimize_provider_selection(workload_profile)
      workload_profile = workload_profile.to_h.symbolize_keys
      simple_pct = workload_profile[:simple_tasks] || 50
      medium_pct = workload_profile[:medium_tasks] || 30
      complex_pct = workload_profile[:complex_tasks] || 20
      monthly_budget = workload_profile[:monthly_budget] || BigDecimal("100")

      credentials = @account.ai_provider_credentials.includes(:provider).active

      recommended_mix = {}
      total_weight = 0.0

      credentials.each do |cred|
        provider = cred.provider
        cost = provider_cost_per_token(provider)
        quality = provider_quality_score(provider)

        weight = (1.0 - normalized_cost(cost * 1000)) * 0.5 + quality * 0.5
        recommended_mix[provider.name] = weight
        total_weight += weight
      end

      recommended_mix.transform_values! { |w| (w / total_weight).round(3) } if total_weight > 0

      projected_cost = calculate_projected_cost_from_mix(recommended_mix, simple_pct, medium_pct, complex_pct)
      current_cost = calculate_current_cost_projection

      {
        recommended_mix: recommended_mix,
        projected_cost: [ projected_cost, monthly_budget ].min,
        projected_savings: [ current_cost - projected_cost, BigDecimal("0") ].max,
        risk_assessment: {
          quality_risk: recommended_mix.values.max < 0.5 ? "low" : "medium",
          availability_risk: credentials.size < 2 ? "high" : "low",
          vendor_lock_in_risk: recommended_mix.values.max > 0.7 ? "high" : "low"
        }
      }
    end

    def analyze_provider_cost_efficiency(executions)
      provider_efficiency = {}

      executions.group_by(&:provider).each do |provider, provider_executions|
        costs = provider_executions.map(&:cost_usd).compact
        response_times = provider_executions.map(&:duration_ms).compact
        success_count = provider_executions.count { |e| e.status == "completed" }

        next if costs.empty? || response_times.empty?

        avg_cost = costs.sum / costs.size
        avg_response_time = response_times.sum / response_times.size
        success_rate = (success_count.to_f / provider_executions.size * 100)

        efficiency_score = calculate_efficiency_score(avg_cost, avg_response_time, success_rate)

        provider_efficiency[provider.name] = {
          avg_cost: avg_cost.round(6),
          avg_response_time: avg_response_time.round(0),
          success_rate: success_rate.round(2),
          efficiency_score: efficiency_score,
          execution_count: provider_executions.size,
          total_cost: costs.sum.round(4)
        }
      end

      best_provider = provider_efficiency.max_by { |_, data| data[:efficiency_score] }
      worst_provider = provider_efficiency.min_by { |_, data| data[:efficiency_score] }

      recommendations = []
      if best_provider && worst_provider && best_provider != worst_provider
        potential_savings = calculate_provider_switching_savings(
          worst_provider[1][:avg_cost],
          best_provider[1][:avg_cost],
          worst_provider[1][:execution_count]
        )

        if potential_savings > 1.0
          recommendations << {
            type: "provider_switch",
            description: "Switch from #{worst_provider[0]} to #{best_provider[0]}",
            estimated_monthly_savings: potential_savings,
            confidence: calculate_recommendation_confidence(worst_provider[1][:execution_count])
          }
        end
      end

      {
        provider_efficiency: provider_efficiency,
        recommendations: recommendations
      }
    end

    private

    def empty_recommendation
      {
        provider_id: nil,
        estimated_cost: BigDecimal("0"),
        confidence_score: 0,
        reasoning: "No providers available",
        alternative_options: [],
        warnings: [ "No active provider credentials found" ],
        estimated_response_time_ms: 0
      }
    end

    def generate_trade_offs(best, alt)
      trade_offs = []
      if alt[:estimated_cost] < best[:estimated_cost]
        trade_offs << "Lower cost by #{((1 - alt[:estimated_cost] / best[:estimated_cost]) * 100).round}%"
      end
      if alt[:quality_score] > best[:quality_score]
        trade_offs << "Higher quality score"
      end
      if alt[:response_time] < best[:response_time]
        trade_offs << "Faster response time"
      end
      trade_offs.join(", ").presence || "No significant trade-offs"
    end

    def generate_recommendation_reasoning(provider_data, budget_priority)
      provider = provider_data[:provider]
      reasons = []

      case budget_priority
      when "cost_optimized"
        reasons << "Selected for lowest cost optimization"
        reasons << "Estimated cost: $#{provider_data[:estimated_cost].round(4)}"
      when "quality_first"
        reasons << "Selected for highest quality score (#{(provider_data[:quality_score] * 100).round}%)"
      else
        reasons << "Balanced selection for cost and quality"
      end

      if provider.provider_type == "ollama"
        reasons << "Local model - no API costs"
      end

      reasons.join(". ")
    end

    def calculate_projected_cost_from_mix(mix, simple_pct, medium_pct, complex_pct)
      base_cost = BigDecimal("50")
      (base_cost * (simple_pct / 100.0) * 0.5 +
       base_cost * (medium_pct / 100.0) * 1.0 +
       base_cost * (complex_pct / 100.0) * 2.0).round(2)
    end

    def calculate_current_cost_projection
      daily_cost = calculate_daily_cost
      daily_cost * 30
    end

    def calculate_provider_switching_savings(old_cost, new_cost, execution_count)
      return 0 if old_cost <= new_cost

      savings_per_execution = old_cost - new_cost
      monthly_executions = execution_count * (30.0 / @time_range.to_i.days)
      monthly_executions * savings_per_execution
    end

    def calculate_recommendation_confidence(execution_count)
      execution_count > 10 ? "high" : "medium"
    end
  end
end
