# Cost Attribution System

**AI cost tracking, budget management, and optimization**

---

## Table of Contents

1. [Overview](#overview)
2. [Cost Tracking](#cost-tracking)
3. [Budget Management](#budget-management)
4. [Cost Analysis](#cost-analysis)
5. [Recommendations](#recommendations)
6. [Provider Optimization](#provider-optimization)

---

## Overview

The Cost Attribution System provides comprehensive tracking, analysis, and optimization of AI operation costs across the platform.

### Service Structure

```
server/app/services/cost_optimization/
├── initialization.rb        # Service initialization
├── cost_tracking.rb         # Real-time cost tracking
├── cost_analysis.rb         # Cost analysis and reporting
├── budget_management.rb     # Budget tracking and alerts
├── recommendations.rb       # Cost optimization recommendations
├── provider_optimization.rb # Provider-level optimization
└── usage_patterns.rb        # Usage pattern analysis
```

### Key Features

- **Real-time tracking**: Track costs as operations execute
- **Budget management**: Set limits and receive alerts
- **Cost analysis**: Detailed breakdown by provider, model, user
- **Recommendations**: AI-driven cost optimization suggestions
- **Projections**: Monthly cost forecasting

---

## Cost Tracking

### Real-Time Cost Tracking

```ruby
module CostOptimization
  module CostTracking
    def track_real_time_costs
      current_cost = calculate_current_period_cost
      daily_cost = calculate_daily_cost
      monthly_projection = calculate_monthly_projection(daily_cost)

      {
        current_period_cost: current_cost,
        daily_cost: daily_cost,
        monthly_projection: monthly_projection,
        cost_trends: analyze_cost_trends,
        budget_status: analyze_budget_status(monthly_projection),
        alerts: generate_cost_alerts(current_cost, daily_cost, monthly_projection),
        last_updated: Time.current.iso8601
      }
    end
  end
end
```

### Starting Cost Tracking

```ruby
def start_cost_tracking(context)
  tracking_id = SecureRandom.uuid
  provider = Ai::Provider.find_by(id: context[:provider_id])
  cost_per_token = provider_cost_per_token(provider)

  estimated_cost = calculate_estimated_cost(
    cost_per_token,
    context[:estimated_tokens] || 1000,
    context[:complexity] || "medium"
  )

  # Check budget impact
  current_spending = @account.ai_agent_executions
                             .where(created_at: Time.current.beginning_of_month..Time.current)
                             .sum(:cost_usd)
  monthly_budget = get_monthly_budget

  budget_alerts = []
  if current_spending + estimated_cost > monthly_budget * 0.9
    budget_alerts << "This operation will exceed 90% of monthly budget"
  end

  {
    tracking_id: tracking_id,
    estimated_cost: estimated_cost,
    start_time: Time.current,
    budget_impact: ((estimated_cost / monthly_budget) * 100).round(2),
    budget_alerts: budget_alerts.presence
  }
end
```

### Updating Cost Tracking

```ruby
def update_cost_tracking(tracking_id, data)
  tracker = @cost_trackers[tracking_id]
  return nil unless tracker

  actual_tokens = data[:actual_tokens] || 0
  actual_cost = tracker[:estimated_cost] * (actual_tokens.to_f / 1000)

  tracker.merge(
    actual_tokens: actual_tokens,
    actual_cost: actual_cost,
    response_time_ms: data[:response_time_ms],
    end_time: Time.current
  )
end
```

---

## Budget Management

### Budget Status

```ruby
module CostOptimization
  module BudgetManagement
    def budget_status(start_date, end_date)
      monthly_budget = get_monthly_budget

      executions = @account.ai_agent_executions
                           .where(created_at: start_date..end_date)
                           .where.not(cost_usd: nil)

      current_spending = executions.sum(:cost_usd) || BigDecimal("0")
      remaining_budget = [monthly_budget - current_spending, BigDecimal("0")].max

      days_elapsed = [(end_date.to_date - start_date.to_date).to_i, 1].max
      daily_avg = current_spending / days_elapsed
      projected_monthly = daily_avg * 30

      utilization_percent = ((current_spending / monthly_budget) * 100).round(1)

      {
        budget_limit: monthly_budget,
        current_spending: current_spending,
        remaining_budget: remaining_budget,
        projected_monthly_cost: projected_monthly,
        budget_utilization_percent: utilization_percent,
        alerts: generate_budget_alerts(utilization_percent)
      }
    end
  end
end
```

### Budget Recommendations

```ruby
def generate_budget_recommendations(executions)
  current_monthly_cost = calculate_monthly_projection(calculate_daily_cost)

  budget_tiers = [
    { name: "Conservative", limit: current_monthly_cost * 0.8, savings_target: 20 },
    { name: "Moderate", limit: current_monthly_cost * 0.9, savings_target: 10 },
    { name: "Current", limit: current_monthly_cost, savings_target: 0 },
    { name: "Growth", limit: current_monthly_cost * 1.2, savings_target: -20 }
  ]

  {
    current_monthly_cost: current_monthly_cost.round(2),
    budget_recommendations: budget_tiers.map do |tier|
      {
        tier: tier[:name],
        monthly_limit: tier[:limit].round(2),
        savings_target_percentage: tier[:savings_target],
        actions_required: generate_budget_tier_actions(tier[:savings_target]),
        alert_threshold: (tier[:limit] * 0.8).round(2)
      }
    end,
    suggested_tier: determine_suggested_budget_tier(current_monthly_cost)
  }
end
```

### Budget Alerts

```ruby
def generate_budget_alerts(utilization_percent)
  alerts = []

  if utilization_percent > 100
    alerts << {
      level: "critical",
      message: "Budget exceeded by #{(utilization_percent - 100).round(1)}%"
    }
  elsif utilization_percent > 90
    alerts << {
      level: "warning",
      message: "Budget utilization at #{utilization_percent}% - approaching limit"
    }
  elsif utilization_percent > 80
    alerts << {
      level: "info",
      message: "Budget utilization at #{utilization_percent}%"
    }
  end

  alerts
end
```

---

## Cost Analysis

### Cost Breakdown

```ruby
module CostOptimization
  module CostAnalysis
    def cost_breakdown(start_date, end_date)
      executions = @account.ai_agent_executions
                           .where(created_at: start_date..end_date)
                           .includes(:ai_provider, :ai_agent, :user)

      {
        by_provider: group_costs_by_provider(executions),
        by_model: group_costs_by_model(executions),
        by_agent: group_costs_by_agent(executions),
        by_user: group_costs_by_user(executions),
        by_day: group_costs_by_day(executions),
        totals: calculate_totals(executions)
      }
    end

    def group_costs_by_provider(executions)
      executions.group(:ai_provider_id).sum(:cost_usd).transform_keys do |id|
        Ai::Provider.find(id).name rescue "Unknown"
      end
    end

    def group_costs_by_model(executions)
      executions.group("metadata->>'model'").sum(:cost_usd)
    end

    def group_costs_by_agent(executions)
      executions.group(:ai_agent_id).sum(:cost_usd).transform_keys do |id|
        Ai::Agent.find(id).name rescue "Unknown"
      end
    end

    def group_costs_by_day(executions)
      executions.group("DATE(created_at)").sum(:cost_usd)
    end
  end
end
```

### Cost Trends

```ruby
def analyze_cost_trends(period = 30.days)
  current_period = @account.ai_agent_executions
                           .where(created_at: period.ago..Time.current)
                           .sum(:cost_usd)

  previous_period = @account.ai_agent_executions
                            .where(created_at: (period * 2).ago..period.ago)
                            .sum(:cost_usd)

  change_percent = previous_period > 0 ?
    ((current_period - previous_period) / previous_period * 100).round(2) : 0

  {
    current_period_cost: current_period,
    previous_period_cost: previous_period,
    change_percent: change_percent,
    trend: change_percent > 0 ? "increasing" : "decreasing"
  }
end
```

---

## Recommendations

### Cost Optimization Recommendations

```ruby
module CostOptimization
  module Recommendations
    def generate_recommendations
      executions = @account.ai_agent_executions
                           .where(created_at: 30.days.ago..Time.current)

      recommendations = []

      # Provider optimization
      recommendations.concat(provider_recommendations(executions))

      # Model optimization
      recommendations.concat(model_recommendations(executions))

      # Usage pattern optimization
      recommendations.concat(usage_recommendations(executions))

      # Caching recommendations
      recommendations.concat(caching_recommendations(executions))

      recommendations.sort_by { |r| -r[:potential_savings] }
    end

    def provider_recommendations(executions)
      by_provider = executions.group(:ai_provider_id)
                              .select("ai_provider_id, SUM(cost_usd) as total_cost, AVG(cost_usd) as avg_cost")

      recommendations = []

      by_provider.each do |group|
        provider = Ai::Provider.find(group.ai_provider_id)
        cheaper_alternatives = find_cheaper_providers(provider, group.avg_cost)

        if cheaper_alternatives.any?
          recommendations << {
            type: "provider_switch",
            title: "Consider switching from #{provider.name}",
            description: "Alternative providers could save up to #{calculate_savings(group, cheaper_alternatives)}%",
            potential_savings: calculate_potential_savings(group, cheaper_alternatives),
            priority: "high"
          }
        end
      end

      recommendations
    end
  end
end
```

### Caching Recommendations

```ruby
def caching_recommendations(executions)
  # Find repeated similar requests
  similar_requests = find_similar_requests(executions)

  recommendations = []

  if similar_requests.count > 10
    estimated_savings = similar_requests.sum(:cost_usd) * 0.8

    recommendations << {
      type: "enable_caching",
      title: "Enable response caching",
      description: "#{similar_requests.count} similar requests detected. Caching could save significant costs.",
      potential_savings: estimated_savings,
      priority: "medium"
    }
  end

  recommendations
end
```

---

## Provider Optimization

### Provider Cost Comparison

```ruby
module CostOptimization
  module ProviderOptimization
    def compare_providers
      providers = @account.ai_providers.active

      providers.map do |provider|
        executions = @account.ai_agent_executions
                             .where(ai_provider_id: provider.id)
                             .where(created_at: 30.days.ago..Time.current)

        {
          provider_id: provider.id,
          provider_name: provider.name,
          total_cost: executions.sum(:cost_usd),
          total_executions: executions.count,
          avg_cost_per_execution: executions.average(:cost_usd),
          avg_tokens_per_execution: executions.average(:tokens_used),
          avg_response_time_ms: executions.average("(metadata->>'processing_time_ms')::integer"),
          success_rate: calculate_success_rate(executions),
          cost_efficiency_score: calculate_cost_efficiency(provider, executions)
        }
      end.sort_by { |p| -p[:cost_efficiency_score] }
    end

    def calculate_cost_efficiency(provider, executions)
      return 0 if executions.count == 0

      avg_cost = executions.average(:cost_usd) || 0
      success_rate = calculate_success_rate(executions)
      avg_response_time = executions.average("(metadata->>'processing_time_ms')::integer") || 1000

      # Higher is better
      (success_rate * 0.5) / (avg_cost * 0.3 + avg_response_time / 10000 * 0.2)
    end
  end
end
```

### Optimization Actions

```ruby
def suggest_provider_actions
  comparison = compare_providers

  actions = []

  # Identify underperforming providers
  comparison.each do |provider_stats|
    if provider_stats[:success_rate] < 95
      actions << {
        action: "review_provider",
        provider_id: provider_stats[:provider_id],
        reason: "Success rate below 95%",
        current_value: provider_stats[:success_rate]
      }
    end

    if provider_stats[:cost_efficiency_score] < comparison.map { |p| p[:cost_efficiency_score] }.average * 0.8
      actions << {
        action: "consider_alternative",
        provider_id: provider_stats[:provider_id],
        reason: "Below average cost efficiency",
        potential_alternatives: find_better_alternatives(provider_stats)
      }
    end
  end

  actions
end
```

---

## Usage Examples

### Get Cost Dashboard Data

```ruby
service = CostOptimization::Service.new(account: current_account)

dashboard = {
  real_time: service.track_real_time_costs,
  budget: service.budget_status(
    Time.current.beginning_of_month,
    Time.current
  ),
  breakdown: service.cost_breakdown(30.days.ago, Time.current),
  recommendations: service.generate_recommendations,
  providers: service.compare_providers
}
```

### Track Operation Cost

```ruby
service = CostOptimization::Service.new(account: current_account)

# Start tracking
tracker = service.start_cost_tracking(
  provider_id: provider.id,
  estimated_tokens: 1500,
  complexity: "high"
)

# Check budget impact before proceeding
if tracker[:budget_alerts].present?
  Rails.logger.warn "Budget alert: #{tracker[:budget_alerts].join(', ')}"
end

# After operation completes
service.update_cost_tracking(tracker[:tracking_id], {
  actual_tokens: 1450,
  response_time_ms: 2500
})
```

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `server/app/services/cost_optimization/`
