# frozen_string_literal: true

module CostOptimization
  module Initialization
    extend ActiveSupport::Concern

    included do
      attr_accessor :account, :time_range
    end

    def load_provider_costs
      costs = {}
      Ai::Provider.active.each do |provider|
        costs[provider.id] = provider_cost_per_token(provider)
      end
      costs
    end

    def initialize_usage_tracker
      {
        session_start: Time.current,
        requests_tracked: 0,
        total_cost: BigDecimal("0")
      }
    end

    def get_monthly_budget
      budget = @account.settings&.dig("monthly_ai_budget")
      budget ? BigDecimal(budget.to_s) : BigDecimal("100")
    end

    def provider_cost_per_token(provider)
      model_info = provider.supported_models&.first
      if model_info && model_info["cost_per_token"]
        BigDecimal(model_info["cost_per_token"].to_s)
      else
        case provider.provider_type
        when "openai" then BigDecimal("0.00002")
        when "anthropic" then BigDecimal("0.000025")
        when "ollama" then BigDecimal("0")
        else BigDecimal("0.00001")
        end
      end
    end

    def provider_quality_score(provider)
      case provider.provider_type
      when "openai" then 0.9
      when "anthropic" then 0.92
      when "ollama" then 0.75
      else 0.7
      end
    end

    def provider_avg_response_time(provider)
      recent_executions = @account.ai_agent_executions
                                  .where(provider: provider)
                                  .where(created_at: 7.days.ago..Time.current)

      avg = recent_executions.average(:duration_ms)
      avg&.to_i || (provider.provider_type == "ollama" ? 3000 : 2000)
    end

    def calculate_estimated_cost(cost_per_token, max_tokens, complexity)
      multiplier = case complexity
      when "simple" then 1.0
      when "medium" then 1.5
      when "complex" then 2.5
      else 1.5
      end

      (cost_per_token * max_tokens * multiplier).round(6)
    end

    def normalized_cost(cost)
      [ cost / BigDecimal("0.1"), BigDecimal("1") ].min.to_f
    end

    def base_executions_query
      @account.ai_agent_executions
              .joins(:agent, :provider)
              .where(created_at: @start_date..@end_date)
              .where.not(cost_usd: nil)
    end

    def cache_key
      Digest::MD5.hexdigest("#{@start_date.to_i}-#{@end_date.to_i}")
    end

    def calculate_efficiency_score(avg_cost, avg_response_time, success_rate)
      cost_score = [ 100 - (avg_cost * 1000), 0 ].max
      time_score = [ 100 - (avg_response_time / 100), 0 ].max
      success_score = success_rate

      (cost_score * 0.4 + time_score * 0.3 + success_score * 0.3).round(2)
    end

    def calculate_efficiency_score_from_metrics(cost_per_token, response_time, success_rate)
      cost_score = [ 1.0 - (cost_per_token.to_f * 10000), 0 ].max
      time_score = [ 1.0 - (response_time.to_f / 10000), 0 ].max
      (cost_score * 0.3 + time_score * 0.2 + success_rate * 0.5).round(2)
    end

    def calculate_provider_value_score(provider_metrics, weights)
      provider_metrics = provider_metrics.to_h.symbolize_keys
      weights = weights.to_h.symbolize_keys

      cost_score = 1.0 - [ provider_metrics[:cost_per_token].to_f * 10000, 1.0 ].min
      quality_score = provider_metrics[:quality_score].to_f
      speed_score = 1.0 - [ provider_metrics[:response_time_ms].to_f / 5000, 1.0 ].min
      reliability_score = provider_metrics[:reliability_score].to_f

      (cost_score * (weights[:cost] || 0.25) +
       quality_score * (weights[:quality] || 0.25) +
       speed_score * (weights[:speed] || 0.25) +
       reliability_score * (weights[:reliability] || 0.25)).round(3)
    end

    def estimate_monthly_cost(daily_usage)
      daily_usage = daily_usage.to_h.symbolize_keys
      requests = daily_usage[:requests] || 0
      avg_cost = daily_usage[:average_cost] || BigDecimal("0")

      BigDecimal((requests * avg_cost.to_f * 30).to_s)
    end
  end
end
