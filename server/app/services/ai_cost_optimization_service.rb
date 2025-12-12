# frozen_string_literal: true

class AiCostOptimizationService
  include ActiveModel::Model
  include ActiveModel::Attributes

  class OptimizationError < StandardError; end

  attr_accessor :account, :time_range

  def initialize(account:, time_range: 30.days)
    @account = account
    @time_range = time_range
    @start_date = time_range.ago
    @end_date = Time.current
    @logger = Rails.logger
    @provider_costs = load_provider_costs
    @usage_tracker = initialize_usage_tracker
    @cost_trackers = {}
  end

  # Generate comprehensive cost optimization recommendations
  def generate_cost_optimization_plan
    @logger.info "Generating cost optimization plan for account #{@account.id}"

    executions = base_executions_query

    optimization_plan = {
      current_cost_analysis: analyze_current_costs(executions),
      provider_optimization: analyze_provider_cost_efficiency(executions),
      usage_pattern_optimization: analyze_usage_pattern_savings(executions),
      agent_optimization: analyze_agent_cost_efficiency(executions),
      budget_optimization: generate_budget_recommendations(executions),
      automated_optimization: generate_automation_recommendations(executions),
      projected_savings: calculate_projected_savings(executions),
      implementation_roadmap: generate_implementation_roadmap,
      cost_alerts: setup_cost_alert_recommendations
    }

    # Cache optimization plan
    Rails.cache.write(
      "ai_cost_optimization:#{@account.id}:#{cache_key}",
      optimization_plan,
      expires_in: 6.hours
    )

    optimization_plan
  end

  # Real-time cost tracking and alerts
  def track_real_time_costs
    current_cost = calculate_current_period_cost
    daily_cost = calculate_daily_cost
    monthly_projection = calculate_monthly_projection(daily_cost)

    cost_trends = analyze_cost_trends
    budget_status = analyze_budget_status(monthly_projection)

    # Generate alerts if necessary
    alerts = generate_cost_alerts(current_cost, daily_cost, monthly_projection)

    {
      current_period_cost: current_cost,
      daily_cost: daily_cost,
      monthly_projection: monthly_projection,
      cost_trends: cost_trends,
      budget_status: budget_status,
      alerts: alerts,
      last_updated: Time.current.iso8601
    }
  end

  # Apply automatic cost optimizations
  def apply_automatic_optimizations(optimization_settings = {})
    @logger.info "Applying automatic cost optimizations for account #{@account.id}"

    results = {
      provider_switching: apply_provider_switching_optimization(optimization_settings),
      usage_scheduling: apply_usage_scheduling_optimization(optimization_settings),
      resource_limits: apply_resource_limit_optimization(optimization_settings),
      cache_optimization: apply_cache_optimization(optimization_settings),
      applied_optimizations: [],
      estimated_monthly_savings: 0.0
    }

    # Calculate total savings
    results[:estimated_monthly_savings] = results.values
      .select { |v| v.is_a?(Hash) && v[:estimated_monthly_savings] }
      .sum { |v| v[:estimated_monthly_savings] }

    # Log optimization results
    @logger.info "Applied cost optimizations with estimated monthly savings: $#{results[:estimated_monthly_savings]}"

    results
  end

  # Recommend optimal provider for given task requirements
  def recommend_provider(requirements)
    requirements = requirements.to_h.symbolize_keys
    budget_priority = requirements[:budget_priority] || "balanced"
    complexity = requirements[:complexity] || "medium"
    max_tokens = requirements[:max_tokens] || 500
    quality_threshold = requirements[:quality_threshold] || 0.8
    max_cost = requirements[:max_cost]
    max_response_time_ms = requirements[:max_response_time_ms]

    # Get available providers via credentials
    credentials = @account.ai_provider_credentials.includes(:ai_provider).active
    return empty_recommendation if credentials.empty?

    # Score each provider
    scored_providers = credentials.map do |cred|
      provider = cred.ai_provider
      cost_per_token = provider_cost_per_token(provider)
      estimated_cost = calculate_estimated_cost(cost_per_token, max_tokens, complexity)
      quality_score = provider_quality_score(provider)
      response_time = provider_avg_response_time(provider)

      # Apply budget priority weighting
      value_score = case budget_priority
      when "cost_optimized"
                      (1.0 - normalized_cost(estimated_cost)) * 0.7 + quality_score * 0.3
      when "quality_first"
                      # For quality_first, heavily weight quality and only consider paid providers
                      quality_score * 0.9 + (estimated_cost > 0 ? 0.1 : 0)
      else
                      # For balanced, prefer paid providers with a slight bias toward quality
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

    # Filter by quality threshold for quality_first mode
    if budget_priority == "quality_first"
      scored_providers = scored_providers.select { |p| p[:quality_score] >= quality_threshold * 0.95 }
    end

    # Filter by max_cost constraint
    if max_cost
      scored_providers = scored_providers.select { |p| p[:estimated_cost] <= max_cost }
    end

    # Filter by max_response_time constraint
    if max_response_time_ms
      scored_providers = scored_providers.select { |p| p[:response_time] <= max_response_time_ms * 1.5 }
    end

    # Sort by value score
    scored_providers.sort_by! { |p| -p[:value_score] }

    # Check if budget is insufficient
    warnings = []

    # Check for paid providers before filtering
    paid_providers_before = credentials.select do |cred|
      provider_cost_per_token(cred.ai_provider) > 0
    end

    # Check for paid providers after filtering
    paid_providers_remaining = scored_providers.select { |p| p[:estimated_cost] > 0 }

    # Warn if we had paid providers but none can meet the budget
    if max_cost && paid_providers_before.any? && paid_providers_remaining.empty?
      warnings << "Budget insufficient for requested task complexity"
    end

    if scored_providers.empty? && max_cost
      # All providers were filtered out, re-populate with lowest cost options
      scored_providers = credentials.map do |cred|
        provider = cred.ai_provider
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

  # Analyze usage patterns over a time period
  def analyze_usage_patterns(time_period)
    start_date = time_period.ago
    executions = @account.ai_agent_executions
                         .where(created_at: start_date..Time.current)
                         .where.not(cost_usd: nil)

    total_cost = executions.sum(:cost_usd) || BigDecimal("0")
    total_tokens = executions.sum(:tokens_used) || 0

    # Cost breakdown by provider
    provider_costs = {}
    executions.joins(:ai_provider).group("ai_providers.name").sum(:cost_usd).each do |name, cost|
      provider_costs[name] = BigDecimal(cost.to_s)
    end

    # Usage trend calculation
    mid_point = start_date + (time_period / 2)
    first_half_cost = executions.where(created_at: start_date..mid_point).sum(:cost_usd) || 0
    second_half_cost = executions.where(created_at: mid_point..Time.current).sum(:cost_usd) || 0

    usage_trend = if second_half_cost > first_half_cost * 1.1
                    "increasing"
    elsif second_half_cost < first_half_cost * 0.9
                    "decreasing"
    else
                    "stable"
    end

    # Efficiency metrics
    avg_cost_per_token = total_tokens > 0 ? total_cost / total_tokens : BigDecimal("0")
    avg_response_time = executions.average(:duration_ms)&.to_i || 0
    success_count = executions.where(status: "completed").count
    total_count = executions.count
    success_rate = total_count > 0 ? (success_count.to_f / total_count) : 0.0

    # Optimization opportunities
    opportunities = []
    if usage_trend == "increasing" && total_cost > 10
      opportunities << {
        type: "cost_reduction",
        description: "Usage is increasing - consider implementing caching or batch processing",
        potential_savings: BigDecimal((total_cost * 0.15).to_s)
      }
    end

    {
      total_cost: total_cost,
      total_tokens: total_tokens,
      average_cost_per_token: avg_cost_per_token,
      usage_trend: usage_trend,
      cost_breakdown_by_provider: provider_costs,
      optimization_opportunities: opportunities,
      efficiency_metrics: {
        tokens_per_dollar: total_cost > 0 ? (total_tokens / total_cost).to_i : 0,
        average_response_time: avg_response_time,
        success_rate: success_rate,
        cost_efficiency_score: calculate_efficiency_score_from_metrics(avg_cost_per_token, avg_response_time, success_rate)
      }
    }
  end

  # Optimize provider selection based on workload profile
  def optimize_provider_selection(workload_profile)
    workload_profile = workload_profile.to_h.symbolize_keys
    simple_pct = workload_profile[:simple_tasks] || 50
    medium_pct = workload_profile[:medium_tasks] || 30
    complex_pct = workload_profile[:complex_tasks] || 20
    monthly_budget = workload_profile[:monthly_budget] || BigDecimal("100")

    credentials = @account.ai_provider_credentials.includes(:ai_provider).active

    # Calculate optimal mix
    recommended_mix = {}
    total_weight = 0.0

    credentials.each do |cred|
      provider = cred.ai_provider
      cost = provider_cost_per_token(provider)
      quality = provider_quality_score(provider)

      # Weight based on cost efficiency and quality
      weight = (1.0 - normalized_cost(cost * 1000)) * 0.5 + quality * 0.5
      recommended_mix[provider.name] = weight
      total_weight += weight
    end

    # Normalize to percentages
    recommended_mix.transform_values! { |w| (w / total_weight).round(3) } if total_weight > 0

    # Calculate projected costs
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

  # Get budget status for date range
  def budget_status(start_date, end_date)
    monthly_budget = get_monthly_budget

    executions = @account.ai_agent_executions
                         .where(created_at: start_date..end_date)
                         .where.not(cost_usd: nil)

    current_spending = executions.sum(:cost_usd) || BigDecimal("0")
    remaining_budget = [ monthly_budget - current_spending, BigDecimal("0") ].max

    days_elapsed = [ (end_date.to_date - start_date.to_date).to_i, 1 ].max
    days_in_period = [ (end_date.to_date - start_date.to_date).to_i, 1 ].max
    daily_avg = current_spending / days_elapsed
    projected_monthly = daily_avg * 30

    utilization_percent = monthly_budget > 0 ? ((current_spending / monthly_budget) * 100).round(1) : 0

    alerts = []
    if utilization_percent > 80
      alerts << "Budget utilization at #{utilization_percent}% - approaching limit"
    end

    {
      budget_limit: monthly_budget,
      current_spending: current_spending,
      remaining_budget: remaining_budget,
      projected_monthly_cost: projected_monthly,
      budget_utilization_percent: utilization_percent,
      alerts: alerts
    }
  end

  # Compare costs across providers
  def cost_comparison(requirements)
    requirements = requirements.to_h.symbolize_keys
    estimated_tokens = requirements[:estimated_tokens] || 1000
    monthly_volume = requirements[:monthly_volume] || 1000
    quality_weight = requirements[:quality_weight] || 0.5
    cost_weight = requirements[:cost_weight] || 0.5

    providers = AiProvider.active

    comparisons = providers.map do |provider|
      cost_per_token = provider_cost_per_token(provider)
      cost_per_request = cost_per_token * estimated_tokens
      monthly_cost = cost_per_request * monthly_volume
      quality_score = provider_quality_score(provider)

      # Value score based on weights
      normalized_monthly_cost = monthly_cost > 0 ? [ 1.0 - (monthly_cost / 1000.0), 0 ].max : 1.0
      value_score = (normalized_monthly_cost * cost_weight + quality_score * quality_weight).round(3)

      {
        provider_name: provider.name,
        cost_per_request: cost_per_request.round(6),
        monthly_cost: monthly_cost.round(2),
        cost_rank: 0, # Will be set after sorting
        value_score: value_score
      }
    end

    # Sort by monthly cost and assign ranks
    comparisons.sort_by! { |c| c[:monthly_cost] }
    comparisons.each_with_index { |c, i| c[:cost_rank] = i + 1 }

    comparisons
  end

  # Generate comprehensive cost report
  def generate_cost_report(time_period)
    start_date = time_period.ago
    executions = @account.ai_agent_executions
                         .where(created_at: start_date..Time.current)
                         .where.not(cost_usd: nil)

    total_cost = executions.sum(:cost_usd) || BigDecimal("0")
    total_requests = executions.count
    avg_cost = total_requests > 0 ? total_cost / total_requests : BigDecimal("0")

    # Cost change vs previous period
    prev_start = (time_period * 2).ago
    prev_end = time_period.ago
    prev_cost = @account.ai_agent_executions
                        .where(created_at: prev_start..prev_end)
                        .where.not(cost_usd: nil)
                        .sum(:cost_usd) || BigDecimal("0")

    cost_change_pct = prev_cost > 0 ? (((total_cost - prev_cost) / prev_cost) * 100).round(1) : 0

    # Top cost driver
    top_driver = executions.joins(:ai_provider)
                           .group("ai_providers.name")
                           .sum(:cost_usd)
                           .max_by { |_, cost| cost }
    top_cost_driver = top_driver&.first || "None"

    # Forecast
    daily_avg = total_cost / [ time_period.to_i / 86400, 1 ].max
    next_month_projection = daily_avg * 30

    {
      executive_summary: {
        total_cost: total_cost,
        total_requests: total_requests,
        average_cost_per_request: avg_cost,
        cost_change_percentage: cost_change_pct,
        top_cost_driver: top_cost_driver
      },
      detailed_breakdown: analyze_current_costs(executions),
      trends_analysis: {
        direction: cost_change_pct > 5 ? "increasing" : (cost_change_pct < -5 ? "decreasing" : "stable"),
        daily_average: daily_avg
      },
      optimization_recommendations: generate_report_recommendations(total_cost, cost_change_pct),
      forecast: {
        next_month_projected_cost: next_month_projection,
        confidence_interval: { low: next_month_projection * 0.8, high: next_month_projection * 1.2 },
        key_assumptions: [ "Based on current usage patterns", "Assumes no major changes in workload" ]
      }
    }
  end

  # Start real-time cost tracking for an execution
  def start_cost_tracking(context)
    context = context.to_h.symbolize_keys
    tracking_id = SecureRandom.uuid
    provider_id = context[:provider_id]
    estimated_tokens = context[:estimated_tokens] || 1000
    complexity = context[:complexity] || "medium"

    provider = AiProvider.find_by(id: provider_id)
    cost_per_token = provider ? provider_cost_per_token(provider) : BigDecimal("0.0001")
    estimated_cost = calculate_estimated_cost(cost_per_token, estimated_tokens, complexity)

    # Check budget impact
    current_spending = @account.ai_agent_executions
                               .where(created_at: Time.current.beginning_of_month..Time.current)
                               .sum(:cost_usd) || BigDecimal("0")
    monthly_budget = get_monthly_budget

    budget_impact = ((estimated_cost / monthly_budget) * 100).round(2)

    budget_alerts = []
    if current_spending + estimated_cost > monthly_budget * 0.9
      budget_alerts << "This operation will exceed 90% of monthly budget"
    end

    tracker = {
      tracking_id: tracking_id,
      estimated_cost: estimated_cost,
      start_time: Time.current,
      budget_impact: budget_impact,
      budget_alerts: budget_alerts.presence
    }

    @cost_trackers[tracking_id] = tracker
    tracker
  end

  # Update cost tracking with actual data
  def update_cost_tracking(tracking_id, data)
    data = data.to_h.symbolize_keys
    tracker = @cost_trackers[tracking_id]
    return nil unless tracker

    actual_tokens = data[:actual_tokens] || 0
    response_time_ms = data[:response_time_ms] || 0

    # Recalculate actual cost
    actual_cost = tracker[:estimated_cost] * (actual_tokens.to_f / 1000)

    tracker.merge(
      actual_tokens: actual_tokens,
      actual_cost: actual_cost,
      response_time_ms: response_time_ms,
      end_time: Time.current
    )
  end

  private

  def load_provider_costs
    costs = {}
    AiProvider.active.each do |provider|
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
    # Try to get from account settings, fallback to default
    budget = @account.settings&.dig("monthly_ai_budget")
    budget ? BigDecimal(budget.to_s) : BigDecimal("100")
  end

  def provider_cost_per_token(provider)
    # Get cost from provider's supported_models or use defaults
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
                                .where(ai_provider: provider)
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
    # Normalize cost to 0-1 range (assuming max reasonable cost of $0.10 per request)
    [ cost / BigDecimal("0.1"), BigDecimal("1") ].min.to_f
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

  def calculate_efficiency_score_from_metrics(cost_per_token, response_time, success_rate)
    cost_score = [ 1.0 - (cost_per_token.to_f * 10000), 0 ].max
    time_score = [ 1.0 - (response_time.to_f / 10000), 0 ].max
    (cost_score * 0.3 + time_score * 0.2 + success_rate * 0.5).round(2)
  end

  def calculate_projected_cost_from_mix(mix, simple_pct, medium_pct, complex_pct)
    # Simplified projection
    base_cost = BigDecimal("50")
    (base_cost * (simple_pct / 100.0) * 0.5 +
     base_cost * (medium_pct / 100.0) * 1.0 +
     base_cost * (complex_pct / 100.0) * 2.0).round(2)
  end

  def calculate_current_cost_projection
    daily_cost = calculate_daily_cost
    daily_cost * 30
  end

  def generate_report_recommendations(total_cost, cost_change_pct)
    recommendations = []

    if cost_change_pct > 20
      recommendations << {
        priority: "high",
        description: "Costs increasing significantly - review usage patterns",
        estimated_savings: BigDecimal((total_cost * 0.15).to_s),
        implementation_effort: "medium"
      }
    end

    if total_cost > 50
      recommendations << {
        priority: "medium",
        description: "Consider implementing request caching for repeated queries",
        estimated_savings: BigDecimal((total_cost * 0.1).to_s),
        implementation_effort: "low"
      }
    end

    recommendations
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

  def base_executions_query
    @account.ai_agent_executions
            .joins(:ai_agent, :ai_provider)
            .where(created_at: @start_date..@end_date)
            .where.not(cost_usd: nil)
  end

  def analyze_current_costs(executions)
    total_cost = executions.sum(&:cost_usd) || 0.0
    execution_count = executions.count
    avg_cost_per_execution = execution_count > 0 ? total_cost / execution_count : 0.0

    # Cost breakdown by provider
    provider_costs = executions.group_by(&:ai_provider)
                              .transform_values { |execs| execs.sum(&:cost_usd) }
                              .sort_by { |_, cost| -cost }

    # Cost breakdown by agent type
    agent_type_costs = executions.joins(:ai_agent)
                                 .group("ai_agents.agent_type")
                                 .sum(:cost_usd)

    # Daily cost trend
    daily_costs = executions.group_by { |e| e.created_at.to_date }
                           .transform_values { |execs| execs.sum(&:cost_usd) }

    {
      total_cost: total_cost.round(4),
      execution_count: execution_count,
      avg_cost_per_execution: avg_cost_per_execution.round(6),
      provider_breakdown: provider_costs.map { |provider, cost|
        {
          provider: provider.name,
          cost: cost.round(4),
          percentage: ((cost / total_cost) * 100).round(2)
        }
      },
      agent_type_breakdown: agent_type_costs.map { |type, cost|
        {
          agent_type: type,
          cost: cost.round(4),
          percentage: ((cost / total_cost) * 100).round(2)
        }
      },
      daily_trend: daily_costs.transform_values { |cost| cost.round(4) }
    }
  end

  def analyze_provider_cost_efficiency(executions)
    provider_efficiency = {}

    executions.group_by(&:ai_provider).each do |provider, provider_executions|
      costs = provider_executions.map(&:cost_usd).compact
      response_times = provider_executions.map(&:duration_ms).compact
      success_count = provider_executions.count { |e| e.status == "completed" }

      next if costs.empty? || response_times.empty?

      avg_cost = costs.sum / costs.size
      avg_response_time = response_times.sum / response_times.size
      success_rate = (success_count.to_f / provider_executions.size * 100)

      # Calculate efficiency score (lower cost + faster response + higher success = better)
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

    # Generate switching recommendations
    best_provider = provider_efficiency.max_by { |_, data| data[:efficiency_score] }
    worst_provider = provider_efficiency.min_by { |_, data| data[:efficiency_score] }

    recommendations = []
    if best_provider && worst_provider && best_provider != worst_provider
      potential_savings = calculate_provider_switching_savings(
        worst_provider[1][:avg_cost],
        best_provider[1][:avg_cost],
        worst_provider[1][:execution_count]
      )

      if potential_savings > 1.0 # Only recommend if savings > $1/month
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

  def analyze_usage_pattern_savings(executions)
    hourly_usage = executions.group_by { |e| e.created_at.hour }
                            .transform_values { |execs|
                              {
                                count: execs.size,
                                cost: execs.sum(&:cost_usd).round(4)
                              }
                            }

    daily_usage = executions.group_by { |e| e.created_at.strftime("%A") }
                           .transform_values { |execs|
                             {
                               count: execs.size,
                               cost: execs.sum(&:cost_usd).round(4)
                             }
                           }

    # Identify peak usage periods
    peak_hours = hourly_usage.select { |_, data| data[:cost] > 0 }
                            .sort_by { |_, data| -data[:cost] }
                            .first(3)
                            .map(&:first)

    off_peak_hours = (0..23).to_a - peak_hours

    recommendations = []

    # Recommend scheduling non-urgent tasks during off-peak hours
    if peak_hours.any? && off_peak_hours.any?
      peak_cost_per_hour = peak_hours.sum { |hour| hourly_usage[hour]&.dig(:cost) || 0 } / peak_hours.size
      off_peak_cost_per_hour = off_peak_hours.sum { |hour| hourly_usage[hour]&.dig(:cost) || 0 } / off_peak_hours.size

      if peak_cost_per_hour > off_peak_cost_per_hour * 1.2 # 20% higher cost during peak
        potential_savings = (peak_cost_per_hour - off_peak_cost_per_hour) * 30 # Monthly estimate

        recommendations << {
          type: "usage_scheduling",
          description: "Schedule non-urgent AI tasks during off-peak hours",
          peak_hours: peak_hours,
          off_peak_hours: off_peak_hours.first(8), # Suggest best 8 hours
          estimated_monthly_savings: potential_savings.round(2),
          implementation: "Use delayed job scheduling for non-urgent tasks"
        }
      end
    end

    {
      hourly_usage: hourly_usage,
      daily_usage: daily_usage,
      peak_analysis: {
        peak_hours: peak_hours,
        off_peak_hours: off_peak_hours
      },
      recommendations: recommendations
    }
  end

  def analyze_agent_cost_efficiency(executions)
    agent_analysis = {}

    executions.joins(:ai_agent).group_by(&:ai_agent).each do |agent, agent_executions|
      costs = agent_executions.map(&:cost_usd).compact
      next if costs.empty?

      total_cost = costs.sum
      avg_cost = total_cost / costs.size
      success_count = agent_executions.count { |e| e.status == "completed" }
      success_rate = (success_count.to_f / agent_executions.size * 100)

      # Calculate cost per successful execution
      cost_per_success = success_count > 0 ? total_cost / success_count : total_cost

      agent_analysis[agent.name] = {
        total_cost: total_cost.round(4),
        avg_cost_per_execution: avg_cost.round(6),
        cost_per_successful_execution: cost_per_success.round(6),
        success_rate: success_rate.round(2),
        execution_count: agent_executions.size,
        efficiency_rating: calculate_agent_efficiency_rating(cost_per_success, success_rate)
      }
    end

    # Identify underperforming agents
    underperforming = agent_analysis.select { |_, data|
      data[:efficiency_rating] < 3 && data[:total_cost] > 1.0
    }

    recommendations = underperforming.map do |agent_name, data|
      {
        type: "agent_optimization",
        agent: agent_name,
        description: "Optimize or consider replacing #{agent_name} (low efficiency: #{data[:efficiency_rating]}/5)",
        current_monthly_cost: (data[:total_cost] * (30.0 / @time_range.to_i.days)).round(2),
        success_rate: data[:success_rate],
        suggested_actions: generate_agent_optimization_actions(data)
      }
    end

    {
      agent_analysis: agent_analysis,
      recommendations: recommendations
    }
  end

  def generate_budget_recommendations(executions)
    current_monthly_cost = calculate_monthly_projection(calculate_daily_cost)

    # Budget tiers with recommendations
    budget_tiers = [
      { name: "Conservative", limit: current_monthly_cost * 0.8, savings_target: 20 },
      { name: "Moderate", limit: current_monthly_cost * 0.9, savings_target: 10 },
      { name: "Current", limit: current_monthly_cost, savings_target: 0 },
      { name: "Growth", limit: current_monthly_cost * 1.2, savings_target: -20 }
    ]

    recommendations = budget_tiers.map do |tier|
      {
        tier: tier[:name],
        monthly_limit: tier[:limit].round(2),
        savings_target_percentage: tier[:savings_target],
        actions_required: generate_budget_tier_actions(tier[:savings_target]),
        alert_threshold: (tier[:limit] * 0.8).round(2)
      }
    end

    {
      current_monthly_cost: current_monthly_cost.round(2),
      budget_recommendations: recommendations,
      suggested_tier: determine_suggested_budget_tier(current_monthly_cost)
    }
  end

  def calculate_projected_savings(executions)
    all_recommendations = [
      analyze_provider_cost_efficiency(executions)[:recommendations],
      analyze_usage_pattern_savings(executions)[:recommendations],
      analyze_agent_cost_efficiency(executions)[:recommendations]
    ].flatten

    total_monthly_savings = all_recommendations.sum do |rec|
      rec[:estimated_monthly_savings] || 0.0
    end

    current_monthly_cost = calculate_monthly_projection(calculate_daily_cost)
    savings_percentage = current_monthly_cost > 0 ? (total_monthly_savings / current_monthly_cost * 100) : 0

    {
      total_estimated_monthly_savings: total_monthly_savings.round(2),
      current_monthly_cost: current_monthly_cost.round(2),
      savings_percentage: savings_percentage.round(1),
      payback_period: "Immediate", # Most optimizations have immediate effect
      confidence_level: calculate_overall_confidence(all_recommendations)
    }
  end

  def calculate_current_period_cost
    recent_executions = @account.ai_agent_executions
                               .where(created_at: @start_date..@end_date)
                               .where.not(cost_usd: nil)

    recent_executions.sum(&:cost_usd) || 0.0
  end

  def calculate_daily_cost
    today_executions = @account.ai_agent_executions
                              .where(created_at: Time.current.beginning_of_day..Time.current)
                              .where.not(cost_usd: nil)

    today_executions.sum(&:cost_usd) || 0.0
  end

  def calculate_monthly_projection(daily_cost)
    # Use 30-day projection based on recent daily average
    recent_days = [ @time_range.to_i.days, 30 ].min
    recent_daily_costs = (0..recent_days-1).map do |days_ago|
      day_start = days_ago.days.ago.beginning_of_day
      day_end = days_ago.days.ago.end_of_day

      @account.ai_agent_executions
              .where(created_at: day_start..day_end)
              .where.not(cost_usd: nil)
              .sum(&:cost_usd) || 0.0
    end

    avg_daily_cost = recent_daily_costs.sum / recent_days.to_f
    avg_daily_cost * 30
  end

  def cache_key
    Digest::MD5.hexdigest("#{@start_date.to_i}-#{@end_date.to_i}")
  end

  # Helper methods for optimization calculations
  def calculate_efficiency_score(avg_cost, avg_response_time, success_rate)
    # Normalize values and calculate composite score (0-100)
    cost_score = [ 100 - (avg_cost * 1000), 0 ].max # Lower cost = higher score
    time_score = [ 100 - (avg_response_time / 100), 0 ].max # Faster = higher score
    success_score = success_rate # Already 0-100

    (cost_score * 0.4 + time_score * 0.3 + success_score * 0.3).round(2)
  end

  def calculate_provider_switching_savings(old_cost, new_cost, execution_count)
    return 0 if old_cost <= new_cost

    savings_per_execution = old_cost - new_cost
    monthly_executions = execution_count * (30.0 / @time_range.to_i.days)
    monthly_executions * savings_per_execution
  end

  def calculate_agent_efficiency_rating(cost_per_success, success_rate)
    # Rating from 1-5 based on cost efficiency and success rate
    case
    when cost_per_success < 0.01 && success_rate > 90
      5
    when cost_per_success < 0.05 && success_rate > 80
      4
    when cost_per_success < 0.10 && success_rate > 70
      3
    when cost_per_success < 0.20 && success_rate > 60
      2
    else
      1
    end
  end

  def generate_implementation_roadmap
    [
      {
        phase: "Immediate (0-7 days)",
        actions: [ "Set up cost alerts", "Review provider efficiency", "Enable automatic optimizations" ],
        expected_impact: "Quick wins, 5-15% cost reduction"
      },
      {
        phase: "Short-term (1-4 weeks)",
        actions: [ "Implement usage scheduling", "Optimize underperforming agents", "Set budget limits" ],
        expected_impact: "Sustainable optimization, 10-25% cost reduction"
      },
      {
        phase: "Long-term (1-3 months)",
        actions: [ "Advanced caching strategies", "Custom provider negotiations", "ML-driven optimization" ],
        expected_impact: "Maximum efficiency, 20-40% cost reduction"
      }
    ]
  end

  def setup_cost_alert_recommendations
    current_daily_avg = calculate_daily_cost

    [
      {
        type: "daily_spend",
        threshold: (current_daily_avg * 1.5).round(4),
        description: "Alert when daily spend exceeds 150% of current average"
      },
      {
        type: "monthly_projection",
        threshold: (current_daily_avg * 30 * 1.25).round(2),
        description: "Alert when monthly projection exceeds budget by 25%"
      },
      {
        type: "provider_cost_spike",
        threshold: "Dynamic based on provider averages",
        description: "Alert when any provider costs spike above normal range"
      }
    ]
  end

  # Placeholder methods for additional functionality
  def analyze_cost_trends; {}; end
  def analyze_budget_status(projection); {}; end
  def generate_cost_alerts(current, daily, monthly); []; end
  def apply_provider_switching_optimization(settings); {}; end
  def apply_usage_scheduling_optimization(settings); {}; end
  def apply_resource_limit_optimization(settings); {}; end
  def apply_cache_optimization(settings); {}; end
  def calculate_recommendation_confidence(execution_count); execution_count > 10 ? "high" : "medium"; end
  def generate_agent_optimization_actions(data); [ "Review agent configuration", "Consider alternative providers" ]; end
  def generate_budget_tier_actions(target); target > 0 ? [ "Reduce usage", "Optimize providers" ] : [ "Maintain current efficiency" ]; end
  def determine_suggested_budget_tier(cost); "Moderate"; end
  def calculate_overall_confidence(recommendations); recommendations.size > 2 ? "high" : "medium"; end
end
