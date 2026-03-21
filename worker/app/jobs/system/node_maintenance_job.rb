# frozen_string_literal: true

module System
  # NodeMaintenanceJob - Maintains node state and cascades to instances
  #
  # Migrated from legacy powernode-agent Node.do_maintenance
  # This job processes node maintenance, updating instance states and
  # terminating dynamic instances if the node is disabled.
  #
  # @example Execute maintenance for a node
  #   System::NodeMaintenanceJob.perform_async(node_id)
  #
  class NodeMaintenanceJob < BaseJob
    sidekiq_options queue: 'system',
                    retry: 2,
                    dead: true

    # Execute node maintenance
    #
    # @param node_id [String] The node ID to maintain
    # @param operation_id [String, nil] Optional operation ID for tracking
    def execute(node_id, operation_id = nil)
      log_info('Starting node maintenance', node_id: node_id, operation_id: operation_id)
      start_time = Time.current

      # Mark operation as running if provided
      update_operation_status(operation_id, 'running') if operation_id

      # Fetch node details
      node = fetch_node(node_id)
      return handle_node_not_found(node_id, operation_id) unless node

      if node['enabled']
        maintain_enabled_node(node)
      else
        handle_disabled_node(node)
      end

      duration = Time.current - start_time
      track_performance_metric('system_node_maintenance_duration', duration, node_id: node_id)
      increment_counter('system_node_maintenance_completed')

      # Mark operation as complete
      update_operation_status(operation_id, 'complete') if operation_id

      log_info('Node maintenance completed', node_id: node_id, duration: duration)
      { node_id: node_id, duration: duration }
    rescue StandardError => e
      log_error('Node maintenance failed', e, node_id: node_id)
      update_operation_status(operation_id, 'failed', error_message: e.message) if operation_id
      track_error_metric('node_maintenance_failed', node_id: node_id)
      raise
    end

    private

    # Fetch node details from backend
    #
    # @param node_id [String] The node ID
    # @return [Hash, nil] Node data or nil if not found
    def fetch_node(node_id)
      with_api_retry do
        api_client.get("/api/v1/internal/system/nodes/#{node_id}")
      end
    rescue BackendApiClient::ApiError => e
      return nil if e.status == 404

      raise
    end

    # Handle case when node is not found
    def handle_node_not_found(node_id, operation_id)
      log_warn('Node not found for maintenance', node_id: node_id)
      update_operation_status(operation_id, 'failed', error_message: 'Node not found') if operation_id
      nil
    end

    # Maintain an enabled node by cascading to all instances
    #
    # @param node [Hash] The node data
    def maintain_enabled_node(node)
      node_id = node['id']
      log_info('Maintaining enabled node', node_id: node_id)

      # Fetch all instances for this node
      instances = with_api_retry do
        api_client.get('/api/v1/internal/system/node_instances', {
          node_id: node_id
        })
      end

      instance_list = instances['node_instances'] || []
      log_info("Found #{instance_list.size} instances", node_id: node_id)

      # Queue maintenance job for each instance
      instance_list.each do |instance|
        System::NodeInstanceMaintenanceJob.perform_async(instance['id'])
      end

      increment_counter('system_node_instances_queued', count: instance_list.size)
    end

    # Handle a disabled node by terminating dynamic instances
    #
    # @param node [Hash] The node data
    def handle_disabled_node(node)
      node_id = node['id']
      log_info('Handling disabled node', node_id: node_id)

      # Fetch dynamic instances for this node
      instances = with_api_retry do
        api_client.get('/api/v1/internal/system/node_instances', {
          node_id: node_id,
          variety: 'dynamic'
        })
      end

      instance_list = instances['node_instances'] || []
      return if instance_list.empty?

      log_info("Terminating #{instance_list.size} dynamic instances", node_id: node_id)

      # Queue termination for each dynamic instance
      instance_list.each do |instance|
        System::NodeInstanceControlJob.perform_async(instance['id'], nil, 'terminate')
      end

      increment_counter('system_dynamic_instances_terminated', count: instance_list.size)
    end

    # Update operation status via API
    #
    # @param operation_id [String] The operation ID
    # @param status [String] The new status
    # @param error_message [String, nil] Optional error message for failed status
    def update_operation_status(operation_id, status, error_message: nil)
      return unless operation_id

      with_api_retry do
        api_client.patch("/api/v1/internal/system/operations/#{operation_id}", {
          status: status,
          error_message: error_message,
          updated_at: Time.current.iso8601
        }.compact)
      end
    rescue StandardError => e
      log_warn('Failed to update operation status', operation_id: operation_id, error: e.message)
    end
  end
end
