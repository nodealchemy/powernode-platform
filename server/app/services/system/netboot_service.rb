# frozen_string_literal: true

module System
  # Service for managing PXE/Netboot configuration for physical instances
  # Handles TFTP and DHCP configuration for network booting
  class NetbootService
    class NetbootError < StandardError; end

    TFTP_ROOT = ENV.fetch("NETBOOT_TFTP_ROOT", "/srv/tftp")
    PXELINUX_CFG_DIR = File.join(TFTP_ROOT, "pxelinux.cfg")

    # Sync netboot configuration for an instance
    #
    # @param instance [System::NodeInstance] The physical instance
    # @return [Hash] Result with :success, :error
    def self.sync(instance:)
      new.sync(instance: instance)
    end

    # Enable netboot for an instance
    #
    # @param instance [System::NodeInstance] The physical instance
    # @param options [Hash] Netboot options
    # @return [Hash] Result with :success, :error
    def self.enable(instance:, options: {})
      new.enable(instance: instance, options: options)
    end

    # Disable netboot for an instance
    #
    # @param instance [System::NodeInstance] The physical instance
    # @return [Hash] Result with :success, :error
    def self.disable(instance:)
      new.disable(instance: instance)
    end

    def sync(instance:)
      validate_instance!(instance)

      unless instance.variety == "physical"
        return { success: false, error: "Netboot only available for physical instances" }
      end

      unless netboot_enabled?(instance)
        Rails.logger.info("[NetbootService] Netboot not enabled for #{instance.name}")
        return { success: true, message: "Netboot not enabled" }
      end

      Rails.logger.info("[NetbootService] Syncing netboot for #{instance.name}")

      begin
        # Generate PXE configuration
        pxe_config = generate_pxe_config(instance)

        # Write configuration file
        write_pxe_config(instance, pxe_config)

        { success: true }
      rescue StandardError => e
        Rails.logger.error("[NetbootService] Sync failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def enable(instance:, options: {})
      validate_instance!(instance)

      unless instance.variety == "physical"
        return { success: false, error: "Netboot only available for physical instances" }
      end

      Rails.logger.info("[NetbootService] Enabling netboot for #{instance.name}")

      begin
        # Update instance config to enable netboot
        config = instance.config || {}
        config["netboot"] = {
          "enabled" => true,
          "boot_type" => options[:boot_type] || "localboot",
          "kernel" => options[:kernel],
          "initrd" => options[:initrd],
          "append" => options[:append]
        }

        instance.update!(config: config)

        # Generate and write PXE configuration
        pxe_config = generate_pxe_config(instance)
        write_pxe_config(instance, pxe_config)

        { success: true }
      rescue StandardError => e
        Rails.logger.error("[NetbootService] Enable failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def disable(instance:)
      validate_instance!(instance)

      Rails.logger.info("[NetbootService] Disabling netboot for #{instance.name}")

      begin
        # Update instance config to disable netboot
        config = instance.config || {}
        config["netboot"] ||= {}
        config["netboot"]["enabled"] = false

        instance.update!(config: config)

        # Remove PXE configuration file
        remove_pxe_config(instance)

        { success: true }
      rescue StandardError => e
        Rails.logger.error("[NetbootService] Disable failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    private

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
    end

    def netboot_enabled?(instance)
      instance.config&.dig("netboot", "enabled") == true
    end

    def generate_pxe_config(instance)
      netboot_config = instance.config&.dig("netboot") || {}
      boot_type = netboot_config["boot_type"] || "localboot"

      case boot_type
      when "localboot"
        generate_localboot_config(instance)
      when "install"
        generate_install_config(instance, netboot_config)
      when "rescue"
        generate_rescue_config(instance, netboot_config)
      when "custom"
        generate_custom_config(instance, netboot_config)
      else
        generate_localboot_config(instance)
      end
    end

    def generate_localboot_config(instance)
      <<~PXECONFIG
        # PXE configuration for #{instance.name}
        # Generated at #{Time.current}
        DEFAULT local
        PROMPT 0
        TIMEOUT 0
        LABEL local
          LOCALBOOT 0
      PXECONFIG
    end

    def generate_install_config(instance, config)
      kernel = config["kernel"] || "vmlinuz"
      initrd = config["initrd"] || "initrd.img"
      append = config["append"] || ""

      architecture = instance.node&.node_template&.node_platform&.node_architecture

      <<~PXECONFIG
        # PXE configuration for #{instance.name}
        # Generated at #{Time.current}
        DEFAULT install
        PROMPT 0
        TIMEOUT 100
        LABEL install
          KERNEL #{kernel}
          APPEND initrd=#{initrd} #{append}
      PXECONFIG
    end

    def generate_rescue_config(instance, config)
      kernel = config["kernel"] || "rescue/vmlinuz"
      initrd = config["initrd"] || "rescue/initrd.img"

      <<~PXECONFIG
        # PXE configuration for #{instance.name} (RESCUE MODE)
        # Generated at #{Time.current}
        DEFAULT rescue
        PROMPT 0
        TIMEOUT 100
        LABEL rescue
          KERNEL #{kernel}
          APPEND initrd=#{initrd} rescue
      PXECONFIG
    end

    def generate_custom_config(instance, config)
      config["pxe_config"] || generate_localboot_config(instance)
    end

    def pxe_config_filename(instance)
      # PXE configuration files are named based on MAC address or IP
      # Format: 01-xx-xx-xx-xx-xx-xx (MAC) or IP in hex

      if instance.private_ip_address.present?
        # Convert IP to hex format for PXE
        ip_hex = instance.private_ip_address.split(".").map { |o| o.to_i.to_s(16).upcase.rjust(2, "0") }.join
        ip_hex
      else
        # Use instance ID as fallback
        "instance-#{instance.id}"
      end
    end

    def write_pxe_config(instance, config)
      return unless pxe_enabled?

      FileUtils.mkdir_p(PXELINUX_CFG_DIR)

      filename = pxe_config_filename(instance)
      config_path = File.join(PXELINUX_CFG_DIR, filename)

      File.write(config_path, config)
      Rails.logger.info("[NetbootService] Wrote PXE config to #{config_path}")
    end

    def remove_pxe_config(instance)
      return unless pxe_enabled?

      filename = pxe_config_filename(instance)
      config_path = File.join(PXELINUX_CFG_DIR, filename)

      if File.exist?(config_path)
        File.delete(config_path)
        Rails.logger.info("[NetbootService] Removed PXE config #{config_path}")
      end
    end

    def pxe_enabled?
      # Check if PXE/TFTP is configured
      ENV["NETBOOT_ENABLED"] == "true"
    end
  end
end
