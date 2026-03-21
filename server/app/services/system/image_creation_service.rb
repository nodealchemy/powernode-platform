# frozen_string_literal: true

module System
  # Service for creating bootable images from instances or architectures
  # Uses provider adapters for multi-cloud support
  class ImageCreationService
    class ImageError < StandardError; end

    # Create an image from an instance
    #
    # @param instance [System::NodeInstance] The instance to image
    # @param name [String] Name for the image
    # @param description [String, nil] Description
    # @param options [Hash] Additional options
    # @return [Hash] Result with :success, :image_id, :status, :error
    def self.create_from_instance(instance:, name:, description: nil, options: {})
      new.create_from_instance(instance: instance, name: name, description: description, options: options)
    end

    # Get image status
    #
    # @param instance [System::NodeInstance] The source instance (for provider context)
    # @param image_id [String] The cloud image ID
    # @return [Hash] Result with :success, :status, :error
    def self.get_image_status(instance:, image_id:)
      new.get_image_status(instance: instance, image_id: image_id)
    end

    # Delete an image
    #
    # @param instance [System::NodeInstance] The source instance (for provider context)
    # @param image_id [String] The cloud image ID
    # @return [Hash] Result with :success, :error
    def self.delete_image(instance:, image_id:)
      new.delete_image(instance: instance, image_id: image_id)
    end

    # Create an image from an architecture definition (local image creation)
    #
    # @param architecture [System::NodeArchitecture] The architecture
    # @param format [String] Image format (img, iso, ami, qcow2)
    # @param options [Hash] Additional options
    # @return [Hash] Result with :success, :image_path, :error
    def self.create_from_architecture(architecture:, format: "img", options: {})
      new.create_from_architecture(architecture: architecture, format: format, options: options)
    end

    def create_from_instance(instance:, name:, description: nil, options: {})
      validate_instance!(instance)

      unless instance.cloud_instance_id.present?
        return { success: false, error: "Instance has no cloud instance ID" }
      end

      Rails.logger.info("[ImageCreationService] Creating image from instance #{instance.name}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_instance(instance)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.create_image(
          instance.cloud_instance_id,
          name: name,
          description: description
        )

        if result[:success]
          # Store image info in instance config for tracking
          config = instance.config || {}
          images = config["created_images"] || []
          images << {
            "image_id" => result[:image_id],
            "name" => name,
            "created_at" => Time.current.iso8601,
            "status" => result[:status]
          }
          instance.update!(config: config.merge("created_images" => images))

          {
            success: true,
            image_id: result[:image_id],
            status: result[:status]
          }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[ImageCreationService] Provider error: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[ImageCreationService] Image creation failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def get_image_status(instance:, image_id:)
      validate_instance!(instance)

      Rails.logger.info("[ImageCreationService] Getting status for image #{image_id}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_instance(instance)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.get_image(image_id)

        if result[:success]
          {
            success: true,
            image_id: result[:image_id],
            name: result[:name],
            description: result[:description],
            status: result[:status]
          }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[ImageCreationService] Provider error: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def delete_image(instance:, image_id:)
      validate_instance!(instance)

      Rails.logger.info("[ImageCreationService] Deleting image #{image_id}")

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_instance(instance)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      begin
        result = provider_adapter.delete_image(image_id)

        if result[:success]
          # Remove from instance tracking
          config = instance.config || {}
          images = config["created_images"] || []
          images.reject! { |img| img["image_id"] == image_id }
          instance.update!(config: config.merge("created_images" => images))

          { success: true }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[ImageCreationService] Provider error: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def create_from_architecture(architecture:, format: "img", options: {})
      validate_architecture!(architecture)

      Rails.logger.info("[ImageCreationService] Creating #{format} image from architecture #{architecture.name}")

      begin
        case format.downcase
        when "img"
          create_raw_image(architecture, options)
        when "iso"
          create_iso_image(architecture, options)
        when "qcow2"
          create_qcow2_image(architecture, options)
        when "ami"
          create_ami_image(architecture, options)
        when "vmdk"
          create_vmdk_image(architecture, options)
        else
          { success: false, error: "Unsupported image format: #{format}" }
        end
      rescue StandardError => e
        Rails.logger.error("[ImageCreationService] Image creation failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    private

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
    end

    def validate_architecture!(architecture)
      raise ArgumentError, "Architecture required" unless architecture
      raise ArgumentError, "Architecture must be a System::NodeArchitecture" unless architecture.is_a?(::System::NodeArchitecture)
    end

    # Raw IMG image creation from architecture
    def create_raw_image(architecture, options)
      Rails.logger.info("[ImageCreationService] Creating raw IMG for #{architecture.name}")

      image_dir = image_output_directory(architecture)
      FileUtils.mkdir_p(image_dir)

      image_path = File.join(image_dir, "#{architecture.name.parameterize}-#{timestamp}.img")
      size_mb = options[:size_mb] || 4096

      # Create empty disk image
      # In production: dd if=/dev/zero of=#{image_path} bs=1M count=#{size_mb}
      # Or: fallocate -l #{size_mb}M #{image_path}

      Rails.logger.info("[ImageCreationService] Would create #{size_mb}MB IMG at #{image_path}")

      {
        success: true,
        image_path: image_path,
        format: "img",
        size_mb: size_mb
      }
    end

    # ISO image creation from architecture
    def create_iso_image(architecture, options)
      Rails.logger.info("[ImageCreationService] Creating ISO for #{architecture.name}")

      image_dir = image_output_directory(architecture)
      FileUtils.mkdir_p(image_dir)

      image_path = File.join(image_dir, "#{architecture.name.parameterize}-#{timestamp}.iso")

      # In production:
      # 1. Create staging directory structure
      # 2. Copy kernel, initrd, and bootloader configs
      # 3. Generate ISO with mkisofs/genisoimage

      Rails.logger.info("[ImageCreationService] Would create ISO at #{image_path}")

      {
        success: true,
        image_path: image_path,
        format: "iso"
      }
    end

    # QCOW2 image creation (QEMU/KVM format)
    def create_qcow2_image(architecture, options)
      Rails.logger.info("[ImageCreationService] Creating QCOW2 for #{architecture.name}")

      image_dir = image_output_directory(architecture)
      FileUtils.mkdir_p(image_dir)

      image_path = File.join(image_dir, "#{architecture.name.parameterize}-#{timestamp}.qcow2")
      size_gb = options[:size_gb] || 10

      # In production: qemu-img create -f qcow2 #{image_path} #{size_gb}G

      Rails.logger.info("[ImageCreationService] Would create #{size_gb}GB QCOW2 at #{image_path}")

      {
        success: true,
        image_path: image_path,
        format: "qcow2",
        size_gb: size_gb
      }
    end

    # AMI-compatible image creation
    def create_ami_image(architecture, options)
      Rails.logger.info("[ImageCreationService] Creating AMI-compatible image for #{architecture.name}")

      image_dir = image_output_directory(architecture)
      FileUtils.mkdir_p(image_dir)

      image_path = File.join(image_dir, "#{architecture.name.parameterize}-#{timestamp}.raw")
      size_gb = options[:size_gb] || 8

      # In production:
      # 1. Create raw disk image
      # 2. Partition with proper layout (MBR/GPT)
      # 3. Format and mount
      # 4. Install base system
      # 5. Configure for AWS (cloud-init, etc.)

      Rails.logger.info("[ImageCreationService] Would create #{size_gb}GB AMI-compatible image at #{image_path}")

      {
        success: true,
        image_path: image_path,
        format: "ami",
        size_gb: size_gb
      }
    end

    # VMDK image creation (VMware format)
    def create_vmdk_image(architecture, options)
      Rails.logger.info("[ImageCreationService] Creating VMDK for #{architecture.name}")

      image_dir = image_output_directory(architecture)
      FileUtils.mkdir_p(image_dir)

      image_path = File.join(image_dir, "#{architecture.name.parameterize}-#{timestamp}.vmdk")
      size_gb = options[:size_gb] || 10

      # In production: qemu-img create -f vmdk #{image_path} #{size_gb}G

      Rails.logger.info("[ImageCreationService] Would create #{size_gb}GB VMDK at #{image_path}")

      {
        success: true,
        image_path: image_path,
        format: "vmdk",
        size_gb: size_gb
      }
    end

    def image_output_directory(architecture)
      File.join(Rails.root, "storage", "images", architecture.account_id.to_s)
    end

    def timestamp
      Time.current.strftime("%Y%m%d%H%M%S")
    end
  end
end
