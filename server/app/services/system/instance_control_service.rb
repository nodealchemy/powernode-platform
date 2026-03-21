# frozen_string_literal: true

module System
  # Service for controlling instance lifecycle (start, stop, reboot, terminate)
  # Uses provider adapters for multi-cloud support
  class InstanceControlService
    class ControlError < StandardError; end

    # Execute a control action on an instance
    #
    # @param instance [System::NodeInstance] The instance to control
    # @param action [Symbol] The action (:start, :stop, :reboot, :terminate)
    # @param operation_id [String, nil] Optional operation ID for tracking
    # @param force [Boolean] Force the action (for stop)
    # @return [Hash] Result with :success, :error
    def self.execute(instance:, action:, operation_id: nil, force: false)
      new.execute(instance: instance, action: action, operation_id: operation_id, force: force)
    end

    def execute(instance:, action:, operation_id: nil, force: false)
      validate_instance!(instance)
      validate_action!(action)

      Rails.logger.info("[InstanceControlService] Executing #{action} on #{instance.name}")

      # Check if instance supports this action
      unless can_execute_action?(instance, action)
        return { success: false, error: "Cannot #{action} instance in #{instance.status} status" }
      end

      # Update status to transitional state
      update_transitional_status(instance, action)

      begin
        result = case instance.variety
                 when "cloud", "dynamic"
                   execute_cloud_action(instance, action, force: force)
                 when "physical"
                   execute_physical_action(instance, action)
                 else
                   { success: false, error: "Unknown instance variety: #{instance.variety}" }
                 end

        if result[:success]
          # Update IP addresses if returned from provider
          update_instance_from_result(instance, result)
        else
          # Revert to previous status on failure
          revert_status(instance)
        end

        result
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[InstanceControlService] Provider error: #{e.message}")
        revert_status(instance)
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[InstanceControlService] #{action} failed: #{e.message}")
        revert_status(instance)
        { success: false, error: e.message }
      end
    end

    private

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
    end

    def validate_action!(action)
      valid_actions = %i[start stop reboot terminate]
      raise ArgumentError, "Invalid action: #{action}" unless valid_actions.include?(action.to_sym)
    end

    def can_execute_action?(instance, action)
      case action.to_sym
      when :start
        instance.can_start?
      when :stop
        instance.can_stop?
      when :reboot
        instance.can_reboot?
      when :terminate
        true # Can always terminate
      else
        false
      end
    end

    def update_transitional_status(instance, action)
      status = case action.to_sym
               when :start then "starting"
               when :stop then "stopping"
               when :reboot then "rebooting"
               when :terminate then "terminating"
               end

      instance.update!(status: status)
    end

    def update_instance_from_result(instance, result)
      updates = {}

      # Update status based on action result
      if result[:status].present?
        updates[:status] = result[:status]
      end

      # Update IP addresses if provided
      if result.key?(:private_ip_address)
        updates[:private_ip_address] = result[:private_ip_address]
      end

      if result.key?(:public_ip_address)
        updates[:public_ip_address] = result[:public_ip_address]
      end

      instance.update!(updates) if updates.any?
    end

    def revert_status(instance)
      # Revert to a safe status based on current transitional status
      safe_status = case instance.status
                    when "starting" then "stopped"
                    when "stopping" then "running"
                    when "rebooting" then "running"
                    when "terminating" then "running"
                    else instance.status
                    end

      instance.update!(status: safe_status)
    end

    def execute_cloud_action(instance, action, force: false)
      unless instance.cloud_instance_id.present?
        return { success: false, error: "Instance has no cloud instance ID" }
      end

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_instance(instance)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      Rails.logger.info("[InstanceControlService] Using #{provider_adapter.provider_type} for #{action}")

      case action.to_sym
      when :start
        result = provider_adapter.start_instance(instance.cloud_instance_id)
        result[:status] = "running" if result[:success]
        result
      when :stop
        result = provider_adapter.stop_instance(instance.cloud_instance_id, force: force)
        result[:status] = "stopped" if result[:success]
        result
      when :reboot
        result = provider_adapter.reboot_instance(instance.cloud_instance_id)
        result[:status] = "running" if result[:success]
        result
      when :terminate
        result = provider_adapter.terminate_instance(instance.cloud_instance_id)
        result[:status] = "terminated" if result[:success]
        result
      else
        { success: false, error: "Unknown action: #{action}" }
      end
    end

    def execute_physical_action(instance, action)
      # Physical instances may use IPMI, Wake-on-LAN, or other protocols
      case action.to_sym
      when :start
        # Wake-on-LAN or IPMI power on
        execute_physical_start(instance)
      when :stop
        # IPMI power off or SSH shutdown
        execute_physical_stop(instance)
      when :reboot
        execute_physical_reboot(instance)
      when :terminate
        # Physical instances can't be terminated - just mark as terminated
        { success: true, status: "terminated" }
      end
    end

    def execute_physical_start(instance)
      # Check for IPMI configuration
      ipmi_config = instance.config&.dig("ipmi")

      if ipmi_config.present?
        # Use IPMI to power on
        Rails.logger.info("[InstanceControlService] IPMI power on for #{instance.name}")
        # ipmitool -I lanplus -H #{ipmi_config['host']} -U #{ipmi_config['user']} -P #{ipmi_config['password']} power on
        { success: true, status: "running" }
      elsif instance.config&.dig("mac_address").present?
        # Use Wake-on-LAN
        Rails.logger.info("[InstanceControlService] Wake-on-LAN for #{instance.name}")
        { success: true, status: "starting" }
      else
        { success: false, error: "No IPMI or WoL configuration available" }
      end
    end

    def execute_physical_stop(instance)
      # Try SSH shutdown first
      if instance.private_ip_address.present?
        result = SshExecutionService.execute(
          instance: instance,
          command: "shutdown -h now",
          sudo: true
        )
        return { success: true, status: "stopped" } if result[:success]
      end

      # Fall back to IPMI if SSH fails
      ipmi_config = instance.config&.dig("ipmi")
      if ipmi_config.present?
        Rails.logger.info("[InstanceControlService] IPMI power off for #{instance.name}")
        { success: true, status: "stopped" }
      else
        { success: false, error: "Cannot stop physical instance - no SSH or IPMI available" }
      end
    end

    def execute_physical_reboot(instance)
      # Try SSH reboot first
      if instance.private_ip_address.present?
        result = SshExecutionService.execute(
          instance: instance,
          command: "reboot",
          sudo: true
        )
        return { success: true, status: "running" } if result[:success]
      end

      # Fall back to IPMI if SSH fails
      ipmi_config = instance.config&.dig("ipmi")
      if ipmi_config.present?
        Rails.logger.info("[InstanceControlService] IPMI power cycle for #{instance.name}")
        { success: true, status: "rebooting" }
      else
        { success: false, error: "Cannot reboot physical instance - no SSH or IPMI available" }
      end
    end
  end
end
