# frozen_string_literal: true

module System
  # NodeInstanceExecJob - Executes commands on instances via SSH
  #
  # Migrated from legacy powernode-agent NodeInstance.do_exec
  # This job executes arbitrary commands on instances with proper sudo handling.
  #
  # @example Execute a command on an instance
  #   System::NodeInstanceExecJob.perform_async(instance_id, operation_id, 'ls -la /var/log')
  #
  class NodeInstanceExecJob < BaseJob
    include OperationReportingConcern

    sidekiq_options queue: 'system',
                    retry: 1,
                    dead: true

    # Execute command on instance
    #
    # @param instance_id [String] The node instance ID
    # @param operation_id [String] The operation ID for tracking
    # @param command [String, nil] The command to execute (from params or operation options)
    def execute(instance_id, operation_id, command = nil)
      log_info('Starting remote command execution',
               instance_id: instance_id,
               operation_id: operation_id)
      start_time = Time.current

      # Mark operation as running
      update_operation_status(operation_id, 'running')

      # Get command from operation if not provided
      if command.nil?
        operation = fetch_operation(operation_id)
        return handle_operation_not_found(operation_id) unless operation

        command = operation.dig('options', 'exec') || operation.dig('options', 'command')
      end

      unless command.present?
        return handle_missing_command(operation_id)
      end

      # Fetch instance details
      instance = fetch_instance(instance_id)
      return handle_instance_not_found(instance_id, operation_id) unless instance

      log_info("Executing command on #{instance['name']}", command: command)

      # Update progress
      update_operation_progress(operation_id, 20)

      # Execute via backend API (which handles SSH)
      result = execute_ssh_command(instance_id, command, operation_id)

      if result['success']
        handle_success(operation_id, instance, command, result, start_time)
      else
        handle_failure(operation_id, instance, command, result)
      end
    rescue StandardError => e
      log_error('Command execution failed', e, instance_id: instance_id)
      update_operation_status(operation_id, 'failed', error_message: e.message)
      track_error_metric('instance_exec_failed', instance_id: instance_id)
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

    def fetch_instance(instance_id)
      with_api_retry do
        api_client.get("/api/v1/internal/system/node_instances/#{instance_id}")
      end
    rescue BackendApiClient::ApiError => e
      return nil if e.status == 404

      raise
    end

    def handle_operation_not_found(operation_id)
      log_error('Operation not found', nil, operation_id: operation_id)
      nil
    end

    def handle_missing_command(operation_id)
      error_message = 'No command specified for execution'
      log_error(error_message, nil, operation_id: operation_id)
      update_operation_status(operation_id, 'failed', error_message: error_message)
      { success: false, error: error_message }
    end

    def handle_instance_not_found(instance_id, operation_id)
      error_message = 'Instance not found'
      log_warn(error_message, instance_id: instance_id)
      update_operation_status(operation_id, 'failed', error_message: error_message)
      { success: false, error: error_message }
    end

    # Execute SSH command via backend API
    #
    # @param instance_id [String] The instance ID
    # @param command [String] The command to execute
    # @param operation_id [String] The operation ID
    # @return [Hash] Execution result
    def execute_ssh_command(instance_id, command, operation_id)
      with_api_retry do
        api_client.post("/api/v1/internal/system/node_instances/#{instance_id}/ssh_exec", {
          command: command,
          operation_id: operation_id,
          sudo: true
        })
      end
    end

    def handle_success(operation_id, instance, command, result, start_time)
      log_info('Command executed successfully',
               instance_id: instance['id'],
               instance_name: instance['name'],
               exit_code: result['exit_code'])

      # Add output to operation events if present
      if result['stdout'].present?
        add_operation_event(operation_id, :info, "Output:\n#{result['stdout']}")
      end

      if result['stderr'].present? && result['stderr'].strip.present?
        add_operation_event(operation_id, :warning, "Stderr:\n#{result['stderr']}")
      end

      update_operation_status(operation_id, 'complete')

      duration = Time.current - start_time
      track_performance_metric('system_instance_exec_duration', duration)
      increment_counter('system_instance_exec_completed')

      {
        success: true,
        instance_id: instance['id'],
        exit_code: result['exit_code'],
        stdout: result['stdout'],
        stderr: result['stderr'],
        duration: duration
      }
    end

    def handle_failure(operation_id, instance, command, result)
      error_message = result['error'] || "Failed to execute #{command} on #{instance['name']}"
      log_error('Command execution failed', nil,
                instance_id: instance['id'],
                command: command,
                error: error_message)

      # Add error output to operation events
      if result['stderr'].present?
        add_operation_event(operation_id, :error, "Error:\n#{result['stderr']}")
      end

      update_operation_status(operation_id, 'failed', error_message: error_message)
      track_error_metric('instance_exec_ssh_failed')

      { success: false, error: error_message, stderr: result['stderr'] }
    end
  end
end
