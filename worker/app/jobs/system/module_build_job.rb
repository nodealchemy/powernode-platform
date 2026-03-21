# frozen_string_literal: true

module System
  # ModuleBuildJob - Builds node modules on instances
  #
  # Migrated from legacy powernode-agent NodeModule.do_build
  # This job executes package installation scripts on instances and captures file specs.
  #
  # @example Build a module
  #   System::ModuleBuildJob.perform_async(module_id, operation_id)
  #
  class ModuleBuildJob < BaseJob
    sidekiq_options queue: 'system',
                    retry: 1,
                    dead: true

    # Execute module build
    #
    # @param module_id [String] The node module ID
    # @param operation_id [String] The operation ID for tracking
    def execute(module_id, operation_id)
      log_info('Starting module build',
               module_id: module_id,
               operation_id: operation_id)
      start_time = Time.current

      update_operation_status(operation_id, 'running')

      # Fetch operation to get node_instance_id
      operation = fetch_operation(operation_id)
      return handle_operation_not_found(operation_id) unless operation

      node_instance_id = operation.dig('options', 'node_instance_id')
      unless node_instance_id
        return handle_missing_instance(operation_id)
      end

      # Fetch module details
      node_module = fetch_module(module_id)
      return handle_module_not_found(module_id, operation_id) unless node_module

      # Validate prerequisites
      validation = validate_build(node_module, operation)
      return handle_validation_failure(operation_id, validation) unless validation[:valid]

      # Execute build via backend
      update_operation_progress(operation_id, 20)
      result = execute_build(module_id, node_instance_id, operation_id)

      if result['success']
        handle_success(operation_id, node_module, result, start_time)
      else
        handle_failure(operation_id, node_module, result)
      end
    rescue StandardError => e
      log_error('Module build failed', e, module_id: module_id)
      update_operation_status(operation_id, 'failed', error_message: e.message)
      track_error_metric('module_build_failed', module_id: module_id)
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

    def fetch_module(module_id)
      with_api_retry do
        api_client.get("/api/v1/internal/system/node_modules/#{module_id}")
      end
    rescue BackendApiClient::ApiError => e
      return nil if e.status == 404

      raise
    end

    def handle_operation_not_found(operation_id)
      log_error('Operation not found', nil, operation_id: operation_id)
      nil
    end

    def handle_missing_instance(operation_id)
      error_message = 'Node instance not specified for build'
      log_error(error_message, nil, operation_id: operation_id)
      update_operation_status(operation_id, 'failed', error_message: error_message)
      { success: false, error: error_message }
    end

    def handle_module_not_found(module_id, operation_id)
      error_message = 'Module not found'
      log_error(error_message, nil, module_id: module_id)
      update_operation_status(operation_id, 'failed', error_message: error_message)
      { success: false, error: error_message }
    end

    def handle_validation_failure(operation_id, validation)
      log_error('Build validation failed', nil, reason: validation[:reason])
      update_operation_status(operation_id, 'failed', error_message: validation[:reason])
      { success: false, error: validation[:reason] }
    end

    # Validate build prerequisites
    def validate_build(node_module, operation)
      # Check for package specification
      unless node_module['package_spec'].present?
        return { valid: false, reason: 'Build aborted: No package specification' }
      end

      { valid: true }
    end

    # Execute build via backend API
    #
    # @param module_id [String] The module ID
    # @param node_instance_id [String] The instance to build on
    # @param operation_id [String] The operation ID
    # @return [Hash] Build result
    def execute_build(module_id, node_instance_id, operation_id)
      log_info('Executing module build',
               module_id: module_id,
               node_instance_id: node_instance_id)

      # Request backend to execute SSH build
      result = with_api_retry do
        api_client.post("/api/v1/internal/system/node_modules/#{module_id}/build", {
          node_instance_id: node_instance_id,
          operation_id: operation_id
        })
      end

      result
    end

    def handle_success(operation_id, node_module, result, start_time)
      log_info('Module build completed successfully',
               module_id: node_module['id'],
               module_name: node_module['name'])

      update_operation_status(operation_id, 'complete')

      duration = Time.current - start_time
      track_performance_metric('system_module_build_duration', duration)
      increment_counter('system_module_builds_completed')

      {
        success: true,
        module_id: node_module['id'],
        duration: duration
      }
    end

    def handle_failure(operation_id, node_module, result)
      error_message = result['error'] || "Error installing packages for module #{node_module['name']}"
      log_error('Module build failed', nil,
                module_id: node_module['id'],
                error: error_message)

      # Add error details to operation events
      if result['output'].present?
        add_operation_event(operation_id, :error, result['output'])
      end

      update_operation_status(operation_id, 'failed', error_message: error_message)
      track_error_metric('module_build_package_failed')

      { success: false, error: error_message }
    end

    def update_operation_status(operation_id, status, error_message: nil)
      return unless operation_id

      with_api_retry do
        api_client.patch("/api/v1/internal/system/operations/#{operation_id}", {
          status: status,
          error_message: error_message,
          completed_at: %w[complete failed].include?(status) ? Time.current.iso8601 : nil
        }.compact)
      end
    rescue StandardError => e
      log_warn('Failed to update operation status', operation_id: operation_id, error: e.message)
    end

    def update_operation_progress(operation_id, progress)
      return unless operation_id

      with_api_retry do
        api_client.patch("/api/v1/internal/system/operations/#{operation_id}", {
          progress: progress
        })
      end
    rescue StandardError => e
      log_warn('Failed to update operation progress', operation_id: operation_id, error: e.message)
    end

    def add_operation_event(operation_id, event_type, message)
      return unless operation_id

      with_api_retry do
        api_client.post("/api/v1/internal/system/operations/#{operation_id}/events", {
          event_type: event_type,
          message: message,
          timestamp: Time.current.iso8601
        })
      end
    rescue StandardError => e
      log_warn('Failed to add operation event', operation_id: operation_id, error: e.message)
    end
  end
end
