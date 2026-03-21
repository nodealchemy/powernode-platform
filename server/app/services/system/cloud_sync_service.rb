# frozen_string_literal: true

module System
  # Service for synchronizing cloud instance state with cloud providers
  # Uses provider adapters for multi-cloud support
  class CloudSyncService
    class SyncError < StandardError; end

    # Sync a single instance state from cloud provider
    #
    # @param instance [System::NodeInstance] The instance to sync
    # @return [Hash] Result with :success, :status, :private_ip_address, :public_ip_address, :updated, :error
    def self.sync_instance_state(instance:)
      new.sync_instance_state(instance: instance)
    end

    # Sync all instances for a node
    #
    # @param node [System::Node] The node
    # @return [Hash] Result with :success, :synced_count, :error
    def self.sync_node_instances(node:)
      new.sync_node_instances(node: node)
    end

    def sync_instance_state(instance:)
      validate_instance!(instance)

      unless %w[cloud dynamic].include?(instance.variety)
        return { success: false, error: "Instance variety #{instance.variety} does not support cloud sync" }
      end

      unless instance.cloud_instance_id.present?
        return { success: false, error: "Instance has no cloud instance ID" }
      end

      Rails.logger.info("[CloudSyncService] Syncing instance #{instance.name}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_instance(instance)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.get_instance(instance.cloud_instance_id)

        if result[:success]
          updated = state_changed?(instance, result)

          {
            success: true,
            status: result[:status],
            private_ip_address: result[:private_ip_address],
            public_ip_address: result[:public_ip_address],
            instance_type: result[:instance_type],
            updated: updated
          }
        else
          # Handle not found - instance may have been terminated externally
          if result[:error_code] == "NotFound"
            {
              success: true,
              status: "terminated",
              private_ip_address: nil,
              public_ip_address: nil,
              updated: instance.status != "terminated"
            }
          else
            { success: false, error: result[:error] }
          end
        end
      rescue Providers::BaseProvider::ResourceNotFoundError
        # Instance was terminated externally
        {
          success: true,
          status: "terminated",
          private_ip_address: nil,
          public_ip_address: nil,
          updated: instance.status != "terminated"
        }
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[CloudSyncService] Provider error: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[CloudSyncService] Sync failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def sync_node_instances(node:)
      validate_node!(node)

      instances = node.node_instances.where(variety: %w[cloud dynamic])
      synced_count = 0
      errors = []

      instances.find_each do |instance|
        result = sync_instance_state(instance: instance)

        if result[:success]
          if result[:updated]
            update_data = {
              status: result[:status],
              last_synced_at: Time.current
            }

            # Only update IPs if they changed
            if result.key?(:private_ip_address)
              update_data[:private_ip_address] = result[:private_ip_address]
            end

            if result.key?(:public_ip_address)
              update_data[:public_ip_address] = result[:public_ip_address]
            end

            instance.update!(update_data)
          else
            # Just update sync timestamp
            instance.update!(last_synced_at: Time.current)
          end
          synced_count += 1
        else
          errors << { instance_id: instance.id, error: result[:error] }
        end
      end

      {
        success: errors.empty?,
        synced_count: synced_count,
        total_count: instances.count,
        errors: errors
      }
    end

    # Batch sync for all instances in a region
    #
    # @param region [System::ProviderRegion] The region
    # @param account [Account] The account
    # @return [Hash] Result with :success, :synced_count, :error
    def self.sync_region_instances(region:, account:)
      new.sync_region_instances(region: region, account: account)
    end

    def sync_region_instances(region:, account:)
      validate_region!(region)

      # Get provider adapter through the registry
      connection = get_provider_connection_for_region(region, account)
      unless connection
        return { success: false, error: "No provider connection available" }
      end

      provider_adapter = begin
        Providers::Registry.for(connection, region: region)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        # Fetch all instances from cloud provider
        cloud_result = provider_adapter.list_instances

        unless cloud_result[:success]
          return { success: false, error: cloud_result[:error] }
        end

        cloud_instances = cloud_result[:instances] || []

        # Get local instances for this region
        local_instances = ::System::NodeInstance
          .where(provider_region: region)
          .where(variety: %w[cloud dynamic])
          .where.not(cloud_instance_id: nil)
          .index_by(&:cloud_instance_id)

        synced_count = 0
        updated_count = 0

        cloud_instances.each do |cloud_data|
          cloud_id = cloud_data[:cloud_instance_id]
          local_instance = local_instances[cloud_id]

          if local_instance
            if state_changed?(local_instance, cloud_data)
              local_instance.update!(
                status: cloud_data[:status],
                private_ip_address: cloud_data[:private_ip_address],
                public_ip_address: cloud_data[:public_ip_address],
                last_synced_at: Time.current
              )
              updated_count += 1
            else
              local_instance.update!(last_synced_at: Time.current)
            end
            synced_count += 1
          end
        end

        {
          success: true,
          synced_count: synced_count,
          updated_count: updated_count,
          cloud_count: cloud_instances.size
        }
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[CloudSyncService] Provider error: #{e.message}")
        { success: false, error: e.message }
      end
    end

    private

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
    end

    def validate_node!(node)
      raise ArgumentError, "Node required" unless node
      raise ArgumentError, "Node must be a System::Node" unless node.is_a?(::System::Node)
    end

    def validate_region!(region)
      raise ArgumentError, "Region required" unless region
      raise ArgumentError, "Region must be a System::ProviderRegion" unless region.is_a?(::System::ProviderRegion)
    end

    def get_provider_connection_for_region(region, account)
      provider = region.provider

      ::System::ProviderConnection
        .where(provider: provider)
        .where("account_id = ? OR account_id IS NULL", account&.id)
        .where(status: "connected")
        .first
    end

    def state_changed?(instance, result)
      instance.status != result[:status] ||
        instance.private_ip_address != result[:private_ip_address] ||
        instance.public_ip_address != result[:public_ip_address]
    end
  end
end
