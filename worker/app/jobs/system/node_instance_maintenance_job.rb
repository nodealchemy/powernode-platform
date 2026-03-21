# frozen_string_literal: true

module System
  # NodeInstanceMaintenanceJob - Maintains node instance state
  #
  # Migrated from legacy powernode-agent NodeInstance.do_maintenance
  # This job syncs cloud instance state (IPs, status) and handles netboot for physical instances.
  #
  # @example Execute maintenance for an instance
  #   System::NodeInstanceMaintenanceJob.perform_async(instance_id)
  #
  class NodeInstanceMaintenanceJob < BaseJob
    sidekiq_options queue: 'system',
                    retry: 2,
                    dead: true

    # Execute instance maintenance
    #
    # @param instance_id [String] The node instance ID to maintain
    # @param operation_id [String, nil] Optional operation ID for tracking
    def execute(instance_id, operation_id = nil)
      log_info('Starting instance maintenance', instance_id: instance_id)
      start_time = Time.current

      # Fetch instance details
      instance = fetch_instance(instance_id)
      return handle_not_found(instance_id) unless instance

      case instance['variety']
      when 'cloud', 'dynamic'
        maintain_cloud_instance(instance)
      when 'physical'
        maintain_physical_instance(instance)
      end

      duration = Time.current - start_time
      track_performance_metric('system_instance_maintenance_duration', duration, instance_id: instance_id)
      increment_counter('system_instance_maintenance_completed', variety: instance['variety'])

      log_info('Instance maintenance completed', instance_id: instance_id, duration: duration)
      { instance_id: instance_id, duration: duration, variety: instance['variety'] }
    rescue StandardError => e
      log_error('Instance maintenance failed', e, instance_id: instance_id)
      track_error_metric('instance_maintenance_failed', instance_id: instance_id)
      raise
    end

    private

    # Fetch instance details from backend
    def fetch_instance(instance_id)
      with_api_retry do
        api_client.get("/api/v1/internal/system/node_instances/#{instance_id}")
      end
    rescue BackendApiClient::ApiError => e
      return nil if e.status == 404

      raise
    end

    def handle_not_found(instance_id)
      log_warn('Instance not found for maintenance', instance_id: instance_id)
      nil
    end

    # Maintain a cloud/dynamic instance
    #
    # @param instance [Hash] The instance data
    def maintain_cloud_instance(instance)
      instance_id = instance['id']
      log_info('Maintaining cloud instance', instance_id: instance_id)

      # Request backend to sync instance state from cloud provider
      result = with_api_retry do
        api_client.post("/api/v1/internal/system/node_instances/#{instance_id}/sync_cloud_state")
      end

      if result['status'] == 'terminated'
        log_info('Instance terminated, requesting cleanup', instance_id: instance_id)
        # Request backend to destroy the instance record
        with_api_retry do
          api_client.delete("/api/v1/internal/system/node_instances/#{instance_id}")
        end
        increment_counter('system_terminated_instances_cleaned')
      elsif result['updated']
        log_info('Instance state updated',
                 instance_id: instance_id,
                 status: result['status'],
                 private_ip: result['private_ip_address'],
                 public_ip: result['public_ip_address'])
        increment_counter('system_instance_state_updated')
      end
    end

    # Maintain a physical instance (netboot sync)
    #
    # @param instance [Hash] The instance data
    def maintain_physical_instance(instance)
      instance_id = instance['id']

      unless instance['private_netboot_enabled']
        log_info('Netboot not enabled, skipping', instance_id: instance_id)
        return
      end

      log_info('Syncing netboot configuration', instance_id: instance_id)

      # Request backend to sync netboot configuration
      with_api_retry do
        api_client.post("/api/v1/internal/system/node_instances/#{instance_id}/sync_netboot")
      end

      increment_counter('system_netboot_synced')
    end
  end
end
