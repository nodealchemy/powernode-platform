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
  
  private
  
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
                                 .group('ai_agents.agent_type')
                                 .sum(&:cost_usd)
    
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
      success_count = provider_executions.count { |e| e.status == 'completed' }
      
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
          type: 'provider_switch',
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
    
    daily_usage = executions.group_by { |e| e.created_at.strftime('%A') }
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
          type: 'usage_scheduling',
          description: 'Schedule non-urgent AI tasks during off-peak hours',
          peak_hours: peak_hours,
          off_peak_hours: off_peak_hours.first(8), # Suggest best 8 hours
          estimated_monthly_savings: potential_savings.round(2),
          implementation: 'Use delayed job scheduling for non-urgent tasks'
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
      success_count = agent_executions.count { |e| e.status == 'completed' }
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
        type: 'agent_optimization',
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
      { name: 'Conservative', limit: current_monthly_cost * 0.8, savings_target: 20 },
      { name: 'Moderate', limit: current_monthly_cost * 0.9, savings_target: 10 },
      { name: 'Current', limit: current_monthly_cost, savings_target: 0 },
      { name: 'Growth', limit: current_monthly_cost * 1.2, savings_target: -20 }
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
      payback_period: 'Immediate', # Most optimizations have immediate effect
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
    recent_days = [@time_range.to_i.days, 30].min
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
    cost_score = [100 - (avg_cost * 1000), 0].max # Lower cost = higher score
    time_score = [100 - (avg_response_time / 100), 0].max # Faster = higher score  
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
        phase: 'Immediate (0-7 days)',
        actions: ['Set up cost alerts', 'Review provider efficiency', 'Enable automatic optimizations'],
        expected_impact: 'Quick wins, 5-15% cost reduction'
      },
      {
        phase: 'Short-term (1-4 weeks)', 
        actions: ['Implement usage scheduling', 'Optimize underperforming agents', 'Set budget limits'],
        expected_impact: 'Sustainable optimization, 10-25% cost reduction'
      },
      {
        phase: 'Long-term (1-3 months)',
        actions: ['Advanced caching strategies', 'Custom provider negotiations', 'ML-driven optimization'],
        expected_impact: 'Maximum efficiency, 20-40% cost reduction'
      }
    ]
  end
  
  def setup_cost_alert_recommendations
    current_daily_avg = calculate_daily_cost
    
    [
      {
        type: 'daily_spend',
        threshold: (current_daily_avg * 1.5).round(4),
        description: 'Alert when daily spend exceeds 150% of current average'
      },
      {
        type: 'monthly_projection',
        threshold: (current_daily_avg * 30 * 1.25).round(2),
        description: 'Alert when monthly projection exceeds budget by 25%'
      },
      {
        type: 'provider_cost_spike',
        threshold: 'Dynamic based on provider averages',
        description: 'Alert when any provider costs spike above normal range'
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
  def calculate_recommendation_confidence(execution_count); execution_count > 10 ? 'high' : 'medium'; end
  def generate_agent_optimization_actions(data); ['Review agent configuration', 'Consider alternative providers']; end
  def generate_budget_tier_actions(target); target > 0 ? ['Reduce usage', 'Optimize providers'] : ['Maintain current efficiency']; end
  def determine_suggested_budget_tier(cost); 'Moderate'; end
  def calculate_overall_confidence(recommendations); recommendations.size > 2 ? 'high' : 'medium'; end
end