# frozen_string_literal: true

module System
  # NodeInstanceControlJob - Controls instance lifecycle (start/stop/reboot/terminate)
  #
  # Migrated from legacy powernode-agent NodeInstance.do_start, do_stop, do_reboot, do_terminate
  # This job handles instance lifecycle operations via the cloud provider.
  #
  # @example Start an instance
  #   System::NodeInstanceControlJob.perform_async(instance_id, operation_id, 'start')
  #
  # @example Terminate an instance
  #   System::NodeInstanceControlJob.perform_async(instance_id, operation_id, 'terminate')
  #
  class NodeInstanceControlJob < BaseJob
    include OperationReportingConcern

    VALID_COMMANDS = %w[start stop reboot terminate].freeze

    sidekiq_options queue: 'system',
                    retry: 2,
                    dead: true

    # Execute instance control command
    #
    # @param instance_id [String] The node instance ID
    # @param operation_id [String, nil] Optional operation ID for tracking
    # @param command [String] The command to execute (start, stop, reboot, terminate)
    def execute(instance_id, operation_id = nil, command = nil)
      # Handle case where command is passed as second argument (no operation_id)
      if operation_id && !VALID_COMMANDS.include?(operation_id) && command.nil?
        # operation_id is actually the command
        command = operation_id
        operation_id = nil
      end

      validate_command!(command)

      log_info("Executing instance #{command}",
               instance_id: instance_id,
               operation_id: operation_id,
               command: command)
      start_time = Time.current

      # Mark operation as running
      update_operation_status(operation_id, 'running') if operation_id

      # Fetch instance details
      instance = fetch_instance(instance_id)
      return handle_not_found(instance_id, operation_id) unless instance

      # Execute the command via backend
      result = execute_control_command(instance, command)

      if result['success']
        handle_success(operation_id, command, instance, start_time)
      else
        handle_failure(operation_id, command, instance, result)
      end
    rescue ArgumentError => e
      log_error('Invalid command', e, instance_id: instance_id, command: command)
      update_operation_status(operation_id, 'failed', error_message: e.message) if operation_id
      raise
    rescue StandardError => e
      log_error("Instance #{command} failed", e, instance_id: instance_id)
      update_operation_status(operation_id, 'failed', error_message: e.message) if operation_id
      track_error_metric("instance_#{command}_failed", instance_id: instance_id)
      raise
    end

    private

    def validate_command!(command)
      return if VALID_COMMANDS.include?(command)

      raise ArgumentError, "Invalid command: #{command}. Valid commands: #{VALID_COMMANDS.join(', ')}"
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
      nil
    end

    # Execute the control command via backend API
    #
    # @param instance [Hash] The instance data
    # @param command [String] The command to execute
    # @return [Hash] Command result
    def execute_control_command(instance, command)
      instance_id = instance['id']

      log_info("Requesting #{command} for instance",
               instance_id: instance_id,
               instance_name: instance['name'])

      with_api_retry do
        api_client.post("/api/v1/internal/system/node_instances/#{instance_id}/#{command}")
      end
    end

    def handle_success(operation_id, command, instance, start_time)
      instance_id = instance['id']
      instance_name = instance['name']

      log_info("Instance #{command} completed successfully",
               instance_id: instance_id,
               instance_name: instance_name)

      update_operation_status(operation_id, 'complete') if operation_id

      duration = Time.current - start_time
      track_performance_metric("system_instance_#{command}_duration", duration)
      increment_counter("system_instance_#{command}_completed")

      { success: true, instance_id: instance_id, command: command, duration: duration }
    end

    def handle_failure(operation_id, command, instance, result)
      error_message = result['error'] || "Failed to #{command} instance #{instance['name']}"
      log_error("Instance #{command} failed", nil,
                instance_id: instance['id'],
                error: error_message)

      update_operation_status(operation_id, 'failed', error_message: error_message) if operation_id
      track_error_metric("instance_#{command}_cloud_failed")

      { success: false, error: error_message }
    end
  end
end
