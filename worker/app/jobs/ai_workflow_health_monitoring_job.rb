# frozen_string_literal: true

class AiWorkflowHealthMonitoringJob < BaseJob
  include HealthCheckStepsConcern
  include HealthDataFetchersConcern

  sidekiq_options queue: :ai_workflow_health

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
  rescue StandardError => e
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
end
