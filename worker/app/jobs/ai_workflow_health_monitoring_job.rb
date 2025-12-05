# frozen_string_literal: true

class AiWorkflowHealthMonitoringJob < BaseJob
  queue_as :ai_workflow_health

  def execute
    log_info("Starting AI Workflow Health Monitoring check")
    
    health_report = {
      timestamp: Time.current.iso8601,
      overall_status: 'healthy',
      checks: {}
    }

    # Perform system health checks
    check_workflow_execution_health(health_report)
    check_provider_connectivity(health_report)
    check_worker_queue_health(health_report)
    check_event_system_health(health_report)
    check_database_performance(health_report)
    check_resource_utilization(health_report)
    
    # Calculate overall system health
    calculate_overall_health_status(health_report)
    
    # Store health metrics
    store_health_metrics(health_report)
    
    # Trigger alerts if needed
    process_health_alerts(health_report) if health_report[:overall_status] != 'healthy'
    
    # Broadcast health status
    broadcast_health_status(health_report)
    
    log_info("AI Workflow Health Monitoring completed: #{health_report[:overall_status]}")
    
    health_report
  rescue => e
    log_error("AI Workflow Health Monitoring failed: #{e.message}")
    log_error(e.backtrace.join("\n"))

    emergency_health_report = {
      timestamp: Time.current.iso8601,
      overall_status: 'critical',
      error: e.message,
      checks: { monitoring_system: { status: 'failed', error: e.message } }
    }
    
    broadcast_health_status(emergency_health_report)
    raise
  end

  private

  def check_workflow_execution_health(health_report)
    logger.debug "Checking workflow execution health"
    
    check_result = {
      status: 'healthy',
      metrics: {},
      issues: []
    }

    begin
      # Check for stuck workflows
      stuck_workflows = fetch_stuck_workflows
      if stuck_workflows.any?
        check_result[:status] = 'warning'
        check_result[:issues] << "#{stuck_workflows.size} workflows appear stuck"
        check_result[:metrics][:stuck_workflows] = stuck_workflows.size
      end

      # Check failure rate
      failure_rate = calculate_recent_failure_rate
      if failure_rate > 10.0 # 10% threshold
        check_result[:status] = 'critical' if failure_rate > 25.0
        check_result[:status] = 'warning' if check_result[:status] != 'critical'
        check_result[:issues] << "High failure rate: #{failure_rate.round(1)}%"
      end
      check_result[:metrics][:failure_rate] = failure_rate

      # Check average execution time
      avg_execution_time = calculate_average_execution_time
      if avg_execution_time > 300_000 # 5 minutes
        check_result[:status] = 'warning'
        check_result[:issues] << "High average execution time: #{avg_execution_time}ms"
      end
      check_result[:metrics][:avg_execution_time_ms] = avg_execution_time

      # Check active workflow count
      active_workflows = count_active_workflows
      check_result[:metrics][:active_workflows] = active_workflows

    rescue => e
      check_result[:status] = 'failed'
      check_result[:error] = e.message
      log_error("Workflow execution health check failed: #{e.message}")
    end

    health_report[:checks][:workflow_execution] = check_result
  end

  def check_provider_connectivity(health_report)
    logger.debug "Checking AI provider connectivity"
    
    check_result = {
      status: 'healthy',
      providers: {},
      metrics: { total_providers: 0, healthy_providers: 0, failed_providers: 0 }
    }

    begin
      providers = fetch_ai_providers
      check_result[:metrics][:total_providers] = providers.size

      providers.each do |provider|
        provider_status = test_provider_connectivity(provider)
        check_result[:providers][provider['name']] = provider_status
        
        if provider_status[:status] == 'healthy'
          check_result[:metrics][:healthy_providers] += 1
        else
          check_result[:metrics][:failed_providers] += 1
        end
      end

      # Determine overall provider health
      if check_result[:metrics][:failed_providers] > 0
        failure_percentage = (check_result[:metrics][:failed_providers].to_f / check_result[:metrics][:total_providers]) * 100
        
        if failure_percentage > 50
          check_result[:status] = 'critical'
        elsif failure_percentage > 25
          check_result[:status] = 'warning'
        end
      end

    rescue => e
      check_result[:status] = 'failed'
      check_result[:error] = e.message
      log_error("Provider connectivity check failed: #{e.message}")
    end

    health_report[:checks][:provider_connectivity] = check_result
  end

  def check_worker_queue_health(health_report)
    logger.debug "Checking worker queue health"
    
    check_result = {
      status: 'healthy',
      queues: {},
      metrics: { total_jobs: 0, failed_jobs: 0, retry_jobs: 0, dead_jobs: 0 }
    }

    begin
      # Check Sidekiq queue stats
      stats = fetch_sidekiq_stats
      
      check_result[:metrics] = {
        total_jobs: stats['processed'] || 0,
        failed_jobs: stats['failed'] || 0,
        retry_jobs: stats['retry_size'] || 0,
        dead_jobs: stats['dead_size'] || 0,
        busy_workers: stats['busy'] || 0,
        enqueued_jobs: stats['enqueued'] || 0
      }

      # Check individual queues
      ai_workflow_queues = %w[ai_workflow_execution ai_workflow_node ai_workflow_schedule ai_workflow_health]
      ai_workflow_queues.each do |queue_name|
        queue_stats = fetch_queue_stats(queue_name)
        check_result[:queues][queue_name] = queue_stats
      end

      # Determine queue health
      if check_result[:metrics][:retry_jobs] > 100
        check_result[:status] = 'warning'
      end
      
      if check_result[:metrics][:dead_jobs] > 50
        check_result[:status] = 'critical'
      end

    rescue => e
      check_result[:status] = 'failed'
      check_result[:error] = e.message
      log_error("Worker queue health check failed: #{e.message}")
    end

    health_report[:checks][:worker_queues] = check_result
  end

  def check_event_system_health(health_report)
    logger.debug "Checking event system health"
    
    check_result = {
      status: 'healthy',
      metrics: {},
      components: {}
    }

    begin
      # Check event dispatcher health
      dispatcher_health = fetch_event_dispatcher_health
      check_result[:components][:event_dispatcher] = dispatcher_health
      
      # Check trigger service health
      trigger_health = fetch_trigger_service_health
      check_result[:components][:trigger_service] = trigger_health
      
      # Check integration service health
      integration_health = fetch_integration_service_health
      check_result[:components][:integration_service] = integration_health
      
      # Calculate event processing metrics
      event_metrics = calculate_event_processing_metrics
      check_result[:metrics] = event_metrics
      
      # Determine overall event system health
      # Note: API responses use string keys, hardcoded hashes use symbol keys - check both
      failed_components = [dispatcher_health, trigger_health, integration_health].count do |c|
        status = c['status'] || c[:status]
        status != 'healthy'
      end
      
      if failed_components > 1
        check_result[:status] = 'critical'
      elsif failed_components > 0
        check_result[:status] = 'warning'
      end

    rescue => e
      check_result[:status] = 'failed'
      check_result[:error] = e.message
      log_error("Event system health check failed: #{e.message}")
    end

    health_report[:checks][:event_system] = check_result
  end

  def check_database_performance(health_report)
    logger.debug "Checking database performance"
    
    check_result = {
      status: 'healthy',
      metrics: {},
      slow_queries: []
    }

    begin
      # Check connection pool health
      pool_stats = fetch_database_pool_stats
      check_result[:metrics][:connection_pool] = pool_stats
      
      # Check for slow queries
      slow_queries = fetch_slow_queries
      check_result[:slow_queries] = slow_queries.first(5) # Top 5 slow queries
      
      # Check database response time
      response_time = measure_database_response_time
      check_result[:metrics][:avg_response_time_ms] = response_time
      
      # Determine database health
      if response_time > 1000 # 1 second
        check_result[:status] = 'critical'
      elsif response_time > 500 # 500ms
        check_result[:status] = 'warning'
      end
      
      if slow_queries.size > 10
        check_result[:status] = 'warning' if check_result[:status] == 'healthy'
      end

    rescue => e
      check_result[:status] = 'failed'
      check_result[:error] = e.message
      log_error("Database performance check failed: #{e.message}")
    end

    health_report[:checks][:database_performance] = check_result
  end

  def check_resource_utilization(health_report)
    logger.debug "Checking resource utilization"
    
    check_result = {
      status: 'healthy',
      metrics: {}
    }

    begin
      # Check memory usage
      memory_stats = fetch_memory_stats
      check_result[:metrics][:memory] = memory_stats
      
      # Check CPU usage (if available)
      cpu_stats = fetch_cpu_stats
      check_result[:metrics][:cpu] = cpu_stats if cpu_stats
      
      # Check disk usage for logs and temp files
      disk_stats = fetch_disk_stats
      check_result[:metrics][:disk] = disk_stats if disk_stats
      
      # Determine resource health
      if memory_stats[:usage_percentage] && memory_stats[:usage_percentage] > 90
        check_result[:status] = 'critical'
      elsif memory_stats[:usage_percentage] && memory_stats[:usage_percentage] > 80
        check_result[:status] = 'warning'
      end

    rescue => e
      check_result[:status] = 'failed'
      check_result[:error] = e.message
      log_error("Resource utilization check failed: #{e.message}")
    end

    health_report[:checks][:resource_utilization] = check_result
  end

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
    # Store health metrics via API for historical tracking
    api_client.post('admin/ai_workflow_health_metrics', {
      timestamp: health_report[:timestamp],
      overall_status: health_report[:overall_status],
      checks: health_report[:checks]
    })
  rescue => e
    log_error("Failed to store health metrics: #{e.message}")
  end

  def process_health_alerts(health_report)
    log_warn("Processing health alerts for status: #{health_report[:overall_status]}")
    
    # Create alert data
    alert_data = {
      alert_type: 'ai_workflow_health',
      severity: health_report[:overall_status],
      timestamp: health_report[:timestamp],
      summary: generate_health_summary(health_report),
      details: health_report[:checks]
    }

    # Send alerts via API
    api_client.post('admin/system_alerts', alert_data)
    
    log_info("Health alert sent for #{health_report[:overall_status]} status")
  rescue => e
    log_error("Failed to process health alerts: #{e.message}")
  end

  def broadcast_health_status(health_report)
    # Broadcast via WebSocket for real-time monitoring
    AiWorkflowMonitoringChannel.broadcast_health_status(health_report)
  rescue => e
    log_error("Failed to broadcast health status: #{e.message}")
  end

  # Helper methods for fetching health data

  def fetch_stuck_workflows
    api_client.get('admin/ai_workflows/stuck_analysis')['workflows'] || []
  rescue
    []
  end

  def calculate_recent_failure_rate
    stats = api_client.get('admin/ai_workflows/execution_stats?period=1h')
    return 0.0 unless stats['total_executions'] && stats['total_executions'] > 0
    
    (stats['failed_executions'].to_f / stats['total_executions'] * 100).round(2)
  rescue
    0.0
  end

  def calculate_average_execution_time
    stats = api_client.get('admin/ai_workflows/performance_stats?period=1h')
    stats['average_execution_time_ms'] || 0
  rescue
    0
  end

  def count_active_workflows
    stats = api_client.get('admin/ai_workflows/status_counts')
    stats['running'] || 0
  rescue
    0
  end

  def fetch_ai_providers
    api_client.get('admin/ai_providers')['providers'] || []
  rescue
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
  rescue => e
    {
      status: 'failed',
      error: e.message,
      last_check: Time.current.iso8601
    }
  end

  def fetch_sidekiq_stats
    stats = api_client.get('admin/sidekiq/stats')
    stats || {}
  rescue
    {}
  end

  def fetch_queue_stats(queue_name)
    stats = api_client.get("admin/sidekiq/queues/#{queue_name}")
    {
      size: stats['size'] || 0,
      latency: stats['latency'] || 0,
      busy: stats['busy'] || 0
    }
  rescue
    { size: 0, latency: 0, busy: 0 }
  end

  def fetch_event_dispatcher_health
    health = api_client.get('admin/ai_workflow_events/health')
    health['event_dispatcher'] || { status: 'unknown' }
  rescue
    { status: 'failed', error: 'Unable to fetch event dispatcher health' }
  end

  def fetch_trigger_service_health
    health = api_client.get('admin/ai_workflow_events/health')
    health['trigger_service'] || { status: 'unknown' }
  rescue
    { status: 'failed', error: 'Unable to fetch trigger service health' }
  end

  def fetch_integration_service_health
    # Integration service health would be checked here
    { status: 'healthy', last_check: Time.current.iso8601 }
  rescue
    { status: 'failed', error: 'Unable to fetch integration service health' }
  end

  def calculate_event_processing_metrics
    stats = api_client.get('admin/ai_workflow_events/processing_stats')
    {
      events_processed_last_hour: stats['events_processed_last_hour'] || 0,
      average_processing_time_ms: stats['average_processing_time_ms'] || 0,
      failed_events_last_hour: stats['failed_events_last_hour'] || 0
    }
  rescue
    { events_processed_last_hour: 0, average_processing_time_ms: 0, failed_events_last_hour: 0 }
  end

  def fetch_database_pool_stats
    {
      size: ActiveRecord::Base.connection_pool.size,
      checked_out: ActiveRecord::Base.connection_pool.stat[:busy],
      checked_in: ActiveRecord::Base.connection_pool.stat[:idle],
      dead: ActiveRecord::Base.connection_pool.stat[:dead]
    }
  rescue
    { size: 0, checked_out: 0, checked_in: 0, dead: 0 }
  end

  def fetch_slow_queries
    # This would integrate with database monitoring tools
    # For now, return empty array
    []
  rescue
    []
  end

  def measure_database_response_time
    start_time = Time.current
    # Simple query to test database responsiveness
    api_client.get('admin/database/ping')
    ((Time.current - start_time) * 1000).round(2)
  rescue
    999999 # Return high value if unable to measure
  end

  def fetch_memory_stats
    # Basic memory stats - would integrate with system monitoring
    {
      used_mb: (GC.stat[:heap_allocated_pages] * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE]) / (1024 * 1024),
      usage_percentage: nil # Would need system integration
    }
  rescue
    { used_mb: 0, usage_percentage: nil }
  end

  def fetch_cpu_stats
    # Would integrate with system monitoring tools
    nil
  rescue
    nil
  end

  def fetch_disk_stats
    # Would integrate with system monitoring tools  
    nil
  rescue
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