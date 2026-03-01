# frozen_string_literal: true

module HealthCheckStepsConcern
  extend ActiveSupport::Concern

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
      if failure_rate > 10.0
        check_result[:status] = 'critical' if failure_rate > 25.0
        check_result[:status] = 'warning' if check_result[:status] != 'critical'
        check_result[:issues] << "High failure rate: #{failure_rate.round(1)}%"
      end
      check_result[:metrics][:failure_rate] = failure_rate

      # Check average execution time
      avg_execution_time = calculate_average_execution_time
      if avg_execution_time > 300_000
        check_result[:status] = 'warning'
        check_result[:issues] << "High average execution time: #{avg_execution_time}ms"
      end
      check_result[:metrics][:avg_execution_time_ms] = avg_execution_time

      # Check active workflow count
      active_workflows = count_active_workflows
      check_result[:metrics][:active_workflows] = active_workflows

    rescue StandardError => e
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

      if check_result[:metrics][:failed_providers] > 0
        failure_percentage = (check_result[:metrics][:failed_providers].to_f / check_result[:metrics][:total_providers]) * 100

        if failure_percentage > 50
          check_result[:status] = 'critical'
        elsif failure_percentage > 25
          check_result[:status] = 'warning'
        end
      end

    rescue StandardError => e
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
      stats = fetch_sidekiq_stats

      check_result[:metrics] = {
        total_jobs: stats['processed'] || 0,
        failed_jobs: stats['failed'] || 0,
        retry_jobs: stats['retry_size'] || 0,
        dead_jobs: stats['dead_size'] || 0,
        busy_workers: stats['busy'] || 0,
        enqueued_jobs: stats['enqueued'] || 0
      }

      ai_workflow_queues = %w[ai_workflow_execution ai_workflow_node ai_workflow_schedule ai_workflow_health]
      ai_workflow_queues.each do |queue_name|
        queue_stats = fetch_queue_stats(queue_name)
        check_result[:queues][queue_name] = queue_stats
      end

      if check_result[:metrics][:retry_jobs] > 100
        check_result[:status] = 'warning'
      end

      if check_result[:metrics][:dead_jobs] > 50
        check_result[:status] = 'critical'
      end

    rescue StandardError => e
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
      dispatcher_health = fetch_event_dispatcher_health
      check_result[:components][:event_dispatcher] = dispatcher_health

      trigger_health = fetch_trigger_service_health
      check_result[:components][:trigger_service] = trigger_health

      integration_health = fetch_integration_service_health
      check_result[:components][:integration_service] = integration_health

      event_metrics = calculate_event_processing_metrics
      check_result[:metrics] = event_metrics

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

    rescue StandardError => e
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
      pool_stats = fetch_database_pool_stats
      check_result[:metrics][:connection_pool] = pool_stats

      slow_queries = fetch_slow_queries
      check_result[:slow_queries] = slow_queries.first(5)

      response_time = measure_database_response_time
      check_result[:metrics][:avg_response_time_ms] = response_time

      if response_time > 1000
        check_result[:status] = 'critical'
      elsif response_time > 500
        check_result[:status] = 'warning'
      end

      if slow_queries.size > 10
        check_result[:status] = 'warning' if check_result[:status] == 'healthy'
      end

    rescue StandardError => e
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
      memory_stats = fetch_memory_stats
      check_result[:metrics][:memory] = memory_stats

      cpu_stats = fetch_cpu_stats
      check_result[:metrics][:cpu] = cpu_stats if cpu_stats

      disk_stats = fetch_disk_stats
      check_result[:metrics][:disk] = disk_stats if disk_stats

      if memory_stats[:usage_percentage] && memory_stats[:usage_percentage] > 90
        check_result[:status] = 'critical'
      elsif memory_stats[:usage_percentage] && memory_stats[:usage_percentage] > 80
        check_result[:status] = 'warning'
      end

    rescue StandardError => e
      check_result[:status] = 'failed'
      check_result[:error] = e.message
      log_error("Resource utilization check failed: #{e.message}")
    end

    health_report[:checks][:resource_utilization] = check_result
  end
end
