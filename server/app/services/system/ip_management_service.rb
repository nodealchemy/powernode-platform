# frozen_string_literal: true

module System
  # Service for managing public/elastic IP addresses
  # Uses provider adapters for multi-cloud support
  class IpManagementService
    class IpError < StandardError; end

    # Associate a public IP with an instance
    #
    # @param instance [System::NodeInstance] The instance
    # @param allocation_id [String, nil] Optional existing allocation ID
    # @return [Hash] Result with :success, :public_ip_address, :allocation_id, :association_id, :error
    def self.associate_public_ip(instance:, allocation_id: nil)
      new.associate_public_ip(instance: instance, allocation_id: allocation_id)
    end

    # Disassociate a public IP from an instance
    #
    # @param instance [System::NodeInstance] The instance
    # @param release [Boolean] Whether to release the IP after disassociating
    # @return [Hash] Result with :success, :error
    def self.disassociate_public_ip(instance:, release: true)
      new.disassociate_public_ip(instance: instance, release: release)
    end

    # Allocate a new public IP
    #
    # @param region [System::ProviderRegion] The region
    # @param account [Account] The account
    # @return [Hash] Result with :success, :allocation_id, :public_ip, :error
    def self.allocate_ip(region:, account:)
      new.allocate_ip(region: region, account: account)
    end

    # Release an allocated IP
    #
    # @param region [System::ProviderRegion] The region
    # @param account [Account] The account
    # @param allocation_id [String] The allocation ID
    # @return [Hash] Result with :success, :error
    def self.release_ip(region:, account:, allocation_id:)
      new.release_ip(region: region, account: account, allocation_id: allocation_id)
    end

    def associate_public_ip(instance:, allocation_id: nil)
      validate_instance!(instance)

      unless instance.cloud_instance_id.present?
        return { success: false, error: "Instance has no cloud instance ID" }
      end

      if instance.public_ip_address.present? && allocation_id.nil?
        return { success: true, public_ip_address: instance.public_ip_address, message: "IP already associated" }
      end

      Rails.logger.info("[IpManagementService] Associating public IP to #{instance.name}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_instance(instance)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.associate_ip(instance.cloud_instance_id, allocation_id: allocation_id)

        if result[:success]
          instance.update!(
            public_ip_address: result[:public_ip],
            config: (instance.config || {}).merge(
              "ip_allocation_id" => result[:allocation_id],
              "ip_association_id" => result[:association_id]
            )
          )

          {
            success: true,
            public_ip_address: result[:public_ip],
            allocation_id: result[:allocation_id],
            association_id: result[:association_id]
          }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[IpManagementService] Provider error: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[IpManagementService] Associate IP failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def disassociate_public_ip(instance:, release: true)
      validate_instance!(instance)

      unless instance.public_ip_address.present?
        return { success: true, message: "No public IP to disassociate" }
      end

      Rails.logger.info("[IpManagementService] Disassociating public IP from #{instance.name}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_instance(instance)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        association_id = instance.config&.dig("ip_association_id")
        allocation_id = instance.config&.dig("ip_allocation_id")

        # Disassociate the IP
        if association_id.present?
          result = provider_adapter.disassociate_ip(association_id)
          return { success: false, error: result[:error] } unless result[:success]
        end

        # Release the IP if requested
        if release && allocation_id.present?
          release_result = provider_adapter.release_ip(allocation_id)
          Rails.logger.warn("[IpManagementService] Failed to release IP: #{release_result[:error]}") unless release_result[:success]
        end

        # Update instance
        config = instance.config || {}
        config.delete("ip_allocation_id")
        config.delete("ip_association_id")

        instance.update!(
          public_ip_address: nil,
          config: config
        )

        { success: true }
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[IpManagementService] Provider error: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[IpManagementService] Disassociate IP failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def allocate_ip(region:, account:)
      validate_region!(region)

      Rails.logger.info("[IpManagementService] Allocating IP in region #{region.name}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_node(nil, region: region) # TODO: Update registry to support region-only lookup
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.allocate_ip

        if result[:success]
          {
            success: true,
            allocation_id: result[:allocation_id],
            public_ip: result[:public_ip]
          }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[IpManagementService] Provider error: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def release_ip(region:, account:, allocation_id:)
      validate_region!(region)

      Rails.logger.info("[IpManagementService] Releasing IP #{allocation_id}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_node(nil, region: region)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.release_ip(allocation_id)

        if result[:success]
          { success: true }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[IpManagementService] Provider error: #{e.message}")
        { success: false, error: e.message }
      end
    end

    private

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
    end

    def validate_region!(region)
      raise ArgumentError, "Region required" unless region
      raise ArgumentError, "Region must be a System::ProviderRegion" unless region.is_a?(::System::ProviderRegion)
    end
  end
end
