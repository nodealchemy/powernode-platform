# frozen_string_literal: true

module System
  # Service for managing cloud storage volumes
  # Uses provider adapters for multi-cloud support
  class VolumeManagementService
    class VolumeError < StandardError; end

    # Attach a volume to an instance
    #
    # @param volume [System::ProviderVolume] The volume to attach
    # @param instance [System::NodeInstance] The instance to attach to
    # @param device [String] The device path (e.g., /dev/sdb)
    # @return [Hash] Result with :success, :device, :error
    def self.attach(volume:, instance:, device: nil)
      new.attach(volume: volume, instance: instance, device: device)
    end

    # Detach a volume from an instance
    #
    # @param volume [System::ProviderVolume] The volume to detach
    # @param force [Boolean] Force detach
    # @return [Hash] Result with :success, :error
    def self.detach(volume:, force: false)
      new.detach(volume: volume, force: force)
    end

    # Provision a new volume
    #
    # @param account [Account] The account
    # @param region [System::ProviderRegion] The region to create in
    # @param volume_type [System::ProviderVolumeType] The volume type
    # @param size_gb [Integer] Size in GB
    # @param options [Hash] Additional options
    # @return [Hash] Result with :success, :volume, :error
    def self.provision(account:, region:, volume_type:, size_gb:, options: {})
      new.provision(account: account, region: region, volume_type: volume_type, size_gb: size_gb, options: options)
    end

    # Delete a volume
    #
    # @param volume [System::ProviderVolume] The volume to delete
    # @return [Hash] Result with :success, :error
    def self.delete(volume:)
      new.delete(volume: volume)
    end

    # Check volume health and status
    #
    # @param volume [System::ProviderVolume] The volume to check
    # @return [Hash] Result with :success, :status, :health, :error
    def self.check(volume:)
      new.check(volume: volume)
    end

    def attach(volume:, instance:, device: nil)
      validate_volume!(volume)
      validate_instance!(instance)

      unless volume.cloud_volume_id.present?
        return { success: false, error: "Volume has no cloud volume ID" }
      end

      unless instance.cloud_instance_id.present?
        return { success: false, error: "Instance has no cloud instance ID" }
      end

      if volume.provider_volume_members.any?
        return { success: false, error: "Volume is already attached" }
      end

      Rails.logger.info("[VolumeManagementService] Attaching volume #{volume.name} to #{instance.name}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_volume(volume)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        device ||= next_available_device(instance)
        result = provider_adapter.attach_volume(volume.cloud_volume_id, instance.cloud_instance_id, device: device)

        if result[:success]
          # Create volume member record
          ::System::ProviderVolumeMember.create!(
            provider_volume: volume,
            node_instance: instance,
            device: result[:device] || device
          )

          volume.update!(status: "attached")

          { success: true, device: result[:device] || device }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[VolumeManagementService] Provider error: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[VolumeManagementService] Attach failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def detach(volume:, force: false)
      validate_volume!(volume)

      unless volume.cloud_volume_id.present?
        return { success: false, error: "Volume has no cloud volume ID" }
      end

      member = volume.provider_volume_members.first
      unless member
        return { success: true, message: "Volume is not attached" }
      end

      Rails.logger.info("[VolumeManagementService] Detaching volume #{volume.name}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_volume(volume)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.detach_volume(volume.cloud_volume_id, force: force)

        if result[:success]
          member.destroy!
          volume.update!(status: "available")
          { success: true }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[VolumeManagementService] Provider error: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[VolumeManagementService] Detach failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def provision(account:, region:, volume_type:, size_gb:, options: {})
      validate_region!(region)

      Rails.logger.info("[VolumeManagementService] Provisioning #{size_gb}GB volume in #{region.name}")

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
        # Create volume record
        volume = ::System::ProviderVolume.create!(
          name: options[:name] || "volume-#{Time.current.strftime('%Y%m%d%H%M%S')}",
          account: account,
          provider_region: region,
          provider_volume_type: volume_type,
          size_gb: size_gb,
          status: "creating"
        )

        # Build provider params
        provider_params = {
          name: volume.name,
          size_gb: size_gb,
          volume_type: volume_type&.name,
          availability_zone: options[:availability_zone],
          encrypted: options[:encrypted],
          kms_key_id: options[:kms_key_id],
          iops: options[:iops],
          throughput: options[:throughput]
        }.compact

        result = provider_adapter.create_volume(provider_params)

        if result[:success]
          volume.update!(
            cloud_volume_id: result[:volume_id],
            status: "available"
          )

          { success: true, volume: volume }
        else
          volume.update!(status: "failed")
          { success: false, error: result[:error], volume: volume }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[VolumeManagementService] Provider error: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[VolumeManagementService] Provision failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def delete(volume:)
      validate_volume!(volume)

      unless volume.cloud_volume_id.present?
        # No cloud volume - just destroy record
        volume.destroy!
        return { success: true }
      end

      if volume.provider_volume_members.any?
        return { success: false, error: "Volume is attached, detach first" }
      end

      Rails.logger.info("[VolumeManagementService] Deleting volume #{volume.name}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_volume(volume)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.delete_volume(volume.cloud_volume_id)

        if result[:success]
          volume.destroy!
          { success: true }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[VolumeManagementService] Provider error: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def check(volume:)
      validate_volume!(volume)

      unless volume.cloud_volume_id.present?
        return { success: true, status: volume.status, health: "unknown", message: "No cloud volume" }
      end

      Rails.logger.info("[VolumeManagementService] Checking volume #{volume.name}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_volume(volume)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.get_volume(volume.cloud_volume_id)

        if result[:success]
          # Update local status if changed
          if result[:status] != volume.status
            volume.update!(status: result[:status])
          end

          {
            success: true,
            status: result[:status],
            size_gb: result[:size_gb],
            volume_type: result[:volume_type],
            attached_to: result[:attached_to],
            device: result[:device]
          }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[VolumeManagementService] Provider error: #{e.message}")
        { success: false, error: e.message }
      end
    end

    private

    def validate_volume!(volume)
      raise ArgumentError, "Volume required" unless volume
      raise ArgumentError, "Volume must be a System::ProviderVolume" unless volume.is_a?(::System::ProviderVolume)
    end

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
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

    def next_available_device(instance)
      # Get existing attached devices
      existing = ::System::ProviderVolumeMember
                   .where(node_instance: instance)
                   .pluck(:device)

      # Find next available device letter
      ("b".."z").each do |letter|
        device = "/dev/sd#{letter}"
        return device unless existing.include?(device)
      end

      raise VolumeError, "No available device paths"
    end
  end
end
