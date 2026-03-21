# frozen_string_literal: true

module System
  module Providers
    # Microsoft Azure cloud provider adapter
    # Uses azure_mgmt_compute SDK for cloud operations
    class AzureProvider < BaseProvider
      # Azure-specific status mappings
      AZURE_STATUS_MAP = {
        "VM starting" => "starting",
        "VM running" => "running",
        "VM stopping" => "stopping",
        "VM stopped" => "stopped",
        "VM deallocating" => "stopping",
        "VM deallocated" => "stopped",
        "VM creating" => "pending",
        "VM deleting" => "terminating"
      }.freeze

      def provider_type
        "azure"
      end

      # ===========================================
      # Instance Lifecycle Operations
      # ===========================================

      def create_instance(params)
        log_operation("create_instance", params: params.except(:user_data, :custom_data))

        begin
          vm_params = build_vm_parameters(params)

          result = compute_client.virtual_machines.begin_create_or_update(
            resource_group,
            params[:name],
            vm_params
          )

          # Wait for creation to complete
          vm = wait_for_vm_operation(result)

          build_instance_response(
            cloud_id: vm.name,
            status: get_vm_status(vm.name),
            private_ip: get_vm_private_ip(vm.name),
            instance_type: vm.hardware_profile.vm_size
          )
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def start_instance(instance_id)
        log_operation("start_instance", instance_id: instance_id)

        begin
          compute_client.virtual_machines.begin_start(resource_group, instance_id)

          build_instance_response(
            cloud_id: instance_id,
            status: "starting",
            private_ip: get_vm_private_ip(instance_id),
            public_ip: get_vm_public_ip(instance_id)
          )
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def stop_instance(instance_id, force: false)
        log_operation("stop_instance", instance_id: instance_id, force: force)

        begin
          if force
            compute_client.virtual_machines.begin_power_off(resource_group, instance_id)
          else
            compute_client.virtual_machines.begin_deallocate(resource_group, instance_id)
          end

          build_instance_response(
            cloud_id: instance_id,
            status: "stopping",
            private_ip: get_vm_private_ip(instance_id)
          )
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def reboot_instance(instance_id)
        log_operation("reboot_instance", instance_id: instance_id)

        begin
          compute_client.virtual_machines.begin_restart(resource_group, instance_id)

          build_instance_response(
            cloud_id: instance_id,
            status: "rebooting",
            private_ip: get_vm_private_ip(instance_id),
            public_ip: get_vm_public_ip(instance_id)
          )
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def terminate_instance(instance_id)
        log_operation("terminate_instance", instance_id: instance_id)

        begin
          compute_client.virtual_machines.begin_delete(resource_group, instance_id)

          build_instance_response(
            cloud_id: instance_id,
            status: "terminating"
          )
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def get_instance(instance_id)
        log_operation("get_instance", instance_id: instance_id)

        begin
          vm = compute_client.virtual_machines.get(
            resource_group,
            instance_id,
            expand: "instanceView"
          )

          return build_error_response("Instance not found", code: "NotFound") unless vm

          build_instance_response(
            cloud_id: vm.name,
            status: extract_vm_status(vm),
            private_ip: get_vm_private_ip(vm.name),
            public_ip: get_vm_public_ip(vm.name),
            instance_type: vm.hardware_profile.vm_size
          )
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def list_instances(filters = {})
        log_operation("list_instances", filters: filters)

        begin
          vms = compute_client.virtual_machines.list(resource_group)

          instances = vms.map do |vm|
            status = get_vm_status(vm.name)

            # Apply filters
            next if filters[:status] && status != filters[:status]

            build_instance_response(
              cloud_id: vm.name,
              status: status,
              private_ip: get_vm_private_ip(vm.name),
              public_ip: get_vm_public_ip(vm.name),
              instance_type: vm.hardware_profile.vm_size
            )
          end.compact

          { success: true, instances: instances }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      # ===========================================
      # IP Address Operations
      # ===========================================

      def allocate_ip
        log_operation("allocate_ip")

        begin
          ip_name = "powernode-ip-#{SecureRandom.hex(4)}"

          public_ip_params = Azure::Network::Mgmt::V2020_08_01::Models::PublicIPAddress.new.tap do |ip|
            ip.location = azure_location
            ip.public_ipallocation_method = Azure::Network::Mgmt::V2020_08_01::Models::IPAllocationMethod::Static
            ip.sku = Azure::Network::Mgmt::V2020_08_01::Models::PublicIPAddressSku.new.tap do |sku|
              sku.name = Azure::Network::Mgmt::V2020_08_01::Models::PublicIPAddressSkuName::Standard
            end
          end

          result = network_client.public_ipaddresses.begin_create_or_update(
            resource_group,
            ip_name,
            public_ip_params
          )

          public_ip = wait_for_network_operation(result)

          {
            success: true,
            allocation_id: public_ip.name,
            public_ip: public_ip.ip_address
          }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def associate_ip(instance_id, allocation_id: nil)
        log_operation("associate_ip", instance_id: instance_id, allocation_id: allocation_id)

        begin
          # Allocate new IP if not provided
          unless allocation_id
            alloc_result = allocate_ip
            return alloc_result unless alloc_result[:success]
            allocation_id = alloc_result[:allocation_id]
          end

          public_ip = network_client.public_ipaddresses.get(resource_group, allocation_id)
          return build_error_response("Public IP not found") unless public_ip

          # Get the VM's primary NIC
          vm = compute_client.virtual_machines.get(resource_group, instance_id)
          nic_ref = vm.network_profile.network_interfaces.first
          nic_name = nic_ref.id.split("/").last

          nic = network_client.network_interfaces.get(resource_group, nic_name)
          ip_config = nic.ip_configurations.first

          # Associate the public IP
          ip_config.public_ipaddress = public_ip

          result = network_client.network_interfaces.begin_create_or_update(
            resource_group,
            nic_name,
            nic
          )

          wait_for_network_operation(result)

          # Refresh public IP to get assigned address
          public_ip = network_client.public_ipaddresses.get(resource_group, allocation_id)

          {
            success: true,
            public_ip: public_ip.ip_address,
            allocation_id: allocation_id,
            association_id: "#{nic_name}:#{allocation_id}"
          }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def disassociate_ip(association_id)
        log_operation("disassociate_ip", association_id: association_id)

        begin
          nic_name, _ip_name = association_id.split(":")

          nic = network_client.network_interfaces.get(resource_group, nic_name)
          ip_config = nic.ip_configurations.first

          ip_config.public_ipaddress = nil

          result = network_client.network_interfaces.begin_create_or_update(
            resource_group,
            nic_name,
            nic
          )

          wait_for_network_operation(result)

          { success: true }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def release_ip(allocation_id)
        log_operation("release_ip", allocation_id: allocation_id)

        begin
          public_ip = network_client.public_ipaddresses.get(resource_group, allocation_id)

          if public_ip.ip_configuration.present?
            return build_error_response("IP is still associated, disassociate first")
          end

          network_client.public_ipaddresses.begin_delete(resource_group, allocation_id)

          { success: true }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      # ===========================================
      # Volume Operations
      # ===========================================

      def create_volume(params)
        log_operation("create_volume", params: params)

        begin
          disk_name = params[:name] || "powernode-disk-#{SecureRandom.hex(4)}"

          disk_params = Azure::Compute::Mgmt::V2020_12_01::Models::Disk.new.tap do |disk|
            disk.location = azure_location
            disk.disk_size_gb = params[:size_gb]
            disk.creation_data = Azure::Compute::Mgmt::V2020_12_01::Models::CreationData.new.tap do |cd|
              cd.create_option = Azure::Compute::Mgmt::V2020_12_01::Models::DiskCreateOption::Empty
            end
            disk.sku = Azure::Compute::Mgmt::V2020_12_01::Models::DiskSku.new.tap do |sku|
              sku.name = map_volume_type(params[:volume_type])
            end
          end

          result = compute_client.disks.begin_create_or_update(
            resource_group,
            disk_name,
            disk_params
          )

          disk = wait_for_disk_operation(result)

          {
            success: true,
            volume_id: disk.name,
            status: disk.provisioning_state&.downcase
          }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def attach_volume(volume_id, instance_id, device: nil)
        log_operation("attach_volume", volume_id: volume_id, instance_id: instance_id, device: device)

        begin
          disk = compute_client.disks.get(resource_group, volume_id)
          return build_error_response("Volume not found") unless disk

          vm = compute_client.virtual_machines.get(resource_group, instance_id)
          return build_error_response("Instance not found") unless vm

          # Get next available LUN
          existing_luns = vm.storage_profile.data_disks.map(&:lun)
          lun = ((0..63).to_a - existing_luns).first

          data_disk = Azure::Compute::Mgmt::V2020_12_01::Models::DataDisk.new.tap do |dd|
            dd.lun = lun
            dd.name = volume_id
            dd.create_option = Azure::Compute::Mgmt::V2020_12_01::Models::DiskCreateOptionTypes::Attach
            dd.managed_disk = Azure::Compute::Mgmt::V2020_12_01::Models::ManagedDiskParameters.new.tap do |md|
              md.id = disk.id
            end
          end

          vm.storage_profile.data_disks << data_disk

          result = compute_client.virtual_machines.begin_create_or_update(
            resource_group,
            instance_id,
            vm
          )

          wait_for_vm_operation(result)

          {
            success: true,
            device: "/dev/sd#{('c'.ord + lun).chr}",
            status: "attached"
          }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def detach_volume(volume_id, force: false)
        log_operation("detach_volume", volume_id: volume_id, force: force)

        begin
          disk = compute_client.disks.get(resource_group, volume_id)
          return build_error_response("Volume not found") unless disk

          managed_by = disk.managed_by
          return { success: true, message: "Volume not attached" } unless managed_by

          vm_name = managed_by.split("/").last
          vm = compute_client.virtual_machines.get(resource_group, vm_name)

          # Remove the disk from data_disks
          vm.storage_profile.data_disks.reject! { |d| d.name == volume_id }

          result = compute_client.virtual_machines.begin_create_or_update(
            resource_group,
            vm_name,
            vm
          )

          wait_for_vm_operation(result)

          { success: true }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def delete_volume(volume_id)
        log_operation("delete_volume", volume_id: volume_id)

        begin
          disk = compute_client.disks.get(resource_group, volume_id)
          return build_error_response("Volume not found") unless disk

          if disk.managed_by.present?
            return build_error_response("Volume is attached, detach first")
          end

          compute_client.disks.begin_delete(resource_group, volume_id)

          { success: true }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def get_volume(volume_id)
        log_operation("get_volume", volume_id: volume_id)

        begin
          disk = compute_client.disks.get(resource_group, volume_id)
          return build_error_response("Volume not found") unless disk

          attached_vm = disk.managed_by&.split("/")&.last

          {
            success: true,
            volume_id: disk.name,
            size_gb: disk.disk_size_gb,
            volume_type: disk.sku.name,
            status: attached_vm ? "attached" : "available",
            attached_to: attached_vm,
            device: nil # Azure doesn't expose device path directly
          }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      # ===========================================
      # Image Operations
      # ===========================================

      def create_image(instance_id, name:, description: nil)
        log_operation("create_image", instance_id: instance_id, name: name)

        begin
          vm = compute_client.virtual_machines.get(resource_group, instance_id)
          return build_error_response("Instance not found") unless vm

          # VM must be stopped/deallocated for imaging
          status = get_vm_status(instance_id)
          unless %w[stopped].include?(status)
            return build_error_response("VM must be stopped before creating image")
          end

          # Generalize the VM (required for Azure image creation)
          compute_client.virtual_machines.generalize(resource_group, instance_id)

          image_name = name.downcase.gsub(/[^a-z0-9-]/, "-")

          image_params = Azure::Compute::Mgmt::V2020_12_01::Models::Image.new.tap do |img|
            img.location = azure_location
            img.tags = { "description" => description || "Created by Powernode" }
            img.source_virtual_machine = Azure::Compute::Mgmt::V2020_12_01::Models::SubResource.new.tap do |sr|
              sr.id = vm.id
            end
          end

          result = compute_client.images.begin_create_or_update(
            resource_group,
            image_name,
            image_params
          )

          wait_for_image_operation(result)

          {
            success: true,
            image_id: image_name,
            status: "pending"
          }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def get_image(image_id)
        log_operation("get_image", image_id: image_id)

        begin
          image = compute_client.images.get(resource_group, image_id)
          return build_error_response("Image not found") unless image

          {
            success: true,
            image_id: image.name,
            name: image.name,
            description: image.tags&.dig("description"),
            status: image.provisioning_state&.downcase == "succeeded" ? "available" : "pending"
          }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      def delete_image(image_id)
        log_operation("delete_image", image_id: image_id)

        begin
          compute_client.images.begin_delete(resource_group, image_id)
          { success: true }
        rescue MsRestAzure::AzureOperationError => e
          handle_azure_error(e)
        end
      end

      # ===========================================
      # Utility Methods
      # ===========================================

      def test_connection
        log_operation("test_connection")

        begin
          # Try to list resource groups as a connection test
          locations = compute_client.virtual_machine_sizes.list(azure_location)

          {
            success: true,
            message: "Azure connection successful",
            provider: "azure",
            subscription: subscription_id,
            location: azure_location,
            available_sizes: locations.take(10).map(&:name)
          }
        rescue MsRestAzure::AzureOperationError => e
          {
            success: false,
            error: "Azure connection failed: #{e.message}",
            error_code: e.class.name
          }
        end
      end

      def get_metadata
        {
          provider: "azure",
          subscription: subscription_id,
          resource_group: resource_group,
          location: azure_location,
          features: %w[instances disks public_ips images snapshots vnets nsgs]
        }
      end

      protected

      def normalize_status(provider_status)
        AZURE_STATUS_MAP[provider_status] || "unknown"
      end

      private

      def compute_client
        @compute_client ||= Azure::Compute::Mgmt::V2020_12_01::ComputeManagementClient.new(azure_credentials).tap do |client|
          client.subscription_id = subscription_id
        end
      end

      def network_client
        @network_client ||= Azure::Network::Mgmt::V2020_08_01::NetworkManagementClient.new(azure_credentials).tap do |client|
          client.subscription_id = subscription_id
        end
      end

      def azure_credentials
        @azure_credentials ||= MsRest::TokenCredentials.new(
          MsRestAzure::ApplicationTokenProvider.new(
            tenant_id,
            client_id,
            client_secret
          )
        )
      end

      def subscription_id
        connection.config&.dig("subscription_id") || connection.tenant
      end

      def tenant_id
        connection.config&.dig("tenant_id")
      end

      def client_id
        connection.access_key
      end

      def client_secret
        connection.secret_key
      end

      def resource_group
        connection.config&.dig("resource_group") || "powernode-rg"
      end

      def azure_location
        region&.region_code || connection.config&.dig("default_location") || "eastus"
      end

      def get_vm_status(vm_name)
        vm = compute_client.virtual_machines.get(
          resource_group,
          vm_name,
          expand: "instanceView"
        )
        extract_vm_status(vm)
      rescue StandardError
        "unknown"
      end

      def extract_vm_status(vm)
        return "unknown" unless vm.instance_view

        status = vm.instance_view.statuses.find { |s| s.code.start_with?("PowerState/") }
        return "unknown" unless status

        power_state = status.display_status
        normalize_status(power_state)
      end

      def get_vm_private_ip(vm_name)
        vm = compute_client.virtual_machines.get(resource_group, vm_name)
        nic_ref = vm.network_profile.network_interfaces.first
        return nil unless nic_ref

        nic_name = nic_ref.id.split("/").last
        nic = network_client.network_interfaces.get(resource_group, nic_name)
        nic.ip_configurations.first&.private_ipaddress
      rescue StandardError
        nil
      end

      def get_vm_public_ip(vm_name)
        vm = compute_client.virtual_machines.get(resource_group, vm_name)
        nic_ref = vm.network_profile.network_interfaces.first
        return nil unless nic_ref

        nic_name = nic_ref.id.split("/").last
        nic = network_client.network_interfaces.get(resource_group, nic_name)

        public_ip_ref = nic.ip_configurations.first&.public_ipaddress
        return nil unless public_ip_ref

        public_ip_name = public_ip_ref.id.split("/").last
        public_ip = network_client.public_ipaddresses.get(resource_group, public_ip_name)
        public_ip.ip_address
      rescue StandardError
        nil
      end

      def build_vm_parameters(params)
        Azure::Compute::Mgmt::V2020_12_01::Models::VirtualMachine.new.tap do |vm|
          vm.location = azure_location

          # Hardware profile
          vm.hardware_profile = Azure::Compute::Mgmt::V2020_12_01::Models::HardwareProfile.new.tap do |hw|
            hw.vm_size = params[:instance_type]
          end

          # OS profile
          vm.os_profile = Azure::Compute::Mgmt::V2020_12_01::Models::OSProfile.new.tap do |os|
            os.computer_name = params[:name]
            os.admin_username = params[:admin_user] || "powernode"
            os.admin_password = params[:admin_password] if params[:admin_password]
            os.custom_data = Base64.encode64(params[:user_data]) if params[:user_data]

            if params[:ssh_key]
              os.linux_configuration = Azure::Compute::Mgmt::V2020_12_01::Models::LinuxConfiguration.new.tap do |linux|
                linux.disable_password_authentication = true
                linux.ssh = Azure::Compute::Mgmt::V2020_12_01::Models::SshConfiguration.new.tap do |ssh|
                  ssh.public_keys = [
                    Azure::Compute::Mgmt::V2020_12_01::Models::SshPublicKey.new.tap do |key|
                      key.path = "/home/#{os.admin_username}/.ssh/authorized_keys"
                      key.key_data = params[:ssh_key]
                    end
                  ]
                end
              end
            end
          end

          # Storage profile
          vm.storage_profile = Azure::Compute::Mgmt::V2020_12_01::Models::StorageProfile.new.tap do |storage|
            storage.image_reference = build_image_reference(params[:image_id])
            storage.os_disk = Azure::Compute::Mgmt::V2020_12_01::Models::OSDisk.new.tap do |os_disk|
              os_disk.name = "#{params[:name]}-osdisk"
              os_disk.caching = Azure::Compute::Mgmt::V2020_12_01::Models::CachingTypes::ReadWrite
              os_disk.create_option = Azure::Compute::Mgmt::V2020_12_01::Models::DiskCreateOptionTypes::FromImage
              os_disk.managed_disk = Azure::Compute::Mgmt::V2020_12_01::Models::ManagedDiskParameters.new.tap do |md|
                md.storage_account_type = map_volume_type(params[:root_volume_type])
              end
              os_disk.disk_size_gb = params[:root_volume_size] if params[:root_volume_size]
            end
          end

          # Network profile
          vm.network_profile = Azure::Compute::Mgmt::V2020_12_01::Models::NetworkProfile.new.tap do |network|
            network.network_interfaces = [
              Azure::Compute::Mgmt::V2020_12_01::Models::NetworkInterfaceReference.new.tap do |nic_ref|
                nic_id = params[:network_interface_id] || create_default_nic(params[:name])
                nic_ref.id = nic_id
                nic_ref.primary = true
              end
            ]
          end

          # Tags
          if params[:tags].present?
            vm.tags = params[:tags].transform_keys(&:to_s).transform_values(&:to_s)
          end
        end
      end

      def build_image_reference(image_id)
        # Check if it's a marketplace image (publisher:offer:sku:version format)
        if image_id.include?(":")
          parts = image_id.split(":")
          Azure::Compute::Mgmt::V2020_12_01::Models::ImageReference.new.tap do |ref|
            ref.publisher = parts[0]
            ref.offer = parts[1]
            ref.sku = parts[2]
            ref.version = parts[3] || "latest"
          end
        else
          # Custom image ID
          Azure::Compute::Mgmt::V2020_12_01::Models::ImageReference.new.tap do |ref|
            ref.id = "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/images/#{image_id}"
          end
        end
      end

      def create_default_nic(vm_name)
        nic_name = "#{vm_name}-nic"

        # Get default subnet
        vnet_name = connection.config&.dig("default_vnet") || "powernode-vnet"
        subnet_name = connection.config&.dig("default_subnet") || "default"

        subnet = network_client.subnets.get(resource_group, vnet_name, subnet_name)

        nic_params = Azure::Network::Mgmt::V2020_08_01::Models::NetworkInterface.new.tap do |nic|
          nic.location = azure_location
          nic.ip_configurations = [
            Azure::Network::Mgmt::V2020_08_01::Models::NetworkInterfaceIPConfiguration.new.tap do |ip_config|
              ip_config.name = "ipconfig1"
              ip_config.subnet = subnet
              ip_config.private_ipallocation_method = Azure::Network::Mgmt::V2020_08_01::Models::IPAllocationMethod::Dynamic
            end
          ]
        end

        result = network_client.network_interfaces.begin_create_or_update(
          resource_group,
          nic_name,
          nic_params
        )

        nic = wait_for_network_operation(result)
        nic.id
      end

      def map_volume_type(type)
        case type&.downcase
        when "standard", "standard_lrs"
          Azure::Compute::Mgmt::V2020_12_01::Models::StorageAccountTypes::StandardLRS
        when "premium", "premium_lrs"
          Azure::Compute::Mgmt::V2020_12_01::Models::StorageAccountTypes::PremiumLRS
        when "standardssd", "standardssd_lrs"
          Azure::Compute::Mgmt::V2020_12_01::Models::StorageAccountTypes::StandardSSDLRS
        else
          Azure::Compute::Mgmt::V2020_12_01::Models::StorageAccountTypes::StandardLRS
        end
      end

      def wait_for_vm_operation(operation, timeout: 300)
        deadline = Time.current + timeout

        while Time.current < deadline
          if operation.respond_to?(:value!)
            return operation.value!
          end

          sleep 5
          # Re-fetch operation status
        end

        raise StandardError, "Operation timed out"
      end

      def wait_for_network_operation(operation, timeout: 120)
        deadline = Time.current + timeout

        while Time.current < deadline
          if operation.respond_to?(:value!)
            return operation.value!
          end

          sleep 3
        end

        raise StandardError, "Network operation timed out"
      end

      def wait_for_disk_operation(operation, timeout: 120)
        wait_for_network_operation(operation, timeout: timeout)
      end

      def wait_for_image_operation(operation, timeout: 600)
        wait_for_vm_operation(operation, timeout: timeout)
      end

      def handle_azure_error(error)
        logger.error("[AzureProvider] Azure Error: #{error.class} - #{error.message}")

        error_body = error.body if error.respond_to?(:body)
        error_code = error_body&.dig("error", "code")

        case error_code
        when "AuthorizationFailed", "AuthenticationFailed"
          raise AuthenticationError, "Azure authentication failed: #{error.message}"
        when "TooManyRequests", "RequestRateTooLarge"
          raise RateLimitError, "Azure rate limit exceeded: #{error.message}"
        when "ResourceNotFound", "NotFound"
          raise ResourceNotFoundError, error.message
        when "QuotaExceeded", "OperationNotAllowed"
          raise QuotaExceededError, error.message
        else
          build_error_response(error.message, code: error_code)
        end
      end
    end
  end
end
