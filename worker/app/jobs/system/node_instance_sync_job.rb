# frozen_string_literal: true

module System
  # NodeInstanceSyncJob - Syncs instance state or executes sync/cleanse commands
  #
  # Migrated from legacy powernode-agent NodeInstance.do_sync, do_cleanse, Node.do_sync_cloud_instances
  # This job handles instance synchronization via SSH or cloud state sync.
  #
  # @example Sync a single instance
  #   System::NodeInstanceSyncJob.perform_async(instance_id, operation_id, 'sync')
  #
  # @example Cleanse an instance
  #   System::NodeInstanceSyncJob.perform_async(instance_id, operation_id, 'cleanse')
  #
  # @example Sync all cloud instances for a node
  #   System::NodeInstanceSyncJob.perform_async(nil, operation_id, 'sync_all', node_id: node_id)
  #
  class NodeInstanceSyncJob < BaseJob
    VALID_COMMANDS = %w[sync cleanse sync_all].freeze

    sidekiq_options queue: 'system',
                    retry: 2,
                    dead: true

    # Execute sync command
    #
    # @param instance_id [String, nil] The node instance ID (nil for sync_all)
    # @param operation_id [String, nil] Optional operation ID for tracking
    # @param command [String] The command (sync, cleanse, sync_all)
    # @param options [Hash] Additional options (e.g., node_id for sync_all)
    def execute(instance_id, operation_id = nil, command = 'sync', options = {})
      validate_command!(command)

      log_info("Executing #{command}",
               instance_id: instance_id,
               operation_id: operation_id,
               command: command)
      start_time = Time.current

      update_operation_status(operation_id, 'running') if operation_id

      result = case command
               when 'sync_all'
                 sync_all_instances(options[:node_id] || options['node_id'], operation_id)
               when 'cleanse'
                 cleanse_instance(instance_id, operation_id)
               else
                 sync_instance(instance_id, operation_id)
               end

      duration = Time.current - start_time
      track_performance_metric("system_instance_#{command}_duration", duration)

      result.merge(duration: duration)
    rescue ArgumentError => e
      log_error('Invalid command', e, command: command)
      update_operation_status(operation_id, 'failed', error_message: e.message) if operation_id
      raise
    rescue StandardError => e
      log_error("Instance #{command} failed", e, instance_id: instance_id)
      update_operation_status(operation_id, 'failed', error_message: e.message) if operation_id
      track_error_metric("instance_#{command}_failed")
      raise
    end

    private

    def validate_command!(command)
      return if VALID_COMMANDS.include?(command)

      raise ArgumentError, "Invalid command: #{command}. Valid: #{VALID_COMMANDS.join(', ')}"
    end

    # Sync a single instance via SSH
    def sync_instance(instance_id, operation_id)
      log_info('Syncing instance via SSH', instance_id: instance_id)

      instance = fetch_instance(instance_id)
      return handle_not_found(instance_id, operation_id) unless instance

      # Request backend to execute SSH sync command
      result = with_api_retry do
        api_client.post("/api/v1/internal/system/node_instances/#{instance_id}/ssh_sync")
      end

      if result['success']
        update_operation_status(operation_id, 'complete') if operation_id
        increment_counter('system_instance_synced')
        { success: true, instance_id: instance_id }
      else
        error_message = result['error'] || "Failed to sync instance #{instance['name']}"
        update_operation_status(operation_id, 'failed', error_message: error_message) if operation_id
        track_error_metric('instance_sync_ssh_failed')
        { success: false, error: error_message }
      end
    end

    # Cleanse an instance (reset configuration)
    def cleanse_instance(instance_id, operation_id)
      log_info('Cleansing instance', instance_id: instance_id)

      instance = fetch_instance(instance_id)
      return handle_not_found(instance_id, operation_id) unless instance

      update_operation_progress(operation_id, 50) if operation_id

      # Request backend to execute SSH cleanse command
      result = with_api_retry do
        api_client.post("/api/v1/internal/system/node_instances/#{instance_id}/ssh_cleanse")
      end

      if result['success']
        update_operation_status(operation_id, 'complete') if operation_id
        increment_counter('system_instance_cleansed')
        { success: true, instance_id: instance_id }
      else
        error_message = result['error'] || "Failed to cleanse instance #{instance['name']}"
        update_operation_status(operation_id, 'failed', error_message: error_message) if operation_id
        track_error_metric('instance_cleanse_failed')
        { success: false, error: error_message }
      end
    end

    # Sync all cloud/dynamic instances for a node
    def sync_all_instances(node_id, operation_id)
      log_info('Syncing all cloud instances for node', node_id: node_id)

      unless node_id
        update_operation_status(operation_id, 'failed', error_message: 'Node ID required for sync_all') if operation_id
        return { success: false, error: 'Node ID required' }
      end

      # Fetch cloud and dynamic instances
      instances = with_api_retry do
        api_client.get('/api/v1/internal/system/node_instances', {
          node_id: node_id,
          variety: %w[cloud dynamic]
        })
      end

      instance_list = instances['node_instances'] || []
      log_info("Found #{instance_list.size} instances to sync", node_id: node_id)

      # Queue individual sync jobs
      instance_list.each do |instance|
        System::NodeInstanceSyncJob.perform_async(instance['id'], nil, 'sync')
        log_info('Queued sync for instance', instance_id: instance['id'])
      end

      update_operation_status(operation_id, 'complete') if operation_id
      increment_counter('system_node_instances_sync_queued', count: instance_list.size)

      { success: true, instances_queued: instance_list.size }
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
  end
end
