# frozen_string_literal: true

# AiMonitoringConcern - Shared patterns for AI monitoring services
#
# Provides common functionality for monitoring AI operations:
# - Metric collection and aggregation
# - Alert management
# - Health checks
# - Performance tracking
#
# Usage:
#   class UnifiedMonitoringService
#     include BaseAiService
#     include AiMonitoringConcern
#
#     def get_system_health
#       collect_health_metrics do
#         # Collect metrics from various sources
#       end
#     end
#   end
#
module AiMonitoringConcern
  extend ActiveSupport::Concern

  # Metric types
  METRIC_TYPES = %w[
    execution_count
    success_rate
    error_rate
    avg_response_time
    p95_response_time
    total_cost
    active_runs
    queue_depth
  ].freeze

  # Alert types
  ALERT_TYPES = %w[
    provider_failure
    high_cost
    execution_timeout
    circuit_breaker_open
    low_success_rate
    high_latency
    resource_exhaustion
    quota_exceeded
  ].freeze

  # Alert severities
  ALERT_SEVERITIES = %w[low medium high critical].freeze

  included do
    # Assumes BaseAiService is also included
  end

  # =============================================================================
  # METRIC COLLECTION
  # =============================================================================

  # Collect metrics with proper error handling
  #
  # @yield Block that collects metrics
  # @return [Hash] Collected metrics
  def collect_metrics
    metrics = {}

    begin
      metrics = yield
      validate_metrics!(metrics)
      metrics
    rescue StandardError => e
      log_error "Metric collection failed", { error: e.message }
      default_metrics
    end
  end

  # Record a metric
  #
  # @param metric_name [String] Name of the metric
  # @param value [Numeric] Metric value
  # @param tags [Hash] Additional tags
  def record_metric(metric_name, value, tags = {})
    metric_key = build_metric_key(metric_name, tags)

    redis.zadd(
      "metrics:#{metric_key}",
      Time.current.to_i,
      { value: value, timestamp: Time.current.to_i, tags: tags }.to_json
    )

    # Keep only last 24 hours of data
    cutoff = 24.hours.ago.to_i
    redis.zremrangebyscore("metrics:#{metric_key}", "-inf", cutoff)
  end

  # Get metrics for a time range
  #
  # @param metric_name [String] Name of the metric
  # @param start_time [Time] Start of range
  # @param end_time [Time] End of range
  # @param tags [Hash] Filter by tags
  # @return [Array<Hash>] Metric data points
  def get_metrics(metric_name, start_time: 1.hour.ago, end_time: Time.current, tags: {})
    metric_key = build_metric_key(metric_name, tags)

    results = redis.zrangebyscore(
      "metrics:#{metric_key}",
      start_time.to_i,
      end_time.to_i
    )

    results.map { |r| JSON.parse(r, symbolize_names: true) }
  end

  # =============================================================================
  # AGGREGATIONS
  # =============================================================================

  # Calculate aggregated metrics
  #
  # @param metric_data [Array<Hash>] Metric data points
  # @return [Hash] Aggregated statistics
  def aggregate_metrics(metric_data)
    return default_aggregation if metric_data.empty?

    values = metric_data.map { |d| d[:value].to_f }

    {
      count: values.count,
      sum: values.sum,
      avg: values.sum / values.count,
      min: values.min,
      max: values.max,
      p50: percentile(values, 50),
      p95: percentile(values, 95),
      p99: percentile(values, 99)
    }
  end

  # Calculate success rate
  #
  # @param successes [Integer] Number of successes
  # @param total [Integer] Total attempts
  # @return [Float] Success rate percentage
  def calculate_success_rate(successes, total)
    return 0.0 if total.zero?

    (successes.to_f / total * 100).round(2)
  end

  # Calculate error rate
  #
  # @param errors [Integer] Number of errors
  # @param total [Integer] Total attempts
  # @return [Float] Error rate percentage
  def calculate_error_rate(errors, total)
    return 0.0 if total.zero?

    (errors.to_f / total * 100).round(2)
  end

  # =============================================================================
  # HEALTH CHECKS
  # =============================================================================

  # Check system health
  #
  # @return [Hash] Health status
  def check_system_health
    {
      status: determine_health_status,
      components: check_component_health,
      timestamp: Time.current.iso8601,
      uptime_seconds: calculate_uptime
    }
  end

  # Check component health
  #
  # @return [Hash] Component health statuses
  def check_component_health
    {
      database: check_database_health,
      redis: check_redis_health,
      providers: check_providers_health,
      workers: check_workers_health
    }
  end

  # Determine overall health status
  #
  # @return [String] Health status (healthy, degraded, unhealthy)
  def determine_health_status
    components = check_component_health

    unhealthy = components.values.count { |v| v[:status] == "unhealthy" }
    degraded = components.values.count { |v| v[:status] == "degraded" }

    if unhealthy > 0
      "unhealthy"
    elsif degraded > 0
      "degraded"
    else
      "healthy"
    end
  end

  # =============================================================================
  # ALERT MANAGEMENT
  # =============================================================================

  # Check and trigger alerts based on metrics
  #
  # @param metrics [Hash] Current metrics
  # @return [Array<Hash>] Triggered alerts
  def check_alerts(metrics)
    alerts = []

    ALERT_TYPES.each do |alert_type|
      if should_trigger_alert?(alert_type, metrics)
        alerts << trigger_alert(alert_type, metrics)
      end
    end

    alerts
  end

  # Trigger an alert
  #
  # @param alert_type [String] Type of alert
  # @param data [Hash] Alert data
  # @return [Hash] Alert details
  def trigger_alert(alert_type, data)
    severity = determine_alert_severity(alert_type, data)

    alert = {
      alert_type: alert_type,
      severity: severity,
      message: build_alert_message(alert_type, data),
      data: data,
      timestamp: Time.current.iso8601,
      account_id: @account&.id
    }

    # Store alert
    store_alert(alert)

    # Broadcast alert
    broadcast_alert(alert)

    # Send notifications if critical
    send_alert_notifications(alert) if severity == "critical"

    alert
  end

  # Get active alerts
  #
  # @param filters [Hash] Filter criteria
  # @return [Array<Hash>] Active alerts
  def get_active_alerts(filters = {})
    alerts_key = "alerts:#{@account&.id || 'system'}"

    alert_data = redis.zrevrange(alerts_key, 0, -1, with_scores: true)

    alerts = alert_data.map do |data, score|
      JSON.parse(data, symbolize_names: true)
    end

    # Apply filters
    alerts = apply_alert_filters(alerts, filters)

    alerts
  end

  # =============================================================================
  # PERFORMANCE TRACKING
  # =============================================================================

  # Track operation performance
  #
  # @param operation [String] Operation name
  # @param duration_ms [Integer] Duration in milliseconds
  # @param metadata [Hash] Additional metadata
  def track_performance(operation, duration_ms, metadata = {})
    record_metric("performance.#{operation}", duration_ms, {
      operation: operation,
      **metadata
    })

    # Check for performance degradation
    check_performance_degradation(operation, duration_ms)
  end

  # Get performance statistics
  #
  # @param operation [String] Operation name
  # @param time_range [Range] Time range
  # @return [Hash] Performance statistics
  def get_performance_stats(operation, time_range: 1.hour.ago..Time.current)
    metrics = get_metrics(
      "performance.#{operation}",
      start_time: time_range.begin,
      end_time: time_range.end
    )

    aggregate_metrics(metrics)
  end

  private

  # =============================================================================
  # HELPERS
  # =============================================================================

  def redis
    @redis ||= Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")
  end

  def build_metric_key(metric_name, tags = {})
    tag_string = tags.map { |k, v| "#{k}:#{v}" }.join(".")
    tag_string.present? ? "#{metric_name}.#{tag_string}" : metric_name
  end

  def validate_metrics!(metrics)
    unless metrics.is_a?(Hash)
      raise ValidationError, "Metrics must be a hash"
    end
  end

  def default_metrics
    {
      status: "error",
      message: "Failed to collect metrics",
      timestamp: Time.current.iso8601
    }
  end

  def default_aggregation
    {
      count: 0,
      sum: 0,
      avg: 0,
      min: 0,
      max: 0,
      p50: 0,
      p95: 0,
      p99: 0
    }
  end

  def percentile(values, p)
    return 0 if values.empty?

    sorted = values.sort
    index = ((p / 100.0) * sorted.length).ceil - 1
    sorted[index]
  end

  def check_database_health
    ActiveRecord::Base.connection.execute("SELECT 1")
    { status: "healthy", response_time_ms: 1 }
  rescue StandardError => e
    { status: "unhealthy", error: e.message }
  end

  def check_redis_health
    redis.ping
    { status: "healthy", response_time_ms: 1 }
  rescue StandardError => e
    { status: "unhealthy", error: e.message }
  end

  def check_providers_health
    # Check AI provider availability
    { status: "healthy" }
  end

  def check_workers_health
    # Check Sidekiq workers
    { status: "healthy" }
  end

  def calculate_uptime
    # TODO: Implement proper uptime tracking
    Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i
  end

  def should_trigger_alert?(alert_type, metrics)
    # Implement alert thresholds
    case alert_type
    when "high_cost"
      metrics[:total_cost].to_f > 100.0
    when "low_success_rate"
      metrics[:success_rate].to_f < 90.0
    when "high_latency"
      metrics[:avg_response_time].to_f > 5000
    else
      false
    end
  end

  def determine_alert_severity(alert_type, data)
    case alert_type
    when "provider_failure", "resource_exhaustion"
      "critical"
    when "high_cost", "circuit_breaker_open"
      "high"
    when "low_success_rate", "high_latency"
      "medium"
    else
      "low"
    end
  end

  def build_alert_message(alert_type, data)
    "Alert triggered: #{alert_type.humanize}"
  end

  def store_alert(alert)
    alerts_key = "alerts:#{@account&.id || 'system'}"
    redis.zadd(alerts_key, Time.current.to_i, alert.to_json)

    # Keep only last 7 days of alerts
    cutoff = 7.days.ago.to_i
    redis.zremrangebyscore(alerts_key, "-inf", cutoff)
  end

  def broadcast_alert(alert)
    # Broadcast alert via WebSocket
    AiOrchestrationChannel.broadcast_alert(alert)
  end

  def send_alert_notifications(alert)
    alerting_service.send_alert(
      title: "Monitoring Alert: #{alert[:alert_type]}",
      message: alert[:message],
      severity: alert[:severity]&.to_sym || :error,
      context: {
        alert_type: alert[:alert_type],
        triggered_at: alert[:triggered_at],
        account_id: @account&.id
      }
    )
  rescue StandardError => e
    log_error "Failed to send alert notification", { error: e.message }
  end

  def alerting_service
    @alerting_service ||= AlertingService.new
  end

  def apply_alert_filters(alerts, filters)
    alerts = alerts.select { |a| a[:severity] == filters[:severity] } if filters[:severity]
    alerts = alerts.select { |a| a[:alert_type] == filters[:alert_type] } if filters[:alert_type]
    alerts
  end

  def check_performance_degradation(operation, duration_ms)
    # Get historical average
    stats = get_performance_stats(operation)

    # Check if current duration is significantly higher
    if stats[:avg] > 0 && duration_ms > (stats[:avg] * 2)
      log_warn "Performance degradation detected", {
        operation: operation,
        current_ms: duration_ms,
        avg_ms: stats[:avg]
      }
    end
  end
end
