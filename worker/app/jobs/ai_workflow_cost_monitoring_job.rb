# frozen_string_literal: true

# Background job to monitor AI workflow costs and trigger alerts on anomalies
# Runs every hour to track spending patterns and detect unusual cost spikes
class AiWorkflowCostMonitoringJob < BaseJob
  sidekiq_options queue: :ai_workflow_health

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
      # Fetch configurable thresholds from backend
      @thresholds = fetch_cost_thresholds

      # Fetch cost data from backend
      fetch_hourly_costs(cost_report)
      fetch_daily_costs(cost_report)
      fetch_provider_breakdown(cost_report)

      # Analyze for anomalies
      detect_cost_anomalies(cost_report)

      # Check per-agent budget alerts
      check_agent_budget_alerts(cost_report)

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

    hourly_warning = @thresholds['hourly_warning'] || 50.0
    hourly_critical = @thresholds['hourly_critical'] || 100.0
    daily_warning = @thresholds['daily_warning'] || 500.0
    daily_critical = @thresholds['daily_critical'] || 1000.0
    spike_pct = @thresholds['spike_percentage'] || 200

    # Check hourly thresholds
    hourly_cost = hourly[:total_cost] || 0.0
    if hourly_cost >= hourly_critical
      cost_report[:alerts] << {
        type: 'hourly_cost_critical',
        severity: 'critical',
        message: "Hourly cost ($#{hourly_cost.round(2)}) exceeds critical threshold ($#{hourly_critical})",
        value: hourly_cost,
        threshold: hourly_critical
      }
    elsif hourly_cost >= hourly_warning
      cost_report[:alerts] << {
        type: 'hourly_cost_warning',
        severity: 'warning',
        message: "Hourly cost ($#{hourly_cost.round(2)}) exceeds warning threshold ($#{hourly_warning})",
        value: hourly_cost,
        threshold: hourly_warning
      }
    end

    # Check daily thresholds
    daily_cost = daily[:total_cost] || 0.0
    if daily_cost >= daily_critical
      cost_report[:alerts] << {
        type: 'daily_cost_critical',
        severity: 'critical',
        message: "Daily cost ($#{daily_cost.round(2)}) exceeds critical threshold ($#{daily_critical})",
        value: daily_cost,
        threshold: daily_critical
      }
    elsif daily_cost >= daily_warning
      cost_report[:alerts] << {
        type: 'daily_cost_warning',
        severity: 'warning',
        message: "Daily cost ($#{daily_cost.round(2)}) exceeds warning threshold ($#{daily_warning})",
        value: daily_cost,
        threshold: daily_warning
      }
    end

    # Check for cost spike compared to previous day
    previous_cost = previous_day[:total_cost] || 0.0
    if previous_cost.positive? && daily_cost.positive?
      percentage_change = ((daily_cost - previous_cost) / previous_cost * 100).round(1)
      cost_report[:metrics][:day_over_day_change] = percentage_change

      if percentage_change >= spike_pct
        cost_report[:alerts] << {
          type: 'cost_spike',
          severity: 'warning',
          message: "Cost spike detected: #{percentage_change}% increase from previous day",
          value: percentage_change,
          threshold: spike_pct,
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

  def check_agent_budget_alerts(cost_report)
    response = with_api_retry do
      api_client.get('ai/autonomy/budgets/alerts')
    end

    budget_alerts = response['data'] || []
    budget_alerts.each do |alert|
      severity = case alert['level']
                 when 'exhausted' then 'critical'
                 when 'danger' then 'warning'
                 else 'info'
                 end

      cost_report[:alerts] << {
        type: "agent_budget_#{alert['level']}",
        severity: severity,
        message: "Agent '#{alert['agent_name']}' budget at #{alert['utilization_pct']&.round(1)}% (#{alert['remaining_cents']} cents remaining)",
        value: alert['utilization_pct'],
        agent_id: alert['agent_id'],
        budget_id: alert['budget_id']
      }
    end
  rescue StandardError => e
    log_error("Failed to check agent budget alerts", e)
  end

  def broadcast_cost_status(cost_report)
    with_api_retry(max_attempts: 1) do
      api_client.post("/api/v1/ai/autonomy/broadcast", {
        broadcast_type: "cost_status",
        data: cost_report
      })
    end
  rescue StandardError => e
    log_error("Failed to broadcast cost status", e)
  end

  def fetch_cost_thresholds
    response = api_client.get("/api/v1/ai/autonomy/cost_thresholds")
    if response['success']
      response['data']
    else
      default_thresholds
    end
  rescue StandardError
    default_thresholds
  end

  def default_thresholds
    {
      'hourly_warning' => 50.0, 'hourly_critical' => 100.0,
      'daily_warning' => 500.0, 'daily_critical' => 1000.0,
      'spike_percentage' => 200
    }
  end
end
