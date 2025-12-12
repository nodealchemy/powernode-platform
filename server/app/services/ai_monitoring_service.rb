# frozen_string_literal: true

# @deprecated Use UnifiedMonitoringService instead
#   This service will be removed in v2.0
#   UnifiedMonitoringService provides all functionality from this service plus:
#   - Unified dashboard metrics
#   - Better component organization
#   - Improved performance
#
#   Migration guide: docs/migration/MONITORING_SERVICE_MIGRATION.md
#
class AiMonitoringService
  include ActiveModel::Model
  include ActiveModel::Attributes

  ALERT_TYPES = %w[provider_failure high_cost execution_timeout circuit_breaker_open low_success_rate high_latency].freeze
  METRIC_TYPES = %w[execution_count success_rate avg_response_time total_cost error_count].freeze

  def initialize(account: nil)
    @account = account
    @logger = Rails.logger
    @redis = Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")
  end

  # Record execution metrics
  def record_execution(provider, execution_type, result)
    timestamp = Time.current.to_i

    # Update basic counters
    increment_counter("executions:#{provider.id}", timestamp)
    increment_counter("executions:#{provider.id}:#{execution_type}", timestamp)

    if result[:success]
      increment_counter("successes:#{provider.id}", timestamp)
      record_response_time(provider, result[:execution_time_ms]) if result[:execution_time_ms]
      record_cost(provider, result[:cost]) if result[:cost]
    else
      increment_counter("failures:#{provider.id}", timestamp)
      record_error(provider, execution_type, result[:error])

      # Check if alert should be triggered
      check_and_trigger_alerts(provider, execution_type, result)
    end

    # Update real-time metrics
    update_realtime_metrics(provider, execution_type, result)

    @logger.debug "Recorded execution metrics for provider #{provider.name}: #{result[:success] ? 'success' : 'failure'}"
  end

  # Get comprehensive monitoring dashboard data
  def get_dashboard_metrics(time_range: 1.hour)
    end_time = Time.current
    start_time = end_time - time_range

    providers = get_monitored_providers

    {
      overview: get_overview_metrics(providers, start_time, end_time),
      providers: providers.map { |p| get_provider_metrics(p, start_time, end_time) },
      alerts: get_active_alerts,
      system_health: get_system_health_score(providers),
      cost_analysis: get_cost_analysis(providers, start_time, end_time),
      performance_trends: get_performance_trends(providers, start_time, end_time)
    }
  end

  # Get real-time status for all providers
  def get_realtime_status
    providers = get_monitored_providers

    {
      timestamp: Time.current.iso8601,
      providers: providers.map do |provider|
        begin
          circuit_breaker = AiProviderCircuitBreakerService.new(provider)

          {
            id: provider.id,
            name: provider.name,
            status: get_provider_status(provider),
            circuit_state: circuit_breaker.circuit_state,
            current_load: get_current_load(provider),
            last_execution: get_last_execution_time(provider),
            success_rate_1h: get_success_rate(provider, 1.hour),
            avg_response_time_1h: get_avg_response_time(provider, 1.hour),
            cost_last_hour: get_cost_last_hour(provider) || 0,
            active_alerts: get_provider_alerts(provider) || []
          }
        rescue => e
          @logger.error "Error getting provider status for #{provider.name}: #{e.message}"
          {
            id: provider.id,
            name: provider.name,
            status: "error",
            circuit_state: "unknown",
            current_load: 0,
            last_execution: nil,
            success_rate_1h: 0,
            avg_response_time_1h: 0,
            cost_last_hour: 0,
            active_alerts: []
          }
        end
      end,
      system_summary: {
        total_executions_1h: get_total_executions(1.hour),
        system_success_rate_1h: get_system_success_rate(1.hour),
        total_cost_1h: get_total_cost(1.hour),
        active_alerts_count: get_active_alerts.size
      }
    }
  end

  # Trigger custom alert
  def trigger_alert(alert_type, provider, details = {})
    return unless ALERT_TYPES.include?(alert_type)

    alert_data = {
      type: alert_type,
      provider_id: provider.id,
      provider_name: provider.name,
      timestamp: Time.current.iso8601,
      details: details,
      severity: determine_alert_severity(alert_type, details),
      resolved: false
    }

    alert_key = "alert:#{provider.id}:#{alert_type}:#{Time.current.to_i}"
    @redis.set(alert_key, alert_data.to_json)
    @redis.expire(alert_key, 24.hours) # Alerts expire after 24 hours

    # Add to active alerts list
    @redis.lpush(active_alerts_key, alert_key)
    @redis.ltrim(active_alerts_key, 0, 99) # Keep last 100 alerts

    # Send notifications if configured
    send_alert_notification(alert_data) if should_send_notification?(alert_type, details)

    @logger.warn "Alert triggered: #{alert_type} for provider #{provider.name} - #{details[:message]}"
  end

  # Resolve alert
  def resolve_alert(alert_key)
    alert_json = @redis.get(alert_key)
    return false unless alert_json

    alert_data = JSON.parse(alert_json)
    alert_data["resolved"] = true
    alert_data["resolved_at"] = Time.current.iso8601

    @redis.set(alert_key, alert_data.to_json)
    @redis.lrem(active_alerts_key, 1, alert_key)

    @logger.info "Alert resolved: #{alert_key}"
    true
  end

  # Get execution logs for debugging
  def get_execution_logs(provider: nil, limit: 100, filters: {})
    logs_key = provider ? "execution_logs:#{provider.id}" : "execution_logs:system"
    log_entries = @redis.lrange(logs_key, 0, limit - 1)

    logs = log_entries.map { |entry| JSON.parse(entry) }

    # Apply filters
    logs = filter_logs(logs, filters) if filters.any?

    {
      logs: logs,
      total_count: @redis.llen(logs_key),
      filters_applied: filters
    }
  end

  # Generate health report
  def generate_health_report(time_range: 24.hours)
    end_time = Time.current
    start_time = end_time - time_range
    providers = get_monitored_providers

    report = {
      report_generated_at: end_time.iso8601,
      time_range: {
        start: start_time.iso8601,
        end: end_time.iso8601,
        duration_hours: (time_range / 1.hour).round(2)
      },
      system_overview: {
        total_providers: providers.size,
        healthy_providers: providers.count { |p| get_provider_status(p) == "healthy" },
        total_executions: get_total_executions(time_range),
        system_success_rate: get_system_success_rate(time_range),
        total_cost: get_total_cost(time_range),
        avg_response_time: get_system_avg_response_time(time_range)
      },
      providers: providers.map { |p| generate_provider_health_summary(p, start_time, end_time) },
      alerts_summary: {
        total_alerts: get_alerts_count(time_range),
        alerts_by_type: get_alerts_by_type(time_range),
        top_alerting_providers: get_top_alerting_providers(time_range)
      },
      recommendations: generate_recommendations(providers)
    }

    # Store report for historical tracking
    report_key = "health_report:#{end_time.to_i}"
    @redis.set(report_key, report.to_json)
    @redis.expire(report_key, 7.days) # Keep reports for a week

    report
  end

  private

  def get_monitored_providers
    if @account
      @account.ai_providers.active.to_a
    else
      AiProvider.active.to_a
    end
  end

  def increment_counter(counter_name, timestamp)
    key = "metrics:#{counter_name}:#{timestamp / 60}" # Per-minute buckets
    @redis.incr(key)
    @redis.expire(key, 25.hours) # Keep for slightly more than 24h
  end

  def record_response_time(provider, response_time_ms)
    key = "response_times:#{provider.id}"
    @redis.lpush(key, response_time_ms)
    @redis.ltrim(key, 0, 999) # Keep last 1000 response times
    @redis.expire(key, 1.hour)
  end

  def record_cost(provider, cost)
    timestamp = Time.current.to_i / 60 # Per-minute buckets
    key = "costs:#{provider.id}:#{timestamp}"
    @redis.incrbyfloat(key, cost)
    @redis.expire(key, 25.hours)
  end

  def record_error(provider, execution_type, error_message)
    error_data = {
      provider_id: provider.id,
      execution_type: execution_type,
      error: error_message,
      timestamp: Time.current.iso8601
    }

    key = "errors:#{provider.id}"
    @redis.lpush(key, error_data.to_json)
    @redis.ltrim(key, 0, 99) # Keep last 100 errors
    @redis.expire(key, 24.hours)
  end

  def check_and_trigger_alerts(provider, execution_type, result)
    # High failure rate alert
    failure_rate = 100 - get_success_rate(provider, 15.minutes)
    if failure_rate > 50
      trigger_alert("low_success_rate", provider, {
        message: "Success rate dropped to #{100 - failure_rate}%",
        success_rate: 100 - failure_rate,
        time_window: "15 minutes"
      })
    end

    # High latency alert
    avg_response_time = get_avg_response_time(provider, 15.minutes)
    if avg_response_time > 10000 # 10 seconds
      trigger_alert("high_latency", provider, {
        message: "Average response time is #{avg_response_time}ms",
        avg_response_time: avg_response_time,
        time_window: "15 minutes"
      })
    end

    # Specific error type alerts
    if result[:error]&.include?("timeout")
      trigger_alert("execution_timeout", provider, {
        message: "Execution timeout detected",
        error: result[:error]
      })
    end
  end

  def update_realtime_metrics(provider, execution_type, result)
    # Update real-time aggregated metrics
    realtime_key = "realtime:#{provider.id}"
    current_data = @redis.get(realtime_key)

    metrics = if current_data
                JSON.parse(current_data)
    else
                {
                  "total_executions" => 0,
                  "successful_executions" => 0,
                  "total_cost" => 0.0,
                  "total_response_time" => 0,
                  "last_updated" => Time.current.iso8601
                }
    end

    metrics["total_executions"] += 1
    metrics["successful_executions"] += 1 if result[:success]
    metrics["total_cost"] += result[:cost].to_f if result[:cost]
    metrics["total_response_time"] += result[:execution_time_ms].to_i if result[:execution_time_ms]
    metrics["last_updated"] = Time.current.iso8601

    @redis.set(realtime_key, metrics.to_json)
    @redis.expire(realtime_key, 1.hour)
  end

  def get_success_rate(provider, time_range)
    end_time = Time.current.to_i / 60
    start_time = end_time - (time_range / 60).to_i

    successes = get_counter_sum("metrics:successes:#{provider.id}", start_time, end_time)
    failures = get_counter_sum("metrics:failures:#{provider.id}", start_time, end_time)
    total = successes + failures

    return 100.0 if total == 0
    (successes.to_f / total * 100).round(2)
  end

  def get_counter_sum(prefix, start_time, end_time)
    sum = 0
    (start_time..end_time).each do |minute|
      key = "#{prefix}:#{minute}"
      value = @redis.get(key)
      sum += value.to_i if value
    end
    sum
  end

  def determine_alert_severity(alert_type, details)
    case alert_type
    when "provider_failure", "circuit_breaker_open"
      "high"
    when "high_cost", "execution_timeout"
      "medium"
    when "low_success_rate", "high_latency"
      (details[:success_rate] && details[:success_rate] < 10) ||
      (details[:avg_response_time] && details[:avg_response_time] > 30000) ? "high" : "medium"
    else
      "low"
    end
  end

  def should_send_notification?(alert_type, details)
    # Only send notifications for high severity alerts or repeated issues
    determine_alert_severity(alert_type, details) == "high"
  end

  def send_alert_notification(alert_data)
    # This would integrate with notification systems (email, Slack, webhooks, etc.)
    # For now, just log the alert
    @logger.error "ALERT NOTIFICATION: #{alert_data[:type]} - #{alert_data[:details][:message]}"

    # Future implementation could include:
    # - Email notifications
    # - Slack/Discord webhooks
    # - SMS alerts
    # - PagerDuty integration
  end

  def get_active_alerts
    alert_keys = @redis.lrange(active_alerts_key, 0, -1)
    alert_keys.filter_map do |key|
      alert_json = @redis.get(key)
      JSON.parse(alert_json) if alert_json
    end
  end

  def active_alerts_key
    "active_alerts#{@account ? ":#{@account.id}" : ':system'}"
  end

  # Additional helper methods for metrics calculation...
  def get_provider_status(provider)
    circuit_breaker = AiProviderCircuitBreakerService.new(provider)

    case circuit_breaker.circuit_state
    when :closed
      success_rate = get_success_rate(provider, 15.minutes)
      success_rate > 90 ? "healthy" : "degraded"
    when :half_open
      "recovering"
    when :open
      "unhealthy"
    else
      "unknown"
    end
  end

  def generate_recommendations(providers)
    recommendations = []

    providers.each do |provider|
      success_rate = get_success_rate(provider, 1.hour)
      avg_response_time = get_avg_response_time(provider, 1.hour)

      if success_rate < 95
        recommendations << {
          type: "performance",
          provider: provider.name,
          message: "Provider #{provider.name} has low success rate (#{success_rate}%). Consider investigating or switching providers."
        }
      end

      if avg_response_time > 5000
        recommendations << {
          type: "performance",
          provider: provider.name,
          message: "Provider #{provider.name} has high latency (#{avg_response_time}ms). Consider optimizing or load balancing."
        }
      end
    end

    recommendations
  end

  def get_avg_response_time(provider, time_range)
    key = "response_times:#{provider.id}"
    response_times = @redis.lrange(key, 0, -1).map(&:to_f)

    return 0.0 if response_times.empty?
    response_times.sum / response_times.size
  end

  def get_total_executions(time_range)
    # Implementation for getting total executions across all providers
    get_monitored_providers.sum { |p| get_executions_count(p, time_range) }
  end

  def get_executions_count(provider, time_range)
    end_time = Time.current.to_i / 60
    start_time = end_time - (time_range / 60).to_i
    get_counter_sum("metrics:executions:#{provider.id}", start_time, end_time)
  end

  # Additional helper methods
  def get_current_load(provider)
    (@redis.get("current_load:#{provider.id}") || 0).to_i
  rescue => e
    @logger.error "Error getting current load for #{provider.name}: #{e.message}"
    0
  end

  def get_last_execution_time(provider)
    timestamp = @redis.get("last_execution:#{provider.id}")
    timestamp ? Time.parse(timestamp) : nil
  rescue => e
    @logger.error "Error getting last execution time for #{provider.name}: #{e.message}"
    nil
  end

  def get_cost_last_hour(provider)
    end_time = Time.current.to_i / 60
    start_time = end_time - 60 # Last 60 minutes
    total_cost = 0.0

    (start_time..end_time).each do |minute|
      cost_key = "costs:#{provider.id}:#{minute}"
      cost = @redis.get(cost_key)
      total_cost += cost.to_f if cost
    end

    total_cost
  rescue => e
    @logger.error "Error getting cost for #{provider.name}: #{e.message}"
    0.0
  end

  def get_provider_alerts(provider)
    # Get active alerts for this provider
    alert_keys = @redis.lrange(active_alerts_key, 0, -1)
    provider_alerts = []

    alert_keys.each do |key|
      alert_json = @redis.get(key)
      next unless alert_json

      alert = JSON.parse(alert_json)
      provider_alerts << alert if alert["provider_id"] == provider.id
    end

    provider_alerts
  rescue => e
    @logger.error "Error getting alerts for #{provider.name}: #{e.message}"
    []
  end

  def get_system_success_rate(time_range)
    # Calculate overall system success rate
    providers = get_monitored_providers
    return 100.0 if providers.empty?

    total_successes = 0
    total_executions = 0

    providers.each do |provider|
      successes = get_counter_sum("metrics:successes:#{provider.id}",
                                 Time.current.to_i / 60 - (time_range / 60).to_i,
                                 Time.current.to_i / 60)
      failures = get_counter_sum("metrics:failures:#{provider.id}",
                                Time.current.to_i / 60 - (time_range / 60).to_i,
                                Time.current.to_i / 60)

      total_successes += successes
      total_executions += successes + failures
    end

    return 100.0 if total_executions == 0
    (total_successes.to_f / total_executions * 100).round(2)
  rescue => e
    @logger.error "Error calculating system success rate: #{e.message}"
    0.0
  end

  def get_total_cost(time_range)
    providers = get_monitored_providers
    providers.sum { |p| get_cost_last_hour(p) }
  rescue => e
    @logger.error "Error calculating total cost: #{e.message}"
    0.0
  end
end
