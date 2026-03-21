# frozen_string_literal: true

module System
  # SystemHealthCheckJob - Verifies overall system health
  #
  # This job runs periodically to check the health of nodes and instances,
  # detect anomalies, and queue corrective actions if needed.
  #
  # @example Run health check
  #   System::SystemHealthCheckJob.perform_async
  #
  class SystemHealthCheckJob < BaseJob
    sidekiq_options queue: 'system',
                    retry: 1,
                    dead: false

    # Execute system health check
    def execute
      log_info('Starting system health check')
      start_time = Time.current

      results = {
        nodes_checked: 0,
        instances_checked: 0,
        unhealthy_nodes: 0,
        unhealthy_instances: 0,
        actions_queued: 0
      }

      begin
        # Check all nodes
        nodes = fetch_all_nodes
        results[:nodes_checked] = nodes.size

        nodes.each do |node|
          check_result = check_node_health(node)
          results[:unhealthy_nodes] += 1 unless check_result[:healthy]
          results[:actions_queued] += check_result[:actions_queued]
        end

        # Check all instances
        instances = fetch_all_instances
        results[:instances_checked] = instances.size

        instances.each do |instance|
          check_result = check_instance_health(instance)
          results[:unhealthy_instances] += 1 unless check_result[:healthy]
          results[:actions_queued] += check_result[:actions_queued]
        end

        duration = Time.current - start_time
        log_info('System health check completed',
                 results: results,
                 duration: duration)

        track_performance_metric('system_health_check_duration', duration)
        increment_counter('system_health_check_runs')

        # Track health metrics
        if results[:unhealthy_nodes] > 0
          track_gauge('system_unhealthy_nodes', results[:unhealthy_nodes])
        end
        if results[:unhealthy_instances] > 0
          track_gauge('system_unhealthy_instances', results[:unhealthy_instances])
        end

        results.merge(duration: duration)

      rescue StandardError => e
        log_error('System health check failed', e)
        track_error_metric('system_health_check_failed')
        raise
      end
    end

    private

    def fetch_all_nodes
      with_api_retry do
        response = api_client.get('/api/v1/internal/system/nodes', enabled: true)
        response['nodes'] || []
      end
    rescue BackendApiClient::ApiError => e
      log_error('Failed to fetch nodes for health check', e)
      []
    end

    def fetch_all_instances
      with_api_retry do
        response = api_client.get('/api/v1/internal/system/node_instances', for_health_check: true)
        response['node_instances'] || []
      end
    rescue BackendApiClient::ApiError => e
      log_error('Failed to fetch instances for health check', e)
      []
    end

    def check_node_health(node)
      node_id = node['id']
      healthy = true
      actions_queued = 0

      # Check if node has SSH connectivity issues
      if node['last_ssh_check_failed']
        healthy = false
        log_warn('Node SSH check failed', node_id: node_id, node_name: node['name'])
      end

      # Check if node has stale state
      if node['state_stale']
        healthy = false
        log_warn('Node state is stale', node_id: node_id, node_name: node['name'])

        # Queue maintenance to refresh state
        System::NodeMaintenanceJob.perform_async(node_id)
        actions_queued += 1
      end

      { healthy: healthy, actions_queued: actions_queued }
    rescue StandardError => e
      log_error('Node health check failed', e, node_id: node_id)
      { healthy: false, actions_queued: 0 }
    end

    def check_instance_health(instance)
      instance_id = instance['id']
      healthy = true
      actions_queued = 0

      # Check for orphaned instances (running but node disabled)
      if instance['status'] == 'running' && instance.dig('node', 'enabled') == false
        healthy = false
        log_warn('Instance running on disabled node',
                 instance_id: instance_id,
                 instance_name: instance['name'])
      end

      # Check for instances stuck in transitional states
      if %w[starting stopping].include?(instance['status'])
        transition_duration = Time.current - Time.parse(instance['updated_at']) rescue nil
        if transition_duration && transition_duration > 10.minutes
          healthy = false
          log_warn('Instance stuck in transitional state',
                   instance_id: instance_id,
                   status: instance['status'],
                   duration: transition_duration)

          # Queue maintenance to fix state
          System::NodeInstanceMaintenanceJob.perform_async(instance_id)
          actions_queued += 1
        end
      end

      { healthy: healthy, actions_queued: actions_queued }
    rescue StandardError => e
      log_error('Instance health check failed', e, instance_id: instance_id)
      { healthy: false, actions_queued: 0 }
    end

    def track_gauge(name, value)
      # Track gauge metrics (could be sent to external monitoring)
      log_info('Gauge metric', name: name, value: value)
    end
  end
end
