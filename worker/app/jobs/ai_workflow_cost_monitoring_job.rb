# frozen_string_literal: true

# Background job to monitor AI workflow costs and trigger alerts on anomalies
# Runs every hour to track spending patterns and detect unusual cost spikes
class AiWorkflowCostMonitoringJob < BaseJob
  queue_as :ai_workflow_health

  # Cost thresholds for alerts
  HOURLY_COST_WARNING_THRESHOLD = 50.0     # $50/hour warning
  HOURLY_COST_CRITICAL_THRESHOLD = 100.0   # $100/hour critical
  DAILY_COST_WARNING_THRESHOLD = 500.0     # $500/day warning
  DAILY_COST_CRITICAL_THRESHOLD = 1000.0   # $1000/day critical
  COST_SPIKE_PERCENTAGE = 200              # 200% increase triggers alert

  def execute
    log_info("Starting AI Workflow Cost Monitoring")

    cost_report = {
      timestamp: Time.current.iso8601,
      status: 'healthy',
      metrics: {},
      alerts: [],
      provider_costs: {}
    }

    begin
      # Fetch cost data from backend
      fetch_hourly_costs(cost_report)
      fetch_daily_costs(cost_report)
      fetch_provider_breakdown(cost_report)

      # Analyze for anomalies
      detect_cost_anomalies(cost_report)

      # Calculate cost projections
      calculate_projections(cost_report)

      # Determine overall status
      determine_status(cost_report)

      # Store metrics
      store_cost_metrics(cost_report)

      # Process alerts if needed
      process_cost_alerts(cost_report) if cost_report[:alerts].any?

      # Broadcast cost status
      broadcast_cost_status(cost_report)

      log_info("AI Workflow Cost Monitoring completed: #{cost_report[:status]}")
    rescue StandardError => e
      log_error("AI Workflow Cost Monitoring failed", e)
      cost_report[:status] = 'error'
      cost_report[:error] = e.message
    end

    cost_report
  end

  private

  def fetch_hourly_costs(cost_report)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/cost_summary', { period: '1h' })
    end

    cost_report[:metrics][:hourly] = {
      total_cost: response['total_cost'] || 0.0,
      token_cost: response['token_cost'] || 0.0,
      api_call_cost: response['api_call_cost'] || 0.0,
      execution_count: response['execution_count'] || 0,
      average_cost_per_execution: response['average_cost_per_execution'] || 0.0
    }
  rescue StandardError => e
    log_error("Failed to fetch hourly costs", e)
    cost_report[:metrics][:hourly] = { error: e.message }
  end

  def fetch_daily_costs(cost_report)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/cost_summary', { period: '24h' })
    end

    cost_report[:metrics][:daily] = {
      total_cost: response['total_cost'] || 0.0,
      token_cost: response['token_cost'] || 0.0,
      api_call_cost: response['api_call_cost'] || 0.0,
      execution_count: response['execution_count'] || 0,
      average_cost_per_execution: response['average_cost_per_execution'] || 0.0
    }

    # Fetch previous day for comparison
    yesterday_response = with_api_retry do
      api_client.get('admin/ai_workflows/cost_summary', {
        period: '24h',
        start_date: 1.day.ago.beginning_of_day.iso8601,
        end_date: 1.day.ago.end_of_day.iso8601
      })
    end

    cost_report[:metrics][:previous_day] = {
      total_cost: yesterday_response['total_cost'] || 0.0
    }
  rescue StandardError => e
    log_error("Failed to fetch daily costs", e)
    cost_report[:metrics][:daily] = { error: e.message }
  end

  def fetch_provider_breakdown(cost_report)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/cost_by_provider', { period: '24h' })
    end

    providers = response['providers'] || []
    providers.each do |provider|
      cost_report[:provider_costs][provider['name']] = {
        total_cost: provider['total_cost'] || 0.0,
        token_count: provider['token_count'] || 0,
        api_calls: provider['api_calls'] || 0,
        cost_per_1k_tokens: provider['cost_per_1k_tokens'] || 0.0
      }
    end
  rescue StandardError => e
    log_error("Failed to fetch provider breakdown", e)
  end

  def detect_cost_anomalies(cost_report)
    hourly = cost_report[:metrics][:hourly] || {}
    daily = cost_report[:metrics][:daily] || {}
    previous_day = cost_report[:metrics][:previous_day] || {}

    # Check hourly thresholds
    hourly_cost = hourly[:total_cost] || 0.0
    if hourly_cost >= HOURLY_COST_CRITICAL_THRESHOLD
      cost_report[:alerts] << {
        type: 'hourly_cost_critical',
        severity: 'critical',
        message: "Hourly cost ($#{hourly_cost.round(2)}) exceeds critical threshold ($#{HOURLY_COST_CRITICAL_THRESHOLD})",
        value: hourly_cost,
        threshold: HOURLY_COST_CRITICAL_THRESHOLD
      }
    elsif hourly_cost >= HOURLY_COST_WARNING_THRESHOLD
      cost_report[:alerts] << {
        type: 'hourly_cost_warning',
        severity: 'warning',
        message: "Hourly cost ($#{hourly_cost.round(2)}) exceeds warning threshold ($#{HOURLY_COST_WARNING_THRESHOLD})",
        value: hourly_cost,
        threshold: HOURLY_COST_WARNING_THRESHOLD
      }
    end

    # Check daily thresholds
    daily_cost = daily[:total_cost] || 0.0
    if daily_cost >= DAILY_COST_CRITICAL_THRESHOLD
      cost_report[:alerts] << {
        type: 'daily_cost_critical',
        severity: 'critical',
        message: "Daily cost ($#{daily_cost.round(2)}) exceeds critical threshold ($#{DAILY_COST_CRITICAL_THRESHOLD})",
        value: daily_cost,
        threshold: DAILY_COST_CRITICAL_THRESHOLD
      }
    elsif daily_cost >= DAILY_COST_WARNING_THRESHOLD
      cost_report[:alerts] << {
        type: 'daily_cost_warning',
        severity: 'warning',
        message: "Daily cost ($#{daily_cost.round(2)}) exceeds warning threshold ($#{DAILY_COST_WARNING_THRESHOLD})",
        value: daily_cost,
        threshold: DAILY_COST_WARNING_THRESHOLD
      }
    end

    # Check for cost spike compared to previous day
    previous_cost = previous_day[:total_cost] || 0.0
    if previous_cost.positive? && daily_cost.positive?
      percentage_change = ((daily_cost - previous_cost) / previous_cost * 100).round(1)
      cost_report[:metrics][:day_over_day_change] = percentage_change

      if percentage_change >= COST_SPIKE_PERCENTAGE
        cost_report[:alerts] << {
          type: 'cost_spike',
          severity: 'warning',
          message: "Cost spike detected: #{percentage_change}% increase from previous day",
          value: percentage_change,
          threshold: COST_SPIKE_PERCENTAGE,
          previous_cost: previous_cost,
          current_cost: daily_cost
        }
      end
    end
  end

  def calculate_projections(cost_report)
    daily = cost_report[:metrics][:daily] || {}
    hourly = cost_report[:metrics][:hourly] || {}

    # Project monthly cost based on current daily rate
    daily_cost = daily[:total_cost] || 0.0
    cost_report[:metrics][:projected_monthly_cost] = (daily_cost * 30).round(2)

    # Project weekly cost
    cost_report[:metrics][:projected_weekly_cost] = (daily_cost * 7).round(2)

    # Calculate run rate (cost per hour extrapolated)
    hourly_cost = hourly[:total_cost] || 0.0
    cost_report[:metrics][:hourly_run_rate] = hourly_cost.round(2)
    cost_report[:metrics][:daily_run_rate] = (hourly_cost * 24).round(2)
  end

  def determine_status(cost_report)
    alerts = cost_report[:alerts] || []

    if alerts.any? { |a| a[:severity] == 'critical' }
      cost_report[:status] = 'critical'
    elsif alerts.any? { |a| a[:severity] == 'warning' }
      cost_report[:status] = 'warning'
    else
      cost_report[:status] = 'healthy'
    end
  end

  def store_cost_metrics(cost_report)
    with_api_retry do
      api_client.post('admin/ai_workflow_cost_metrics', {
        timestamp: cost_report[:timestamp],
        status: cost_report[:status],
        metrics: cost_report[:metrics],
        provider_costs: cost_report[:provider_costs]
      })
    end
  rescue StandardError => e
    log_error("Failed to store cost metrics", e)
  end

  def process_cost_alerts(cost_report)
    cost_report[:alerts].each do |alert|
      begin
        with_api_retry do
          api_client.post('admin/system_alerts', {
            alert_type: 'ai_workflow_cost',
            severity: alert[:severity],
            category: 'cost_monitoring',
            title: alert[:type].to_s.humanize,
            message: alert[:message],
            metadata: alert
          })
        end
        log_info("Sent cost alert: #{alert[:type]} (#{alert[:severity]})")
      rescue StandardError => e
        log_error("Failed to send cost alert: #{alert[:type]}", e)
      end
    end
  end

  def broadcast_cost_status(cost_report)
    # Broadcast via WebSocket for real-time monitoring dashboards
    begin
      AiWorkflowMonitoringChannel.broadcast_cost_status(cost_report)
    rescue StandardError => e
      log_error("Failed to broadcast cost status", e)
    end
  end
end
