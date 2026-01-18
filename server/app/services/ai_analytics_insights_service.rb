# frozen_string_literal: true

class AiAnalyticsInsightsService
  include ActiveModel::Model
  include ActiveModel::Attributes

  attr_accessor :account, :time_range

  def initialize(account:, time_range: 30.days)
    @account = account
    @time_range = time_range
    @start_date = time_range.ago
    @end_date = Time.current
    @logger = Rails.logger
  end

  # Generate comprehensive analytics insights
  def generate_insights
    @logger.info "Generating AI analytics insights for account #{@account.id}"

    insights = {
      performance_insights: analyze_performance_trends,
      cost_insights: analyze_cost_patterns,
      usage_insights: analyze_usage_patterns,
      efficiency_insights: analyze_efficiency_metrics,
      predictive_insights: generate_predictive_analytics,
      optimization_recommendations: generate_optimization_recommendations,
      anomaly_detection: detect_anomalies,
      comparative_analysis: perform_comparative_analysis,
      quality_metrics: analyze_quality_metrics,
      resource_utilization: analyze_resource_utilization
    }

    # Cache insights for performance
    Rails.cache.write(
      "ai_analytics_insights:#{@account.id}:#{cache_key}",
      insights,
      expires_in: 1.hour
    )

    insights
  end

  # Performance trend analysis
  def analyze_performance_trends
    executions = base_executions_query

    daily_metrics = calculate_daily_performance_metrics(executions)

    {
      response_time_trend: calculate_trend(daily_metrics, :avg_response_time),
      success_rate_trend: calculate_trend(daily_metrics, :success_rate),
      throughput_trend: calculate_trend(daily_metrics, :execution_count),
      error_rate_trend: calculate_trend(daily_metrics, :error_rate),
      performance_score: calculate_overall_performance_score(daily_metrics),
      top_performing_agents: identify_top_performing_agents,
      underperforming_agents: identify_underperforming_agents,
      peak_performance_periods: identify_peak_performance_periods(daily_metrics)
    }
  end

  # Cost pattern analysis
  def analyze_cost_patterns
    executions = base_executions_query.where.not(cost_usd: nil)

    daily_costs = calculate_daily_cost_metrics(executions)

    {
      cost_trend: calculate_trend(daily_costs, :total_cost),
      cost_per_execution: calculate_average_cost_per_execution(executions),
      cost_by_provider: analyze_cost_by_provider(executions),
      cost_by_agent_type: analyze_cost_by_agent_type(executions),
      most_expensive_agents: identify_most_expensive_agents(executions),
      cost_efficiency_score: calculate_cost_efficiency_score(executions),
      cost_optimization_potential: estimate_cost_optimization_potential(executions),
      budget_forecast: generate_budget_forecast(daily_costs)
    }
  end

  # Usage pattern analysis
  def analyze_usage_patterns
    executions = base_executions_query

    {
      usage_trend: calculate_usage_trend(executions),
      hourly_usage_pattern: analyze_hourly_usage_patterns(executions),
      daily_usage_pattern: analyze_daily_usage_patterns(executions),
      agent_type_distribution: analyze_agent_type_usage(executions),
      provider_usage_distribution: analyze_provider_usage(executions),
      user_adoption_metrics: analyze_user_adoption(executions),
      seasonal_patterns: identify_seasonal_patterns(executions),
      usage_concentration: analyze_usage_concentration(executions)
    }
  end

  # Efficiency metrics analysis
  def analyze_efficiency_metrics
    executions = base_executions_query

    {
      overall_efficiency_score: calculate_overall_efficiency_score,
      resource_efficiency: calculate_resource_efficiency(executions),
      time_efficiency: calculate_time_efficiency(executions),
      cost_efficiency: calculate_cost_efficiency(executions),
      success_rate_efficiency: calculate_success_rate_efficiency(executions),
      provider_efficiency_ranking: rank_providers_by_efficiency,
      agent_efficiency_ranking: rank_agents_by_efficiency,
      efficiency_improvement_opportunities: identify_efficiency_opportunities
    }
  end

  # Predictive analytics
  def generate_predictive_analytics
    historical_data = gather_historical_data_for_prediction

    {
      usage_forecast: predict_future_usage(historical_data),
      cost_forecast: predict_future_costs(historical_data),
      capacity_requirements: predict_capacity_requirements(historical_data),
      scaling_recommendations: predict_scaling_needs(historical_data),
      maintenance_predictions: predict_maintenance_needs(historical_data),
      risk_assessment: assess_future_risks(historical_data),
      growth_trajectory: analyze_growth_trajectory(historical_data),
      seasonal_adjustments: predict_seasonal_adjustments(historical_data)
    }
  end

  # Optimization recommendations
  def generate_optimization_recommendations
    current_metrics = gather_current_performance_metrics

    recommendations = []

    # Performance optimizations
    recommendations.concat(generate_performance_recommendations(current_metrics))

    # Cost optimizations
    recommendations.concat(generate_cost_recommendations(current_metrics))

    # Resource optimizations
    recommendations.concat(generate_resource_recommendations(current_metrics))

    # Quality optimizations
    recommendations.concat(generate_quality_recommendations(current_metrics))

    {
      high_priority: recommendations.select { |r| r[:priority] == "high" },
      medium_priority: recommendations.select { |r| r[:priority] == "medium" },
      low_priority: recommendations.select { |r| r[:priority] == "low" },
      total_recommendations: recommendations.length,
      estimated_savings: calculate_estimated_savings(recommendations),
      implementation_timeline: generate_implementation_timeline(recommendations)
    }
  end

  # Anomaly detection
  def detect_anomalies
    current_metrics = gather_current_performance_metrics
    historical_baselines = calculate_historical_baselines

    anomalies = []

    # Response time anomalies
    anomalies.concat(detect_response_time_anomalies(current_metrics, historical_baselines))

    # Cost anomalies
    anomalies.concat(detect_cost_anomalies(current_metrics, historical_baselines))

    # Usage anomalies
    anomalies.concat(detect_usage_anomalies(current_metrics, historical_baselines))

    # Error rate anomalies
    anomalies.concat(detect_error_rate_anomalies(current_metrics, historical_baselines))

    {
      total_anomalies: anomalies.length,
      critical_anomalies: anomalies.select { |a| a[:severity] == "critical" },
      warning_anomalies: anomalies.select { |a| a[:severity] == "warning" },
      info_anomalies: anomalies.select { |a| a[:severity] == "info" },
      anomaly_trends: analyze_anomaly_trends(anomalies),
      resolution_recommendations: generate_anomaly_resolutions(anomalies)
    }
  end

  # Comparative analysis
  def perform_comparative_analysis
    current_period = gather_period_metrics(@start_date, @end_date)
    previous_period = gather_period_metrics(@start_date - @time_range, @start_date)

    {
      period_comparison: compare_periods(current_period, previous_period),
      agent_comparison: compare_agents_performance,
      provider_comparison: compare_providers_performance,
      trend_analysis: analyze_comparative_trends(current_period, previous_period),
      improvement_areas: identify_improvement_areas(current_period, previous_period),
      regression_areas: identify_regression_areas(current_period, previous_period)
    }
  end

  # Quality metrics analysis
  def analyze_quality_metrics
    executions = base_executions_query

    {
      overall_quality_score: calculate_overall_quality_score(executions),
      success_rate_analysis: analyze_success_rates(executions),
      error_pattern_analysis: analyze_error_patterns(executions),
      response_quality_metrics: analyze_response_quality(executions),
      consistency_metrics: analyze_consistency_metrics(executions),
      reliability_score: calculate_reliability_score(executions),
      quality_trends: analyze_quality_trends(executions),
      quality_by_agent_type: analyze_quality_by_agent_type(executions)
    }
  end

  # Resource utilization analysis
  def analyze_resource_utilization
    {
      compute_utilization: analyze_compute_utilization,
      memory_utilization: analyze_memory_utilization,
      storage_utilization: analyze_storage_utilization,
      network_utilization: analyze_network_utilization,
      provider_resource_efficiency: analyze_provider_resource_efficiency,
      peak_utilization_periods: identify_peak_utilization_periods,
      resource_bottlenecks: identify_resource_bottlenecks,
      scaling_opportunities: identify_scaling_opportunities
    }
  end

  private

  def base_executions_query
    @account.ai_agent_executions
            .where(created_at: @start_date..@end_date)
            .includes(:ai_agent, :ai_provider, :user)
  end

  def calculate_daily_performance_metrics(executions)
    executions.group_by { |e| e.created_at.to_date }
             .transform_values do |day_executions|
               {
                 execution_count: day_executions.count,
                 avg_response_time: day_executions.map(&:duration_ms).compact.sum / day_executions.count.to_f,
                 success_rate: (day_executions.count(&:successful?) / day_executions.count.to_f) * 100,
                 error_rate: (day_executions.count(&:failed?) / day_executions.count.to_f) * 100,
                 total_cost: day_executions.map(&:cost_usd).compact.sum
               }
             end
  end

  def calculate_trend(data_points, metric)
    return "insufficient_data" if data_points.size < 2

    values = data_points.values.map { |point| point[metric] }.compact
    return "no_data" if values.empty?

    # Simple linear trend calculation
    if values.last > values.first
      percentage_change = ((values.last - values.first) / values.first * 100).round(2)
      {
        direction: "increasing",
        percentage_change: percentage_change,
        trend: "upward"
      }
    elsif values.last < values.first
      percentage_change = ((values.first - values.last) / values.first * 100).round(2)
      {
        direction: "decreasing",
        percentage_change: percentage_change,
        trend: "downward"
      }
    else
      {
        direction: "stable",
        percentage_change: 0,
        trend: "stable"
      }
    end
  end

  def calculate_overall_performance_score(metrics)
    return 0 if metrics.empty?

    # Weighted scoring based on multiple factors
    avg_success_rate = metrics.values.map { |m| m[:success_rate] }.sum / metrics.size
    avg_response_time = metrics.values.map { |m| m[:avg_response_time] }.sum / metrics.size
    avg_error_rate = metrics.values.map { |m| m[:error_rate] }.sum / metrics.size

    # Normalize and weight scores (success rate: 40%, response time: 35%, error rate: 25%)
    success_score = (avg_success_rate / 100) * 40
    response_score = [ 1 - (avg_response_time / 10000), 0 ].max * 35  # Penalty for slow responses
    error_score = [ 1 - (avg_error_rate / 100), 0 ].max * 25  # Penalty for high error rates

    (success_score + response_score + error_score).round(2)
  end

  def identify_top_performing_agents
    agent_performance = base_executions_query
                       .joins(:ai_agent)
                       .group("ai_agents.id", "ai_agents.name")
                       .having("COUNT(*) >= 5")  # Minimum executions for statistical significance
                       .group("ai_agents.id", "ai_agents.name")
                       .calculate_multiple([
                         "AVG(CASE WHEN status = ? THEN 1.0 ELSE 0.0 END) * 100 AS success_rate",
                         "AVG(duration_ms) AS avg_response_time",
                         "COUNT(*) AS execution_count"
                       ], "completed")

    # Score and rank agents
    scored_agents = agent_performance.map do |agent_data, metrics|
      agent_id, agent_name = agent_data
      score = calculate_agent_performance_score(metrics)

      {
        agent_id: agent_id,
        agent_name: agent_name,
        performance_score: score,
        success_rate: metrics["success_rate"],
        avg_response_time: metrics["avg_response_time"],
        execution_count: metrics["execution_count"]
      }
    end

    scored_agents.sort_by { |agent| -agent[:performance_score] }.first(10)
  end

  def cache_key
    Digest::MD5.hexdigest("#{@start_date.to_i}-#{@end_date.to_i}")
  end

  # Cost analysis implementations
  def calculate_daily_cost_metrics(executions)
    executions.group_by { |e| e.created_at.to_date }
             .transform_values do |day_executions|
               {
                 total_cost: day_executions.map(&:cost_usd).compact.sum,
                 execution_count: day_executions.count,
                 avg_cost: day_executions.map(&:cost_usd).compact.sum / day_executions.count.to_f,
                 provider_breakdown: day_executions.group_by(&:ai_provider_id)
                                                  .transform_values { |execs| execs.map(&:cost_usd).compact.sum }
               }
             end
  end

  def calculate_average_cost_per_execution(executions)
    costs = executions.map(&:cost_usd).compact
    costs.empty? ? 0.0 : costs.sum / costs.size.to_f
  end

  def analyze_cost_by_provider(executions)
    executions.group_by(&:ai_provider)
             .transform_values do |provider_executions|
               costs = provider_executions.map(&:cost_usd).compact
               {
                 total_cost: costs.sum,
                 execution_count: provider_executions.count,
                 avg_cost: costs.empty? ? 0.0 : costs.sum / costs.size.to_f,
                 percentage_of_total: costs.sum / executions.map(&:cost_usd).compact.sum * 100
               }
             end
  end

  def analyze_cost_by_agent_type(executions)
    executions.joins(:ai_agent)
             .group("ai_agents.agent_type")
             .group("ai_agents.id")
             .calculate("SUM(cost_usd) as total_cost")
  end

  def identify_most_expensive_agents(executions)
    executions.joins(:ai_agent)
             .group("ai_agents.id", "ai_agents.name")
             .having("COUNT(*) >= 3")
             .order("SUM(cost_usd) DESC")
             .limit(10)
             .calculate("SUM(cost_usd) as total_cost")
             .map do |agent_data, cost|
               agent_id, agent_name = agent_data
               {
                 agent_id: agent_id,
                 agent_name: agent_name,
                 total_cost: cost,
                 execution_count: executions.where(ai_agent_id: agent_id).count
               }
             end
  end

  def calculate_cost_efficiency_score(executions)
    return 0.0 if executions.empty?

    # Cost per successful execution weighted by response time
    successful = executions.select(&:successful?)
    return 0.0 if successful.empty?

    avg_cost = successful.map(&:cost_usd).compact.sum / successful.size.to_f
    avg_time = successful.map(&:duration_ms).compact.sum / successful.size.to_f

    # Lower cost + faster response = higher efficiency
    base_score = 100.0
    cost_penalty = [ avg_cost * 10, 50 ].min  # Cap cost penalty
    time_penalty = [ avg_time / 100, 30 ].min # Cap time penalty

    [ base_score - cost_penalty - time_penalty, 0 ].max
  end

  def estimate_cost_optimization_potential(executions)
    return {} if executions.empty?

    provider_costs = analyze_cost_by_provider(executions)
    most_expensive = provider_costs.max_by { |_, data| data[:avg_cost] }
    least_expensive = provider_costs.min_by { |_, data| data[:avg_cost] }

    return {} unless most_expensive && least_expensive

    savings_per_execution = most_expensive[1][:avg_cost] - least_expensive[1][:avg_cost]
    potential_monthly_savings = savings_per_execution * executions.count * (30.0 / @time_range.to_i.days)

    {
      potential_monthly_savings: potential_monthly_savings,
      optimization_percentage: (savings_per_execution / most_expensive[1][:avg_cost] * 100).round(2),
      recommendation: "Consider migrating from #{most_expensive[0]&.name} to #{least_expensive[0]&.name}"
    }
  end

  def generate_budget_forecast(daily_costs)
    return {} if daily_costs.empty?

    costs = daily_costs.values.map { |d| d[:total_cost] }
    trend = calculate_cost_trend(costs)

    current_daily_avg = costs.sum / costs.size.to_f

    case trend[:direction]
    when "increasing"
      growth_factor = 1 + (trend[:percentage_change] / 100.0)
      projected_monthly = current_daily_avg * 30 * growth_factor
    when "decreasing"
      decline_factor = 1 - (trend[:percentage_change] / 100.0)
      projected_monthly = current_daily_avg * 30 * decline_factor
    else
      projected_monthly = current_daily_avg * 30
    end

    {
      current_daily_average: current_daily_avg.round(2),
      projected_monthly_cost: projected_monthly.round(2),
      trend: trend,
      confidence_level: costs.size >= 7 ? "high" : "medium"
    }
  end

  def calculate_cost_trend(costs)
    return { direction: "stable", percentage_change: 0 } if costs.size < 2

    first_half = costs.first(costs.size / 2)
    second_half = costs.last(costs.size / 2)

    first_avg = first_half.sum / first_half.size.to_f
    second_avg = second_half.sum / second_half.size.to_f

    if second_avg > first_avg
      percentage_change = ((second_avg - first_avg) / first_avg * 100).round(2)
      { direction: "increasing", percentage_change: percentage_change }
    elsif second_avg < first_avg
      percentage_change = ((first_avg - second_avg) / first_avg * 100).round(2)
      { direction: "decreasing", percentage_change: percentage_change }
    else
      { direction: "stable", percentage_change: 0 }
    end
  end
  def calculate_usage_trend(executions)
    daily_counts = executions.group_by { |e| e.created_at.to_date }
                            .transform_values(&:count)

    return { trend: "no_data" } if daily_counts.empty?

    dates = daily_counts.keys.sort
    counts = dates.map { |date| daily_counts[date] }

    calculate_trend(daily_counts, :count) if counts.size > 1
  end

  def analyze_hourly_usage_patterns(executions)
    hourly_distribution = executions.group_by { |e| e.created_at.hour }
                                   .transform_values(&:count)

    peak_hour = hourly_distribution.max_by { |_, count| count }&.first
    low_hour = hourly_distribution.min_by { |_, count| count }&.first

    {
      distribution: hourly_distribution,
      peak_hour: peak_hour,
      low_hour: low_hour,
      peak_usage_period: identify_peak_usage_period(hourly_distribution)
    }
  end

  def analyze_daily_usage_patterns(executions)
    daily_distribution = executions.group_by { |e| e.created_at.strftime("%A") }
                                 .transform_values(&:count)

    {
      distribution: daily_distribution,
      busiest_day: daily_distribution.max_by { |_, count| count }&.first,
      quietest_day: daily_distribution.min_by { |_, count| count }&.first
    }
  end

  def analyze_agent_type_usage(executions)
    executions.joins(:ai_agent)
             .group("ai_agents.agent_type")
             .group("ai_agents.name")
             .count
             .group_by { |key, _| key.first }
             .transform_values do |agent_data|
               {
                 total_executions: agent_data.sum { |_, count| count },
                 agents: agent_data.map { |key, count| { name: key.second, executions: count } }
               }
             end
  end

  def analyze_provider_usage(executions)
    executions.joins(:ai_provider)
             .group("ai_providers.name", "ai_providers.provider_type")
             .count
             .map do |key, count|
               provider_name, provider_type = key
               {
                 name: provider_name,
                 type: provider_type,
                 executions: count,
                 percentage: (count.to_f / executions.count * 100).round(2)
               }
             end
  end

  def analyze_user_adoption(executions)
    user_activity = executions.group_by(&:user_id)
                             .transform_values(&:count)

    total_users = user_activity.keys.count
    active_users = user_activity.values.count { |count| count >= 5 }

    {
      total_active_users: total_users,
      highly_active_users: active_users,
      adoption_rate: total_users > 0 ? (active_users.to_f / total_users * 100).round(2) : 0,
      avg_executions_per_user: total_users > 0 ? user_activity.values.sum / total_users.to_f : 0
    }
  end

  def identify_seasonal_patterns(executions)
    return [] if executions.count < 30

    weekly_patterns = executions.group_by { |e| e.created_at.beginning_of_week }
                               .transform_values(&:count)

    monthly_patterns = executions.group_by { |e| e.created_at.beginning_of_month }
                                .transform_values(&:count)

    {
      weekly_trend: calculate_pattern_trend(weekly_patterns),
      monthly_trend: calculate_pattern_trend(monthly_patterns),
      identified_patterns: detect_cyclical_patterns(weekly_patterns)
    }
  end

  def analyze_usage_concentration(executions)
    user_distribution = executions.group_by(&:user_id)
                                 .transform_values(&:count)

    total_executions = executions.count
    top_10_percent = (user_distribution.count * 0.1).ceil
    top_users_executions = user_distribution.values.sort.reverse.first(top_10_percent).sum

    {
      gini_coefficient: calculate_gini_coefficient(user_distribution.values),
      top_10_percent_usage: (top_users_executions.to_f / total_executions * 100).round(2),
      concentration_level: classify_concentration_level(user_distribution.values)
    }
  end

  private

  def identify_peak_usage_period(hourly_distribution)
    # Find consecutive hours with high usage
    sorted_hours = hourly_distribution.sort_by { |_, count| -count }
    peak_threshold = sorted_hours.first(3).map(&:last).sum / 3.0

    peak_hours = hourly_distribution.select { |_, count| count >= peak_threshold }.keys.sort

    if peak_hours.size >= 3
      "#{peak_hours.first}:00-#{peak_hours.last + 1}:00"
    else
      "#{peak_hours.first}:00-#{peak_hours.first + 1}:00" if peak_hours.any?
    end
  end

  def calculate_pattern_trend(patterns)
    return "insufficient_data" if patterns.size < 3

    values = patterns.values
    first_third = values.first(values.size / 3).sum / (values.size / 3).to_f
    last_third = values.last(values.size / 3).sum / (values.size / 3).to_f

    percentage_change = ((last_third - first_third) / first_third * 100).round(2)

    if percentage_change > 10
      "increasing"
    elsif percentage_change < -10
      "decreasing"
    else
      "stable"
    end
  end

  def detect_cyclical_patterns(weekly_patterns)
    return [] if weekly_patterns.size < 8

    # Simple pattern detection - look for recurring weekly patterns
    weeks = weekly_patterns.keys.sort
    patterns = []

    (0..weeks.size-4).each do |i|
      week_slice = weeks[i..i+3]
      counts = week_slice.map { |week| weekly_patterns[week] }

      if counts.max > counts.min * 1.5
        patterns << {
          type: "weekly_spike",
          period: week_slice.first.strftime("%B %d"),
          intensity: ((counts.max - counts.min).to_f / counts.min * 100).round(2)
        }
      end
    end

    patterns.uniq { |p| p[:type] }
  end

  def calculate_gini_coefficient(values)
    return 0 if values.empty? || values.all?(&:zero?)

    sorted_values = values.sort
    n = sorted_values.size

    numerator = (1..n).map { |i| (2 * i - n - 1) * sorted_values[i - 1] }.sum
    denominator = n * sorted_values.sum

    numerator.to_f / denominator
  end

  def classify_concentration_level(values)
    gini = calculate_gini_coefficient(values)

    case gini
    when 0..0.3
      "low_concentration"
    when 0.3..0.6
      "medium_concentration"
    else
      "high_concentration"
    end
  end
  def calculate_overall_efficiency_score; 0.0; end
  def calculate_resource_efficiency(executions); {}; end
  def calculate_time_efficiency(executions); {}; end
  def calculate_cost_efficiency(executions); {}; end
  def calculate_success_rate_efficiency(executions); {}; end
  def rank_providers_by_efficiency; []; end
  def rank_agents_by_efficiency; []; end
  def identify_efficiency_opportunities; []; end
  def gather_historical_data_for_prediction; {}; end
  def predict_future_usage(data); {}; end
  def predict_future_costs(data); {}; end
  def predict_capacity_requirements(data); {}; end
  def predict_scaling_needs(data); {}; end
  def predict_maintenance_needs(data); {}; end
  def assess_future_risks(data); {}; end
  def analyze_growth_trajectory(data); {}; end
  def predict_seasonal_adjustments(data); {}; end
  def gather_current_performance_metrics; {}; end
  def generate_performance_recommendations(metrics); []; end
  def generate_cost_recommendations(metrics); []; end
  def generate_resource_recommendations(metrics); []; end
  def generate_quality_recommendations(metrics); []; end
  def calculate_estimated_savings(recommendations); 0.0; end
  def generate_implementation_timeline(recommendations); {}; end
  def calculate_historical_baselines; {}; end
  def detect_response_time_anomalies(current, baseline); []; end
  def detect_cost_anomalies(current, baseline); []; end
  def detect_usage_anomalies(current, baseline); []; end
  def detect_error_rate_anomalies(current, baseline); []; end
  def analyze_anomaly_trends(anomalies); {}; end
  def generate_anomaly_resolutions(anomalies); []; end
  def gather_period_metrics(start_date, end_date); {}; end
  def compare_periods(current, previous); {}; end
  def compare_agents_performance; {}; end
  def compare_providers_performance; {}; end
  def analyze_comparative_trends(current, previous); {}; end
  def identify_improvement_areas(current, previous); []; end
  def identify_regression_areas(current, previous); []; end
  def calculate_overall_quality_score(executions); 0.0; end
  def analyze_success_rates(executions); {}; end
  def analyze_error_patterns(executions); {}; end
  def analyze_response_quality(executions); {}; end
  def analyze_consistency_metrics(executions); {}; end
  def calculate_reliability_score(executions); 0.0; end
  def analyze_quality_trends(executions); {}; end
  def analyze_quality_by_agent_type(executions); {}; end
  def analyze_compute_utilization; {}; end
  def analyze_memory_utilization; {}; end
  def analyze_storage_utilization; {}; end
  def analyze_network_utilization; {}; end
  def analyze_provider_resource_efficiency; {}; end
  def identify_peak_utilization_periods; []; end
  def identify_resource_bottlenecks; []; end
  def identify_scaling_opportunities; []; end
  def identify_underperforming_agents; []; end
  def identify_peak_performance_periods(metrics); []; end
  def calculate_agent_performance_score(metrics); (metrics["success_rate"] || 0) * 0.6 + [ 100 - (metrics["avg_response_time"] || 0) / 100, 0 ].max * 0.4; end

  # Real-time metrics for WebSocket broadcasting
  def real_time_metrics(account_id)
    @logger.info "Generating real-time metrics for account #{account_id}"

    # Get recent data (last hour)
    recent_executions = Ai::AgentExecution.joins(:account)
                                       .where(accounts: { id: account_id })
                                       .where(created_at: 1.hour.ago..Time.current)

    current_active = recent_executions.where(status: [ "queued", "processing" ]).count
    completed_recent = recent_executions.where(status: "completed").count
    failed_recent = recent_executions.where(status: "failed").count

    # Calculate real-time success rate
    total_recent = completed_recent + failed_recent
    success_rate = total_recent > 0 ? (completed_recent.to_f / total_recent * 100).round(1) : 0.0

    # Get current cost information
    recent_cost = recent_executions.sum(&:cost_usd) || 0.0
    daily_cost = Ai::AgentExecution.joins(:account)
                                 .where(accounts: { id: account_id })
                                 .where(created_at: Time.current.beginning_of_day..Time.current)
                                 .sum(&:cost_usd) || 0.0

    # Provider distribution
    provider_distribution = recent_executions.joins(:ai_provider)
                                           .group("ai_providers.name")
                                           .count

    # Agent activity
    agent_activity = recent_executions.joins(:ai_agent)
                                    .group("ai_agents.name", "ai_agents.id")
                                    .count
                                    .map do |key, count|
                                      agent_name, agent_id = key
                                      {
                                        id: agent_id,
                                        name: agent_name,
                                        executions: count
                                      }
                                    end.first(5)

    # Response time metrics
    response_times = recent_executions.where.not(duration_ms: nil).pluck(:duration_ms)
    avg_response_time = response_times.any? ? response_times.sum / response_times.size.to_f : 0.0

    # System health indicators
    health_score = calculate_system_health_score(recent_executions)

    {
      timestamp: Time.current.iso8601,
      current_active_executions: current_active,
      recent_completed: completed_recent,
      recent_failed: failed_recent,
      success_rate: success_rate,
      recent_cost_usd: recent_cost.round(4),
      daily_cost_usd: daily_cost.round(4),
      avg_response_time_ms: avg_response_time.round(0),
      provider_distribution: provider_distribution,
      top_active_agents: agent_activity,
      system_health_score: health_score,
      alerts: generate_real_time_alerts(recent_executions)
    }
  end

  private

  def calculate_system_health_score(executions)
    return 100.0 if executions.empty?

    completed = executions.where(status: "completed").count
    failed = executions.where(status: "failed").count
    stuck = executions.where(status: "processing")
                     .where("created_at < ?", 10.minutes.ago)
                     .count

    total = executions.count
    return 100.0 if total == 0

    success_factor = (completed.to_f / total) * 100
    failure_penalty = (failed.to_f / total) * 50
    stuck_penalty = (stuck.to_f / total) * 75

    health_score = success_factor - failure_penalty - stuck_penalty

    [ [ health_score, 0 ].max, 100 ].min
  end

  def generate_real_time_alerts(executions)
    alerts = []

    # High failure rate alert
    total_recent = executions.count
    if total_recent >= 5
      failed_count = executions.where(status: "failed").count
      failure_rate = (failed_count.to_f / total_recent * 100)

      if failure_rate > 20
        alerts << {
          type: "high_failure_rate",
          severity: "warning",
          message: "High failure rate detected: #{failure_rate.round(1)}%",
          timestamp: Time.current.iso8601
        }
      end
    end

    # Stuck executions alert
    stuck_executions = executions.where(status: "processing")
                                .where("created_at < ?", 15.minutes.ago)
                                .count

    if stuck_executions > 0
      alerts << {
        type: "stuck_executions",
        severity: "error",
        message: "#{stuck_executions} execution(s) appear to be stuck",
        timestamp: Time.current.iso8601
      }
    end

    # High cost alert (if daily cost exceeds threshold)
    daily_cost = Ai::AgentExecution.joins(:account)
                                .where(accounts: { id: @account.id })
                                .where(created_at: Time.current.beginning_of_day..Time.current)
                                .sum(&:cost_usd) || 0.0

    if daily_cost > 50.0  # Alert if daily cost exceeds $50
      alerts << {
        type: "high_daily_cost",
        severity: "warning",
        message: "Daily cost is high: $#{daily_cost.round(2)}",
        timestamp: Time.current.iso8601
      }
    end

    alerts
  end
end
