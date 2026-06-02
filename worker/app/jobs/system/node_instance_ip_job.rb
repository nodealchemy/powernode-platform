# frozen_string_literal: true

module System
  # NodeInstanceIpJob - Manages public IP association/disassociation
  #
  # Migrated from legacy powernode-agent NodeInstance.do_public_ip_associate, do_public_ip_disassociate
  # This job handles elastic/public IP operations for cloud instances.
  #
  # @example Associate a public IP
  #   System::NodeInstanceIpJob.perform_async(instance_id, operation_id, 'associate')
  #
  # @example Disassociate a public IP
  #   System::NodeInstanceIpJob.perform_async(instance_id, operation_id, 'disassociate')
  #
  class NodeInstanceIpJob < BaseJob
    include OperationReportingConcern

    VALID_ACTIONS = %w[associate disassociate].freeze

    sidekiq_options queue: 'system',
                    retry: 2,
                    dead: true

    # Execute IP action
    #
    # @param instance_id [String] The node instance ID
    # @param operation_id [String, nil] Optional operation ID for tracking
    # @param action [String] The action (associate, disassociate)
    def execute(instance_id, operation_id = nil, action = 'associate')
      validate_action!(action)

      log_info("Executing public IP #{action}",
               instance_id: instance_id,
               operation_id: operation_id,
               action: action)
      start_time = Time.current

      update_operation_status(operation_id, 'running') if operation_id

      # Fetch instance details
      instance = fetch_instance(instance_id)
      return handle_not_found(instance_id, operation_id) unless instance

      # Execute action via backend
      result = case action
               when 'associate'
                 associate_public_ip(instance, operation_id)
               when 'disassociate'
                 disassociate_public_ip(instance, operation_id)
               end

      if result[:success]
        handle_success(operation_id, action, instance, result, start_time)
      else
        handle_failure(operation_id, action, instance, result)
      end
    rescue ArgumentError => e
      log_error('Invalid action', e, action: action)
      update_operation_status(operation_id, 'failed', error_message: e.message) if operation_id
      raise
    rescue StandardError => e
      log_error("Public IP #{action} failed", e, instance_id: instance_id)
      update_operation_status(operation_id, 'failed', error_message: e.message) if operation_id
      track_error_metric("instance_ip_#{action}_failed")
      raise
    end

    private

    def validate_action!(action)
      return if VALID_ACTIONS.include?(action)

      raise ArgumentError, "Invalid action: #{action}. Valid: #{VALID_ACTIONS.join(', ')}"
    end

    def fetch_instance(instance_id)
      with_api_retry do
        api_client.get("/api/v1/internal/system/node_instances/#{instance_id}")
      end
    rescue BackendApiClient::ApiError => e
      return nil if e.status == 404

      raise
    end

    def handle_not_found(instance_id, operation_id)
      log_warn('Instance not found', instance_id: instance_id)
      update_operation_status(operation_id, 'failed', error_message: 'Instance not found') if operation_id
      { success: false, error: 'Instance not found' }
    end

    # Associate a public IP to the instance
    #
    # @param instance [Hash] The instance data
    # @param operation_id [String, nil] The operation ID
    # @return [Hash] Result with :success, :ip, :error keys
    def associate_public_ip(instance, operation_id)
      instance_id = instance['id']
      log_info('Associating public IP', instance_id: instance_id)

      # Request backend to handle IP allocation/association
      result = with_api_retry do
        api_client.post("/api/v1/internal/system/node_instances/#{instance_id}/associate_public_ip")
      end

      if result['success']
        log_info('Public IP associated',
                 instance_id: instance_id,
                 public_ip: result['public_ip_address'])
        { success: true, ip: result['public_ip_address'] }
      else
        error_message = result['error'] || "Unable to associate IP for instance #{instance['name']}"
        { success: false, error: error_message }
      end
    end

    # Disassociate a public IP from the instance
    #
    # @param instance [Hash] The instance data
    # @param operation_id [String, nil] The operation ID
    # @return [Hash] Result with :success, :error keys
    def disassociate_public_ip(instance, operation_id)
      instance_id = instance['id']
      public_ip = instance['public_ip_address']

      unless public_ip.present?
        log_info('No public IP to disassociate', instance_id: instance_id)
        return { success: true, message: 'No public IP associated' }
      end

      log_info('Disassociating public IP',
               instance_id: instance_id,
               public_ip: public_ip)

      # Request backend to handle IP disassociation
      result = with_api_retry do
        api_client.post("/api/v1/internal/system/node_instances/#{instance_id}/disassociate_public_ip")
      end

      if result['success']
        log_info('Public IP disassociated', instance_id: instance_id)
        { success: true }
      else
        error_message = result['error'] || "Unable to disassociate IP for instance #{instance['name']}"
        { success: false, error: error_message }
      end
    end

    def handle_success(operation_id, action, instance, result, start_time)
      log_info("Public IP #{action} completed",
               instance_id: instance['id'],
               instance_name: instance['name'])

      update_operation_status(operation_id, 'complete') if operation_id

      duration = Time.current - start_time
      track_performance_metric("system_instance_ip_#{action}_duration", duration)
      increment_counter("system_instance_ip_#{action}_completed")

      result.merge(duration: duration, instance_id: instance['id'])
    end

    def handle_failure(operation_id, action, instance, result)
      log_error("Public IP #{action} failed", nil,
                instance_id: instance['id'],
                error: result[:error])

      update_operation_status(operation_id, 'failed', error_message: result[:error]) if operation_id
      track_error_metric("instance_ip_#{action}_cloud_failed")

      result
    end
  end
end
