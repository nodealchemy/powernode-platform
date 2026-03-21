# frozen_string_literal: true

module System
  # VolumeManagementJob - Manages provider volume lifecycle
  #
  # Migrated from legacy powernode-agent ProviderVolume operations
  # This job handles volume attach, detach, provision, check, and recover operations.
  #
  # @example Attach a volume
  #   System::VolumeManagementJob.perform_async(volume_id, operation_id, 'attach')
  #
  # @example Check volume status
  #   System::VolumeManagementJob.perform_async(volume_id, operation_id, 'check')
  #
  class VolumeManagementJob < BaseJob
    VALID_COMMANDS = %w[attach detach provision check recover].freeze

    sidekiq_options queue: 'system',
                    retry: 2,
                    dead: true

    # Execute volume management command
    #
    # @param volume_id [String] The provider volume ID
    # @param operation_id [String, nil] Optional operation ID for tracking
    # @param command [String] The command (attach, detach, provision, check, recover)
    def execute(volume_id, operation_id = nil, command = 'check')
      validate_command!(command)

      log_info("Executing volume #{command}",
               volume_id: volume_id,
               operation_id: operation_id,
               command: command)
      start_time = Time.current

      update_operation_status(operation_id, 'running') if operation_id

      # Fetch volume details
      volume = fetch_volume(volume_id)
      return handle_not_found(volume_id, operation_id) unless volume

      # Execute the command
      result = case command
               when 'attach'
                 attach_volume(volume, operation_id)
               when 'detach'
                 detach_volume(volume, operation_id)
               when 'provision'
                 provision_volume(volume, operation_id)
               when 'check'
                 check_volume(volume, operation_id)
               when 'recover'
                 recover_volume(volume, operation_id)
               end

      if result[:success]
        handle_success(operation_id, command, volume, result, start_time)
      else
        handle_failure(operation_id, command, volume, result)
      end
    rescue ArgumentError => e
      log_error('Invalid command', e, command: command)
      update_operation_status(operation_id, 'failed', error_message: e.message) if operation_id
      raise
    rescue StandardError => e
      log_error("Volume #{command} failed", e, volume_id: volume_id)
      update_operation_status(operation_id, 'failed', error_message: e.message) if operation_id
      track_error_metric("volume_#{command}_failed", volume_id: volume_id)
      raise
    end

    private

    def validate_command!(command)
      return if VALID_COMMANDS.include?(command)

      raise ArgumentError, "Invalid command: #{command}. Valid: #{VALID_COMMANDS.join(', ')}"
    end

    def fetch_volume(volume_id)
      with_api_retry do
        api_client.get("/api/v1/internal/system/provider_volumes/#{volume_id}")
      end
    rescue BackendApiClient::ApiError => e
      return nil if e.status == 404

      raise
    end

    def handle_not_found(volume_id, operation_id)
      log_warn('Volume not found', volume_id: volume_id)
      update_operation_status(operation_id, 'failed', error_message: 'Volume not found') if operation_id
      { success: false, error: 'Volume not found' }
    end

    # Attach volume to its assigned node instance
    #
    # @param volume [Hash] The volume data
    # @param operation_id [String, nil] The operation ID
    # @return [Hash] Result with :success, :error keys
    def attach_volume(volume, operation_id)
      volume_id = volume['id']

      unless volume['status'] == 'available'
        return { success: false, error: "Cannot attach volume in #{volume['status']} status" }
      end

      unless volume['node_instance_id'].present?
        return { success: false, error: 'No node instance assigned to volume' }
      end

      log_info('Attaching volume',
               volume_id: volume_id,
               node_instance_id: volume['node_instance_id'])

      result = with_api_retry do
        api_client.post("/api/v1/internal/system/provider_volumes/#{volume_id}/attach")
      end

      if result['success']
        log_info('Volume attached', volume_id: volume_id)
        { success: true }
      else
        { success: false, error: result['error'] || "Failed to attach volume #{volume['name']}" }
      end
    end

    # Detach volume from its active node instance
    #
    # @param volume [Hash] The volume data
    # @param operation_id [String, nil] The operation ID
    # @return [Hash] Result with :success, :error keys
    def detach_volume(volume, operation_id)
      volume_id = volume['id']

      unless volume['status'] == 'attached'
        return { success: false, error: "Cannot detach volume in #{volume['status']} status" }
      end

      log_info('Detaching volume',
               volume_id: volume_id,
               active_instance_id: volume['active_instance_id'])

      result = with_api_retry do
        api_client.post("/api/v1/internal/system/provider_volumes/#{volume_id}/detach")
      end

      if result['success']
        log_info('Volume detached', volume_id: volume_id)
        { success: true }
      else
        { success: false, error: result['error'] || "Failed to detach volume #{volume['name']}" }
      end
    end

    # Provision volume members in the cloud provider
    #
    # @param volume [Hash] The volume data
    # @param operation_id [String, nil] The operation ID
    # @return [Hash] Result with :success, :error keys
    def provision_volume(volume, operation_id)
      volume_id = volume['id']

      log_info('Provisioning volume', volume_id: volume_id)

      result = with_api_retry do
        api_client.post("/api/v1/internal/system/provider_volumes/#{volume_id}/provision")
      end

      if result['success']
        log_info('Volume provisioned',
                 volume_id: volume_id,
                 members_created: result['members_created'])
        { success: true, members_created: result['members_created'] }
      else
        { success: false, error: result['error'] || "Failed to provision volume #{volume['name']}" }
      end
    end

    # Check volume status and reconcile state
    #
    # This operation:
    # 1. Provisions if pending or missing members
    # 2. Checks member status if attached/available
    # 3. Auto-attaches if instance assigned and available
    # 4. Auto-detaches if no instance and attached
    #
    # @param volume [Hash] The volume data
    # @param operation_id [String, nil] The operation ID
    # @return [Hash] Result with :success, :actions keys
    def check_volume(volume, operation_id)
      volume_id = volume['id']
      actions_taken = []

      log_info('Checking volume', volume_id: volume_id, status: volume['status'])

      result = with_api_retry do
        api_client.post("/api/v1/internal/system/provider_volumes/#{volume_id}/check")
      end

      if result['success']
        actions_taken = result['actions'] || []
        log_info('Volume check completed',
                 volume_id: volume_id,
                 actions: actions_taken)
        { success: true, actions: actions_taken }
      else
        { success: false, error: result['error'] || "Failed to check volume #{volume['name']}" }
      end
    end

    # Recover volume to available status
    #
    # @param volume [Hash] The volume data
    # @param operation_id [String, nil] The operation ID
    # @return [Hash] Result with :success, :error keys
    def recover_volume(volume, operation_id)
      volume_id = volume['id']

      log_info('Recovering volume', volume_id: volume_id)

      result = with_api_retry do
        api_client.post("/api/v1/internal/system/provider_volumes/#{volume_id}/recover")
      end

      if result['success']
        log_info('Volume recovered', volume_id: volume_id)
        { success: true }
      else
        { success: false, error: result['error'] || "Failed to recover volume #{volume['name']}" }
      end
    end

    def handle_success(operation_id, command, volume, result, start_time)
      log_info("Volume #{command} completed",
               volume_id: volume['id'],
               volume_name: volume['name'])

      update_operation_status(operation_id, 'complete') if operation_id

      duration = Time.current - start_time
      track_performance_metric("system_volume_#{command}_duration", duration)
      increment_counter("system_volume_#{command}_completed")

      result.merge(duration: duration, volume_id: volume['id'])
    end

    def handle_failure(operation_id, command, volume, result)
      log_error("Volume #{command} failed", nil,
                volume_id: volume['id'],
                error: result[:error])

      update_operation_status(operation_id, 'failed', error_message: result[:error]) if operation_id
      track_error_metric("volume_#{command}_cloud_failed")

      result
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
  end
end
