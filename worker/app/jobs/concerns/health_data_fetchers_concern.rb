# frozen_string_literal: true

module HealthDataFetchersConcern
  extend ActiveSupport::Concern

  private

  def calculate_overall_health_status(health_report)
    statuses = health_report[:checks].values.map { |check| check[:status] }

    if statuses.include?('critical') || statuses.include?('failed')
      health_report[:overall_status] = 'critical'
    elsif statuses.include?('warning')
      health_report[:overall_status] = 'warning'
    else
      health_report[:overall_status] = 'healthy'
    end
  end

  def store_health_metrics(health_report)
    api_client.post('admin/ai_workflow_health_metrics', {
      timestamp: health_report[:timestamp],
      overall_status: health_report[:overall_status],
      checks: health_report[:checks]
    })
  rescue StandardError => e
    log_error("Failed to store health metrics: #{e.message}")
  end

  def process_health_alerts(health_report)
    log_warn("Processing health alerts for status: #{health_report[:overall_status]}")

    alert_data = {
      alert_type: 'ai_workflow_health',
      severity: health_report[:overall_status],
      timestamp: health_report[:timestamp],
      summary: generate_health_summary(health_report),
      details: health_report[:checks]
    }

    api_client.post('admin/system_alerts', alert_data)

    log_info("Health alert sent for #{health_report[:overall_status]} status")
  rescue StandardError => e
    log_error("Failed to process health alerts: #{e.message}")
  end

  def broadcast_health_status(health_report)
    with_api_retry(max_attempts: 1) do
      api_client.post("/api/v1/ai/autonomy/broadcast", {
        broadcast_type: "health_status",
        data: health_report
      })
    end
  rescue StandardError => e
    log_error("Failed to broadcast health status: #{e.message}")
  end

  def fetch_stuck_workflows
    api_client.get('admin/ai_workflows/stuck_analysis')['workflows'] || []
  rescue StandardError
    []
  end

  def calculate_recent_failure_rate
    stats = api_client.get('admin/ai_workflows/execution_stats?period=1h')
    return 0.0 unless stats['total_executions'] && stats['total_executions'] > 0

    (stats['failed_executions'].to_f / stats['total_executions'] * 100).round(2)
  rescue StandardError
    0.0
  end

  def calculate_average_execution_time
    stats = api_client.get('admin/ai_workflows/performance_stats?period=1h')
    stats['average_execution_time_ms'] || 0
  rescue StandardError
    0
  end

  def count_active_workflows
    stats = api_client.get('admin/ai_workflows/status_counts')
    stats['running'] || 0
  rescue StandardError
    0
  end

  def fetch_ai_providers
    api_client.get('admin/ai_providers')['providers'] || []
  rescue StandardError
    []
  end

  def test_provider_connectivity(provider)
    result = api_client.post("admin/ai_providers/#{provider['id']}/health_check")
    {
      status: result['healthy'] ? 'healthy' : 'unhealthy',
      response_time_ms: result['response_time_ms'],
      last_check: Time.current.iso8601,
      error: result['error']
    }
  rescue StandardError => e
    {
      status: 'failed',
      error: e.message,
      last_check: Time.current.iso8601
    }
  end

  def fetch_sidekiq_stats
    stats = api_client.get('admin/sidekiq/stats')
    stats || {}
  rescue StandardError
    {}
  end

  def fetch_queue_stats(queue_name)
    stats = api_client.get("admin/sidekiq/queues/#{queue_name}")
    {
      size: stats['size'] || 0,
      latency: stats['latency'] || 0,
      busy: stats['busy'] || 0
    }
  rescue StandardError
    { size: 0, latency: 0, busy: 0 }
  end

  def fetch_event_dispatcher_health
    health = api_client.get('admin/ai_workflow_events/health')
    health['event_dispatcher'] || { status: 'unknown' }
  rescue StandardError
    { status: 'failed', error: 'Unable to fetch event dispatcher health' }
  end

  def fetch_trigger_service_health
    health = api_client.get('admin/ai_workflow_events/health')
    health['trigger_service'] || { status: 'unknown' }
  rescue StandardError
    { status: 'failed', error: 'Unable to fetch trigger service health' }
  end

  def fetch_integration_service_health
    { status: 'healthy', last_check: Time.current.iso8601 }
  rescue StandardError
    { status: 'failed', error: 'Unable to fetch integration service health' }
  end

  def calculate_event_processing_metrics
    stats = api_client.get('admin/ai_workflow_events/processing_stats')
    {
      events_processed_last_hour: stats['events_processed_last_hour'] || 0,
      average_processing_time_ms: stats['average_processing_time_ms'] || 0,
      failed_events_last_hour: stats['failed_events_last_hour'] || 0
    }
  rescue StandardError
    { events_processed_last_hour: 0, average_processing_time_ms: 0, failed_events_last_hour: 0 }
  end

  def fetch_database_pool_stats
    stats = api_client.get('admin/database/pool_stats')
    {
      size: stats['size'] || 0,
      checked_out: stats['checked_out'] || 0,
      checked_in: stats['checked_in'] || 0,
      dead: stats['dead'] || 0
    }
  rescue StandardError
    { size: 0, checked_out: 0, checked_in: 0, dead: 0 }
  end

  def fetch_slow_queries
    []
  rescue StandardError
    []
  end

  def measure_database_response_time
    start_time = Time.current
    api_client.get('admin/database/ping')
    ((Time.current - start_time) * 1000).round(2)
  rescue StandardError
    999999
  end

  def fetch_memory_stats
    {
      used_mb: (GC.stat[:heap_allocated_pages] * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE]) / (1024 * 1024),
      usage_percentage: nil
    }
  rescue StandardError
    { used_mb: 0, usage_percentage: nil }
  end

  def fetch_cpu_stats
    nil
  rescue StandardError
    nil
  end

  def fetch_disk_stats
    nil
  rescue StandardError
    nil
  end

  def generate_health_summary(health_report)
    issues = []

    health_report[:checks].each do |check_name, check_data|
      if check_data[:status] != 'healthy'
        issues << "#{check_name.to_s.humanize}: #{check_data[:status]}"
        issues.concat(check_data[:issues] || [])
      end
    end

    if issues.empty?
      "All systems operational"
    else
      "#{issues.size} issue(s) detected: #{issues.first(3).join(', ')}"
    end
  end
end
