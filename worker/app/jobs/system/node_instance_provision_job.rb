# frozen_string_literal: true

module System
  # NodeInstanceProvisionJob - Provisions cloud instances
  #
  # Migrated from legacy powernode-agent Node.do_create_cloud_instance
  # This job creates new cloud instances via the provider API.
  #
  # @example Provision a new instance
  #   System::NodeInstanceProvisionJob.perform_async(node_id, operation_id)
  #
  class NodeInstanceProvisionJob < BaseJob
    include OperationReportingConcern

    sidekiq_options queue: 'system',
                    retry: 1,
                    dead: true

    # Execute instance provisioning
    #
    # @param node_id [String] The node ID to provision instance for
    # @param operation_id [String] The operation ID for tracking
    def execute(node_id, operation_id)
      log_info('Starting instance provisioning', node_id: node_id, operation_id: operation_id)
      start_time = Time.current

      # Mark operation as running
      update_operation_status(operation_id, 'running')

      # Fetch operation details for provisioning config
      operation = fetch_operation(operation_id)
      return handle_operation_not_found(operation_id) unless operation

      # Fetch node details
      node = fetch_node(node_id)
      return handle_node_not_found(node_id, operation_id) unless node

      # Validate prerequisites
      validation = validate_provisioning(node, operation)
      return handle_validation_failure(operation_id, validation) unless validation[:valid]

      # Request backend to provision the instance
      result = provision_instance(node, operation)

      if result['success']
        handle_provision_success(operation_id, result, start_time)
      else
        handle_provision_failure(operation_id, result)
      end
    rescue StandardError => e
      log_error('Instance provisioning failed', e, node_id: node_id, operation_id: operation_id)
      update_operation_status(operation_id, 'failed', error_message: e.message)
      track_error_metric('instance_provision_failed', node_id: node_id)
      raise
    end

    private

    def fetch_operation(operation_id)
      with_api_retry do
        api_client.get("/api/v1/internal/system/operations/#{operation_id}")
      end
    rescue BackendApiClient::ApiError => e
      return nil if e.status == 404

      raise
    end

    def fetch_node(node_id)
      with_api_retry do
        api_client.get("/api/v1/internal/system/nodes/#{node_id}")
      end
    rescue BackendApiClient::ApiError => e
      return nil if e.status == 404

      raise
    end

    def handle_operation_not_found(operation_id)
      log_error('Operation not found', nil, operation_id: operation_id)
      nil
    end

    def handle_node_not_found(node_id, operation_id)
      log_error('Node not found for provisioning', nil, node_id: node_id)
      update_operation_status(operation_id, 'failed', error_message: 'Node not found')
      nil
    end

    def handle_validation_failure(operation_id, validation)
      log_error('Provisioning validation failed', nil, reason: validation[:reason])
      update_operation_status(operation_id, 'failed', error_message: validation[:reason])
      nil
    end

    # Validate provisioning prerequisites
    #
    # @param node [Hash] The node data
    # @param operation [Hash] The operation data
    # @return [Hash] Validation result with :valid and :reason keys
    def validate_provisioning(node, operation)
      # Check instance limit
      if node['instance_count'] >= node['instance_limit']
        return { valid: false, reason: 'Account instance limit exceeded, refusing to create instance.' }
      end

      # Check SSH key availability
      unless node['ssh_key'].present?
        return { valid: false, reason: 'SSH key not configured for node.' }
      end

      # Check required operation options
      options = operation['options'] || {}
      unless options['provider_connection_id'].present?
        return { valid: false, reason: 'Provider connection not specified.' }
      end

      { valid: true }
    end

    # Provision the instance via backend API
    #
    # @param node [Hash] The node data
    # @param operation [Hash] The operation data
    # @return [Hash] Provisioning result
    def provision_instance(node, operation)
      options = operation['options'] || {}

      log_info('Requesting instance provisioning',
               node_id: node['id'],
               provider_connection_id: options['provider_connection_id'],
               provider_region_id: options['provider_region_id'],
               variety: options['variety'])

      # Update operation progress
      update_operation_progress(operation['id'], 20)

      # Request backend to create the cloud instance
      result = with_api_retry do
        api_client.post("/api/v1/internal/system/nodes/#{node['id']}/provision_instance", {
          provider_connection_id: options['provider_connection_id'],
          provider_region_id: options['provider_region_id'],
          provider_availability_zone_id: options['provider_availability_zone_id'],
          provider_instance_type_id: options['provider_instance_type_id'],
          provider_network_id: options['provider_network_id'],
          provider_network_subnet_id: options['provider_network_subnet_id'],
          variety: options['variety'] || 'cloud'
        })
      end

      # Update progress
      update_operation_progress(operation['id'], 80)

      result
    end

    def handle_provision_success(operation_id, result, start_time)
      instance = result['node_instance']
      log_info('Instance provisioned successfully',
               operation_id: operation_id,
               instance_id: instance['id'],
               instance_name: instance['name'])

      # Add success event to operation
      add_operation_event(operation_id, :info,
                          "Created #{instance['variety']} instance #{instance['name']}.")

      # If node has allocate_public_ip, queue IP association
      if result['allocate_public_ip']
        log_info('Queueing public IP association', instance_id: instance['id'])
        System::NodeInstanceIpJob.perform_async(instance['id'], nil, 'associate')
      end

      # Mark operation as complete
      update_operation_status(operation_id, 'complete')

      duration = Time.current - start_time
      track_performance_metric('system_instance_provision_duration', duration)
      increment_counter('system_instances_provisioned')

      { success: true, instance_id: instance['id'], duration: duration }
    end

    def handle_provision_failure(operation_id, result)
      error_message = result['error'] || 'Failed to provision instance'
      log_error('Instance provisioning failed', nil, error: error_message)
      update_operation_status(operation_id, 'failed', error_message: error_message)
      track_error_metric('instance_provision_cloud_failed')
      { success: false, error: error_message }
    end
  end
end
