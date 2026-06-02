# frozen_string_literal: true

module System
  # ModuleCommitJob - Commits module files from instances
  #
  # Migrated from legacy powernode-agent NodeModule.do_commit
  # This job rsyncs files from an instance, creates a squashfs archive,
  # and uploads the module data to the server.
  #
  # @example Commit a module from an instance
  #   System::ModuleCommitJob.perform_async(module_id, operation_id)
  #
  class ModuleCommitJob < BaseJob
    include OperationReportingConcern

    sidekiq_options queue: 'system',
                    retry: 1,
                    dead: true

    # Execute module commit
    #
    # @param module_id [String] The node module ID
    # @param operation_id [String] The operation ID for tracking
    def execute(module_id, operation_id)
      log_info('Starting module commit',
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
      validation = validate_commit(node_module, operation)
      return handle_validation_failure(operation_id, validation) unless validation[:valid]

      # Execute commit via backend (handles rsync, squashfs, upload)
      update_operation_progress(operation_id, 20)
      result = execute_commit(module_id, node_instance_id, operation_id)

      if result['success']
        handle_success(operation_id, node_module, result, start_time)
      else
        handle_failure(operation_id, node_module, result)
      end
    rescue StandardError => e
      log_error('Module commit failed', e, module_id: module_id)
      update_operation_status(operation_id, 'failed', error_message: e.message)
      track_error_metric('module_commit_failed', module_id: module_id)
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
      error_message = 'Node instance not specified for commit'
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
      log_error('Commit validation failed', nil, reason: validation[:reason])
      update_operation_status(operation_id, 'failed', error_message: validation[:reason])
      { success: false, error: validation[:reason] }
    end

    # Validate commit prerequisites
    def validate_commit(node_module, operation)
      # Check for rsync specification
      unless node_module['rsync_spec'].present?
        return { valid: false, reason: 'Commit aborted: No file specification' }
      end

      { valid: true }
    end

    # Execute commit via backend API
    #
    # The backend handles:
    # 1. SSH rsync from instance to temp directory
    # 2. Creating squashfs archive with mksquashfs
    # 3. Uploading module data to storage
    # 4. Cleanup of temp files
    #
    # @param module_id [String] The module ID
    # @param node_instance_id [String] The instance to commit from
    # @param operation_id [String] The operation ID
    # @return [Hash] Commit result
    def execute_commit(module_id, node_instance_id, operation_id)
      log_info('Executing module commit',
               module_id: module_id,
               node_instance_id: node_instance_id)

      result = with_api_retry do
        api_client.post("/api/v1/internal/system/node_modules/#{module_id}/commit", {
          node_instance_id: node_instance_id,
          operation_id: operation_id
        })
      end

      result
    end

    def handle_success(operation_id, node_module, result, start_time)
      log_info('Module commit completed successfully',
               module_id: node_module['id'],
               module_name: node_module['name'])

      update_operation_status(operation_id, 'complete')

      duration = Time.current - start_time
      track_performance_metric('system_module_commit_duration', duration)
      increment_counter('system_module_commits_completed')

      {
        success: true,
        module_id: node_module['id'],
        duration: duration
      }
    end

    def handle_failure(operation_id, node_module, result)
      error_message = result['error'] || "Error committing module #{node_module['name']}"
      log_error('Module commit failed', nil,
                module_id: node_module['id'],
                error: error_message)

      # Add error details to operation events
      if result['output'].present?
        add_operation_event(operation_id, :error, result['output'])
      end

      # Handle partial transfer warning
      if result['exit_code'] == 23
        add_operation_event(operation_id, :warning, "Not all files transferred for module #{node_module['name']}")
      end

      update_operation_status(operation_id, 'failed', error_message: error_message)
      track_error_metric('module_commit_rsync_failed')

      { success: false, error: error_message }
    end
  end
end
