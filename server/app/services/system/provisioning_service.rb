# frozen_string_literal: true

module System
  # Service for provisioning cloud instances
  # Uses provider adapters for multi-cloud support
  class ProvisioningService
    class ProvisioningError < StandardError; end

    # Provision a new instance for a node
    #
    # @param node [System::Node] The node to provision for
    # @param provider_region_id [String] The region to provision in
    # @param provider_instance_type_id [String] The instance type to use
    # @param operation_id [String, nil] Optional operation ID for tracking
    # @param options [Hash] Additional provisioning options
    # @return [Hash] Result with :success, :instance, :cloud_instance_id, :error
    def self.provision_instance(node:, provider_region_id:, provider_instance_type_id:, operation_id: nil, options: {})
      new.provision_instance(
        node: node,
        provider_region_id: provider_region_id,
        provider_instance_type_id: provider_instance_type_id,
        operation_id: operation_id,
        options: options
      )
    end

    def provision_instance(node:, provider_region_id:, provider_instance_type_id:, operation_id: nil, options: {})
      validate_node!(node)

      # Get region and instance type
      region = ::System::ProviderRegion.find_by(id: provider_region_id)
      instance_type = ::System::ProviderInstanceType.find_by(id: provider_instance_type_id)

      unless region
        return { success: false, error: "Provider region not found" }
      end

      unless instance_type
        return { success: false, error: "Instance type not found" }
      end

      # Get provider adapter through the registry
      provider_adapter = begin
        Providers::Registry.for_node(node, region: region)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      Rails.logger.info("[ProvisioningService] Provisioning instance for node #{node.name} in #{region.name} using #{provider_adapter.provider_type}")

      begin
        # Generate instance name
        instance_name = generate_instance_name(node, options)

        # Create the instance record
        instance = ::System::NodeInstance.create!(
          name: instance_name,
          node: node,
          variety: "cloud",
          status: "pending",
          provider_region: region,
          provider_instance_type: instance_type,
          admin_user: options[:admin_user] || node.node_template&.admin_user || "ubuntu",
          account: node.account
        )

        # Build provider params
        provider_params = build_provider_params(
          region: region,
          instance_type: instance_type,
          instance: instance,
          node: node,
          options: options
        )

        # Provision via cloud provider adapter
        cloud_result = provider_adapter.create_instance(provider_params)

        if cloud_result[:success]
          # Update instance with cloud details
          instance.update!(
            cloud_instance_id: cloud_result[:cloud_instance_id],
            private_ip_address: cloud_result[:private_ip_address],
            public_ip_address: cloud_result[:public_ip_address],
            status: normalize_status(cloud_result[:status])
          )

          # Associate public IP if requested
          if options[:allocate_public_ip] && cloud_result[:public_ip_address].blank?
            associate_public_ip(provider_adapter, instance, cloud_result[:cloud_instance_id])
          end

          {
            success: true,
            instance: instance,
            cloud_instance_id: cloud_result[:cloud_instance_id]
          }
        else
          # Clean up failed instance
          instance.update!(status: "failed")

          {
            success: false,
            error: cloud_result[:error],
            instance: instance
          }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[ProvisioningService] Provider error: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[ProvisioningService] Provisioning failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Terminate an instance
    #
    # @param instance [System::NodeInstance] The instance to terminate
    # @return [Hash] Result with :success, :error
    def self.terminate_instance(instance:)
      new.terminate_instance(instance: instance)
    end

    def terminate_instance(instance:)
      validate_instance!(instance)

      unless instance.cloud_instance_id.present?
        return { success: false, error: "Instance has no cloud instance ID" }
      end

      provider_adapter = begin
        Providers::Registry.for_instance(instance)
      rescue Providers::Registry::UnknownProviderError => e
        return { success: false, error: e.message }
      end

      Rails.logger.info("[ProvisioningService] Terminating instance #{instance.name}")

      begin
        result = provider_adapter.terminate_instance(instance.cloud_instance_id)

        if result[:success]
          instance.update!(status: "terminating")
          { success: true }
        else
          { success: false, error: result[:error] }
        end
      rescue Providers::BaseProvider::ProviderError => e
        Rails.logger.error("[ProvisioningService] Terminate error: #{e.message}")
        { success: false, error: e.message }
      end
    end

    private

    def validate_node!(node)
      raise ArgumentError, "Node required" unless node
      raise ArgumentError, "Node must be a System::Node" unless node.is_a?(::System::Node)
      raise ProvisioningError, "Node is disabled" unless node.enabled
    end

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
    end

    def generate_instance_name(node, options)
      base_name = options[:name] || "#{node.name}-instance"
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      "#{base_name}-#{timestamp}"
    end

    def build_provider_params(region:, instance_type:, instance:, node:, options:)
      params = {
        name: instance.name,
        instance_type: instance_type.name,
        image_id: region.machine_image,
        key_name: options[:key_name],
        security_groups: options[:security_groups],
        subnet_id: options[:subnet_id],
        network_id: options[:network_id],
        availability_zone: options[:availability_zone]
      }

      # Add user data / startup script if provided
      if options[:user_data].present?
        params[:user_data] = options[:user_data]
      elsif node.node_template&.init_script.present?
        params[:user_data] = node.node_template.init_script
      end

      # Add root volume configuration
      if options[:root_volume_size]
        params[:root_volume_size] = options[:root_volume_size]
        params[:root_volume_type] = options[:root_volume_type]
      end

      # Add SSH key for Linux instances
      if options[:ssh_key].present?
        params[:ssh_key] = options[:ssh_key]
      elsif node.ssh_key.present?
        params[:ssh_key] = node.ssh_key
      end

      # Add tags
      params[:tags] = {
        "powernode:node_id" => node.id,
        "powernode:instance_id" => instance.id,
        "powernode:account_id" => node.account_id,
        "Name" => instance.name
      }.merge(options[:tags] || {})

      params.compact
    end

    def associate_public_ip(provider_adapter, instance, cloud_instance_id)
      Rails.logger.info("[ProvisioningService] Associating public IP for #{instance.name}")

      result = provider_adapter.associate_ip(cloud_instance_id)

      if result[:success] && result[:public_ip].present?
        instance.update!(public_ip_address: result[:public_ip])
        Rails.logger.info("[ProvisioningService] Associated IP #{result[:public_ip]} to #{instance.name}")
      end
    rescue Providers::BaseProvider::ProviderError => e
      Rails.logger.warn("[ProvisioningService] Failed to associate IP: #{e.message}")
    end

    def normalize_status(status)
      case status
      when "pending", "starting" then "starting"
      when "running" then "running"
      when "stopping" then "stopping"
      when "stopped" then "stopped"
      when "terminating" then "terminating"
      when "terminated" then "terminated"
      else "pending"
      end
    end
  end
end
