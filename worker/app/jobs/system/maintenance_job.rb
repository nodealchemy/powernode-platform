# frozen_string_literal: true

module System
  # MaintenanceJob - Orchestrates maintenance operations for accounts
  #
  # Migrated from legacy powernode-agent Account.do_maintenance
  # This job processes pending operations and cascades maintenance to nodes.
  #
  # @example Execute maintenance for a specific account
  #   System::MaintenanceJob.perform_async(account_id)
  #
  # @example Execute maintenance for all accounts (scheduler mode)
  #   System::MaintenanceJob.perform_async
  #
  class MaintenanceJob < BaseJob
    sidekiq_options queue: 'system',
                    retry: 2,
                    dead: true

    # Execute maintenance operations
    #
    # @param account_id [String, nil] Optional account ID; if nil, processes all accounts
    def execute(account_id = nil)
      if account_id
        process_account_maintenance(account_id)
      else
        process_all_accounts_maintenance
      end
    end

    private

    # Process maintenance for all accounts needing it
    def process_all_accounts_maintenance
      log_info('Starting scheduled maintenance for all accounts')
      start_time = Time.current

      # Fetch accounts that need maintenance
      accounts = with_api_retry do
        api_client.get('/api/v1/internal/system/accounts', {
          needs_maintenance: true
        })
      end

      account_list = accounts['accounts'] || []
      log_info("Found #{account_list.size} accounts needing maintenance")

      # Queue individual maintenance jobs for each account
      account_list.each do |account|
        System::MaintenanceJob.perform_async(account['id'])
      end

      duration = Time.current - start_time
      track_performance_metric('system_maintenance_scheduler_duration', duration)
      increment_counter('system_maintenance_accounts_queued', count: account_list.size)

      { accounts_queued: account_list.size, duration: duration }
    end

    # Process maintenance for a specific account
    #
    # @param account_id [String] The account ID to process
    def process_account_maintenance(account_id)
      log_info('Processing account maintenance', account_id: account_id)
      start_time = Time.current

      # Process pending synchronous operations
      process_pending_operations(account_id)

      # Execute and monitor async operations
      execute_async_operations(account_id)

      # Cascade maintenance to all nodes
      cascade_node_maintenance(account_id)

      duration = Time.current - start_time
      track_performance_metric('system_account_maintenance_duration', duration, account_id: account_id)
      increment_counter('system_account_maintenance_completed')

      log_info('Account maintenance completed', account_id: account_id, duration: duration)
      { account_id: account_id, duration: duration }
    rescue StandardError => e
      log_error('Account maintenance failed', e, account_id: account_id)
      track_error_metric('account_maintenance_failed', account_id: account_id)
      raise
    end

    # Process pending synchronous operations for an account
    #
    # @param account_id [String] The account ID
    def process_pending_operations(account_id)
      log_info('Processing pending operations', account_id: account_id)

      # Fetch pending non-async operations
      operations = with_api_retry do
        api_client.get('/api/v1/internal/system/operations', {
          account_id: account_id,
          status: 'pending',
          async: false
        })
      end

      operation_list = operations['operations'] || []
      log_info("Found #{operation_list.size} pending sync operations", account_id: account_id)

      operation_list.each do |operation|
        dispatch_operation(operation)
      end
    end

    # Execute async operations and wait for completion
    #
    # @param account_id [String] The account ID
    def execute_async_operations(account_id)
      log_info('Executing async operations', account_id: account_id)

      # Fetch pending async operations
      operations = with_api_retry do
        api_client.get('/api/v1/internal/system/operations', {
          account_id: account_id,
          status: 'pending',
          async: true
        })
      end

      operation_list = operations['operations'] || []
      return if operation_list.empty?

      log_info("Found #{operation_list.size} async operations", account_id: account_id)

      # Queue async operations as separate jobs
      operation_list.each do |operation|
        dispatch_operation(operation)
      end
    end

    # Cascade maintenance to all nodes in the account
    #
    # @param account_id [String] The account ID
    def cascade_node_maintenance(account_id)
      log_info('Cascading maintenance to nodes', account_id: account_id)

      # Fetch enabled nodes for account
      nodes = with_api_retry do
        api_client.get('/api/v1/internal/system/nodes', {
          account_id: account_id,
          enabled: true
        })
      end

      node_list = nodes['nodes'] || []
      log_info("Cascading maintenance to #{node_list.size} nodes", account_id: account_id)

      node_list.each do |node|
        System::NodeMaintenanceJob.perform_async(node['id'])
      end
    end

    # Dispatch an operation to the appropriate job
    #
    # @param operation [Hash] The operation to dispatch
    def dispatch_operation(operation)
      operable_type = operation['operable_type']
      operable_id = operation['operable_id']
      command = operation['command']
      operation_id = operation['id']

      log_info('Dispatching operation',
               operation_id: operation_id,
               operable_type: operable_type,
               command: command)

      # Map operable_type and command to appropriate job class
      job_class = resolve_job_class(operable_type, command)

      if job_class
        job_class.perform_async(operable_id, operation_id)
        increment_counter('system_operation_dispatched',
                          operable_type: operable_type,
                          command: command)
      else
        log_warn('No job class found for operation',
                 operable_type: operable_type,
                 command: command)
      end
    end

    # Resolve the job class for an operable type and command
    #
    # @param operable_type [String] The type of operable (node, node_instance, etc.)
    # @param command [String] The command to execute
    # @return [Class, nil] The job class or nil if not found
    def resolve_job_class(operable_type, command)
      case operable_type.to_s.underscore
      when 'system/node', 'node'
        resolve_node_job(command)
      when 'system/node_instance', 'node_instance'
        resolve_node_instance_job(command)
      when 'system/node_module', 'node_module'
        resolve_module_job(command)
      when 'system/provider_volume', 'provider_volume'
        System::VolumeManagementJob
      when 'system/node_architecture', 'node_architecture'
        resolve_architecture_job(command)
      else
        nil
      end
    end

    def resolve_node_job(command)
      case command
      when 'maintenance'
        System::NodeMaintenanceJob
      when 'create_cloud_instance', 'create_instance'
        System::NodeInstanceProvisionJob
      when 'sync_cloud_instances'
        System::NodeInstanceSyncJob
      else
        nil
      end
    end

    def resolve_node_instance_job(command)
      case command
      when 'maintenance'
        System::NodeInstanceMaintenanceJob
      when 'start', 'stop', 'reboot', 'terminate'
        System::NodeInstanceControlJob
      when 'exec'
        System::NodeInstanceExecJob
      when 'sync', 'cleanse'
        System::NodeInstanceSyncJob
      when 'public_ip_associate', 'public_ip_disassociate'
        System::NodeInstanceIpJob
      when 'create_image'
        System::ImageCreateJob
      else
        nil
      end
    end

    def resolve_module_job(command)
      case command
      when 'build'
        System::ModuleBuildJob
      when 'commit'
        System::ModuleCommitJob
      else
        nil
      end
    end

    def resolve_architecture_job(command)
      case command
      when 'create_image'
        System::ImageCreateJob
      else
        nil
      end
    end
  end
end
