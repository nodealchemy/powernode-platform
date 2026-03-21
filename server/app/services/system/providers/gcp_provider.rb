# frozen_string_literal: true

module System
  module Providers
    # Google Cloud Platform compute provider adapter
    # Uses google-cloud-compute for cloud operations
    class GcpProvider < BaseProvider
      # GCP-specific status mappings
      GCP_STATUS_MAP = {
        "PROVISIONING" => "pending",
        "STAGING" => "pending",
        "RUNNING" => "running",
        "STOPPING" => "stopping",
        "STOPPED" => "stopped",
        "SUSPENDING" => "stopping",
        "SUSPENDED" => "stopped",
        "TERMINATED" => "terminated"
      }.freeze

      def provider_type
        "gcp"
      end

      # ===========================================
      # Instance Lifecycle Operations
      # ===========================================

      def create_instance(params)
        log_operation("create_instance", params: params.except(:user_data, :startup_script))

        begin
          instance_resource = build_instance_resource(params)

          operation = instances_client.insert(
            project: project_id,
            zone: zone,
            instance_resource: instance_resource
          )

          wait_for_operation(operation)

          # Get the created instance
          instance = instances_client.get(
            project: project_id,
            zone: zone,
            instance: params[:name]
          )

          build_instance_response(
            cloud_id: instance.name,
            status: normalize_status(instance.status),
            private_ip: extract_private_ip(instance),
            instance_type: extract_machine_type(instance.machine_type)
          )
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def start_instance(instance_id)
        log_operation("start_instance", instance_id: instance_id)

        begin
          operation = instances_client.start(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          wait_for_operation(operation)

          instance = instances_client.get(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          build_instance_response(
            cloud_id: instance_id,
            status: "starting",
            private_ip: extract_private_ip(instance),
            public_ip: extract_public_ip(instance)
          )
        rescue Google::Cloud::NotFoundError
          build_error_response("Instance not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def stop_instance(instance_id, force: false)
        log_operation("stop_instance", instance_id: instance_id, force: force)

        begin
          operation = instances_client.stop(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          wait_for_operation(operation)

          instance = instances_client.get(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          build_instance_response(
            cloud_id: instance_id,
            status: "stopping",
            private_ip: extract_private_ip(instance)
          )
        rescue Google::Cloud::NotFoundError
          build_error_response("Instance not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def reboot_instance(instance_id)
        log_operation("reboot_instance", instance_id: instance_id)

        begin
          operation = instances_client.reset(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          wait_for_operation(operation)

          instance = instances_client.get(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          build_instance_response(
            cloud_id: instance_id,
            status: "rebooting",
            private_ip: extract_private_ip(instance),
            public_ip: extract_public_ip(instance)
          )
        rescue Google::Cloud::NotFoundError
          build_error_response("Instance not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def terminate_instance(instance_id)
        log_operation("terminate_instance", instance_id: instance_id)

        begin
          operation = instances_client.delete(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          wait_for_operation(operation)

          build_instance_response(
            cloud_id: instance_id,
            status: "terminating"
          )
        rescue Google::Cloud::NotFoundError
          build_error_response("Instance not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def get_instance(instance_id)
        log_operation("get_instance", instance_id: instance_id)

        begin
          instance = instances_client.get(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          build_instance_response(
            cloud_id: instance.name,
            status: normalize_status(instance.status),
            private_ip: extract_private_ip(instance),
            public_ip: extract_public_ip(instance),
            instance_type: extract_machine_type(instance.machine_type)
          )
        rescue Google::Cloud::NotFoundError
          build_error_response("Instance not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def list_instances(filters = {})
        log_operation("list_instances", filters: filters)

        begin
          filter_string = build_filter_string(filters)

          response = instances_client.list(
            project: project_id,
            zone: zone,
            filter: filter_string
          )

          instances = response.map do |instance|
            build_instance_response(
              cloud_id: instance.name,
              status: normalize_status(instance.status),
              private_ip: extract_private_ip(instance),
              public_ip: extract_public_ip(instance),
              instance_type: extract_machine_type(instance.machine_type)
            )
          end

          { success: true, instances: instances }
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      # ===========================================
      # IP Address Operations
      # ===========================================

      def allocate_ip
        log_operation("allocate_ip")

        begin
          address_name = "powernode-ip-#{SecureRandom.hex(4)}"

          address_resource = Google::Cloud::Compute::V1::Address.new(
            name: address_name,
            address_type: "EXTERNAL"
          )

          operation = addresses_client.insert(
            project: project_id,
            region: gcp_region,
            address_resource: address_resource
          )

          wait_for_regional_operation(operation)

          address = addresses_client.get(
            project: project_id,
            region: gcp_region,
            address: address_name
          )

          {
            success: true,
            allocation_id: address.name,
            public_ip: address.address
          }
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
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

          address = addresses_client.get(
            project: project_id,
            region: gcp_region,
            address: allocation_id
          )

          instance = instances_client.get(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          # Get the network interface
          network_interface = instance.network_interfaces.first
          return build_error_response("No network interface found") unless network_interface

          # Create access config with external IP
          access_config = Google::Cloud::Compute::V1::AccessConfig.new(
            name: "External NAT",
            type: "ONE_TO_ONE_NAT",
            nat_i_p: address.address
          )

          operation = instances_client.add_access_config(
            project: project_id,
            zone: zone,
            instance: instance_id,
            network_interface: network_interface.name,
            access_config_resource: access_config
          )

          wait_for_operation(operation)

          {
            success: true,
            public_ip: address.address,
            allocation_id: allocation_id,
            association_id: "#{instance_id}:#{allocation_id}"
          }
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def disassociate_ip(association_id)
        log_operation("disassociate_ip", association_id: association_id)

        begin
          instance_id, _allocation_id = association_id.split(":")

          instance = instances_client.get(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          network_interface = instance.network_interfaces.first
          access_config = network_interface&.access_configs&.first

          return { success: true, message: "No IP associated" } unless access_config

          operation = instances_client.delete_access_config(
            project: project_id,
            zone: zone,
            instance: instance_id,
            network_interface: network_interface.name,
            access_config: access_config.name
          )

          wait_for_operation(operation)

          { success: true }
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def release_ip(allocation_id)
        log_operation("release_ip", allocation_id: allocation_id)

        begin
          address = addresses_client.get(
            project: project_id,
            region: gcp_region,
            address: allocation_id
          )

          if address.status == "IN_USE"
            return build_error_response("IP is still in use, disassociate first")
          end

          operation = addresses_client.delete(
            project: project_id,
            region: gcp_region,
            address: allocation_id
          )

          wait_for_regional_operation(operation)

          { success: true }
        rescue Google::Cloud::NotFoundError
          build_error_response("IP not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      # ===========================================
      # Volume Operations
      # ===========================================

      def create_volume(params)
        log_operation("create_volume", params: params)

        begin
          disk_name = params[:name] || "powernode-disk-#{SecureRandom.hex(4)}"

          disk_resource = Google::Cloud::Compute::V1::Disk.new(
            name: disk_name,
            size_gb: params[:size_gb],
            type: disk_type_url(params[:volume_type] || "pd-standard")
          )

          operation = disks_client.insert(
            project: project_id,
            zone: zone,
            disk_resource: disk_resource
          )

          wait_for_operation(operation)

          {
            success: true,
            volume_id: disk_name,
            status: "available"
          }
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def attach_volume(volume_id, instance_id, device: nil)
        log_operation("attach_volume", volume_id: volume_id, instance_id: instance_id, device: device)

        begin
          attached_disk = Google::Cloud::Compute::V1::AttachedDisk.new(
            source: disk_url(volume_id),
            device_name: device || volume_id
          )

          operation = instances_client.attach_disk(
            project: project_id,
            zone: zone,
            instance: instance_id,
            attached_disk_resource: attached_disk
          )

          wait_for_operation(operation)

          {
            success: true,
            device: "/dev/disk/by-id/google-#{device || volume_id}",
            status: "attached"
          }
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def detach_volume(volume_id, force: false)
        log_operation("detach_volume", volume_id: volume_id, force: force)

        begin
          disk = disks_client.get(
            project: project_id,
            zone: zone,
            disk: volume_id
          )

          users = disk.users || []
          return { success: true, message: "Volume not attached" } if users.empty?

          # Extract instance name from user URL
          instance_url = users.first
          instance_name = instance_url.split("/").last

          operation = instances_client.detach_disk(
            project: project_id,
            zone: zone,
            instance: instance_name,
            device_name: volume_id
          )

          wait_for_operation(operation)

          { success: true }
        rescue Google::Cloud::NotFoundError
          build_error_response("Volume not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def delete_volume(volume_id)
        log_operation("delete_volume", volume_id: volume_id)

        begin
          disk = disks_client.get(
            project: project_id,
            zone: zone,
            disk: volume_id
          )

          if disk.users&.any?
            return build_error_response("Volume is attached, detach first")
          end

          operation = disks_client.delete(
            project: project_id,
            zone: zone,
            disk: volume_id
          )

          wait_for_operation(operation)

          { success: true }
        rescue Google::Cloud::NotFoundError
          build_error_response("Volume not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def get_volume(volume_id)
        log_operation("get_volume", volume_id: volume_id)

        begin
          disk = disks_client.get(
            project: project_id,
            zone: zone,
            disk: volume_id
          )

          users = disk.users || []
          attached_instance = users.first&.split("/")&.last

          {
            success: true,
            volume_id: disk.name,
            size_gb: disk.size_gb,
            volume_type: extract_disk_type(disk.type),
            status: users.any? ? "attached" : "available",
            attached_to: attached_instance,
            device: users.any? ? "/dev/disk/by-id/google-#{disk.name}" : nil
          }
        rescue Google::Cloud::NotFoundError
          build_error_response("Volume not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      # ===========================================
      # Image Operations
      # ===========================================

      def create_image(instance_id, name:, description: nil)
        log_operation("create_image", instance_id: instance_id, name: name)

        begin
          instance = instances_client.get(
            project: project_id,
            zone: zone,
            instance: instance_id
          )

          # Get the boot disk
          boot_disk = instance.disks.find { |d| d.boot }
          return build_error_response("No boot disk found") unless boot_disk

          source_disk = boot_disk.source

          image_resource = Google::Cloud::Compute::V1::Image.new(
            name: name.downcase.gsub(/[^a-z0-9-]/, "-"),
            description: description || "Created by Powernode",
            source_disk: source_disk
          )

          operation = images_client.insert(
            project: project_id,
            image_resource: image_resource
          )

          wait_for_global_operation(operation)

          {
            success: true,
            image_id: image_resource.name,
            status: "pending"
          }
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def get_image(image_id)
        log_operation("get_image", image_id: image_id)

        begin
          image = images_client.get(
            project: project_id,
            image: image_id
          )

          status = case image.status
                   when "READY" then "available"
                   when "PENDING" then "pending"
                   when "FAILED" then "failed"
                   else "unknown"
                   end

          {
            success: true,
            image_id: image.name,
            name: image.name,
            description: image.description,
            status: status
          }
        rescue Google::Cloud::NotFoundError
          build_error_response("Image not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      def delete_image(image_id)
        log_operation("delete_image", image_id: image_id)

        begin
          operation = images_client.delete(
            project: project_id,
            image: image_id
          )

          wait_for_global_operation(operation)

          { success: true }
        rescue Google::Cloud::NotFoundError
          build_error_response("Image not found", code: "NotFound")
        rescue Google::Cloud::Error => e
          handle_gcp_error(e)
        end
      end

      # ===========================================
      # Utility Methods
      # ===========================================

      def test_connection
        log_operation("test_connection")

        begin
          # Try to list zones as a connection test
          zones = zones_client.list(project: project_id)

          {
            success: true,
            message: "GCP connection successful",
            provider: "gcp",
            project: project_id,
            region: gcp_region,
            available_zones: zones.map(&:name)
          }
        rescue Google::Cloud::Error => e
          {
            success: false,
            error: "GCP connection failed: #{e.message}",
            error_code: e.class.name
          }
        end
      end

      def get_metadata
        {
          provider: "gcp",
          project: project_id,
          zone: zone,
          region: gcp_region,
          features: %w[instances disks addresses images snapshots networks firewalls]
        }
      end

      protected

      def normalize_status(provider_status)
        GCP_STATUS_MAP[provider_status] || "unknown"
      end

      private

      def instances_client
        @instances_client ||= Google::Cloud::Compute::V1::Instances::Rest::Client.new do |config|
          config.credentials = gcp_credentials
        end
      end

      def addresses_client
        @addresses_client ||= Google::Cloud::Compute::V1::Addresses::Rest::Client.new do |config|
          config.credentials = gcp_credentials
        end
      end

      def disks_client
        @disks_client ||= Google::Cloud::Compute::V1::Disks::Rest::Client.new do |config|
          config.credentials = gcp_credentials
        end
      end

      def images_client
        @images_client ||= Google::Cloud::Compute::V1::Images::Rest::Client.new do |config|
          config.credentials = gcp_credentials
        end
      end

      def zones_client
        @zones_client ||= Google::Cloud::Compute::V1::Zones::Rest::Client.new do |config|
          config.credentials = gcp_credentials
        end
      end

      def zone_operations_client
        @zone_operations_client ||= Google::Cloud::Compute::V1::ZoneOperations::Rest::Client.new do |config|
          config.credentials = gcp_credentials
        end
      end

      def region_operations_client
        @region_operations_client ||= Google::Cloud::Compute::V1::RegionOperations::Rest::Client.new do |config|
          config.credentials = gcp_credentials
        end
      end

      def global_operations_client
        @global_operations_client ||= Google::Cloud::Compute::V1::GlobalOperations::Rest::Client.new do |config|
          config.credentials = gcp_credentials
        end
      end

      def gcp_credentials
        # GCP credentials from service account JSON stored in secret_key
        @gcp_credentials ||= begin
          if connection.secret_key.present?
            JSON.parse(connection.secret_key)
          else
            # Fall back to application default credentials
            nil
          end
        end
      end

      def project_id
        connection.tenant || connection.config&.dig("project_id") || gcp_credentials&.dig("project_id")
      end

      def gcp_region
        region&.region_code || connection.config&.dig("default_region") || "us-central1"
      end

      def zone
        connection.config&.dig("default_zone") || "#{gcp_region}-a"
      end

      def wait_for_operation(operation, timeout: 120)
        deadline = Time.current + timeout

        while Time.current < deadline
          result = zone_operations_client.get(
            project: project_id,
            zone: zone,
            operation: operation.name
          )

          return result if result.status == :DONE

          if result.error&.errors&.any?
            raise Google::Cloud::Error, result.error.errors.first.message
          end

          sleep 2
        end

        raise Google::Cloud::Error, "Operation timed out"
      end

      def wait_for_regional_operation(operation, timeout: 120)
        deadline = Time.current + timeout

        while Time.current < deadline
          result = region_operations_client.get(
            project: project_id,
            region: gcp_region,
            operation: operation.name
          )

          return result if result.status == :DONE

          if result.error&.errors&.any?
            raise Google::Cloud::Error, result.error.errors.first.message
          end

          sleep 2
        end

        raise Google::Cloud::Error, "Operation timed out"
      end

      def wait_for_global_operation(operation, timeout: 120)
        deadline = Time.current + timeout

        while Time.current < deadline
          result = global_operations_client.get(
            project: project_id,
            operation: operation.name
          )

          return result if result.status == :DONE

          if result.error&.errors&.any?
            raise Google::Cloud::Error, result.error.errors.first.message
          end

          sleep 2
        end

        raise Google::Cloud::Error, "Operation timed out"
      end

      def build_instance_resource(params)
        machine_type = "zones/#{zone}/machineTypes/#{params[:instance_type]}"

        instance = Google::Cloud::Compute::V1::Instance.new(
          name: params[:name],
          machine_type: machine_type
        )

        # Boot disk
        boot_disk = Google::Cloud::Compute::V1::AttachedDisk.new(
          boot: true,
          auto_delete: true,
          initialize_params: Google::Cloud::Compute::V1::AttachedDiskInitializeParams.new(
            source_image: params[:image_id],
            disk_size_gb: params[:root_volume_size] || 20,
            disk_type: disk_type_url(params[:root_volume_type] || "pd-standard")
          )
        )
        instance.disks = [boot_disk]

        # Network interface
        network_interface = Google::Cloud::Compute::V1::NetworkInterface.new(
          network: params[:network_id] || "global/networks/default"
        )

        if params[:allocate_public_ip]
          network_interface.access_configs = [
            Google::Cloud::Compute::V1::AccessConfig.new(
              name: "External NAT",
              type: "ONE_TO_ONE_NAT"
            )
          ]
        end
        instance.network_interfaces = [network_interface]

        # Metadata (including startup script)
        if params[:user_data].present? || params[:startup_script].present?
          script = params[:startup_script] || params[:user_data]
          instance.metadata = Google::Cloud::Compute::V1::Metadata.new(
            items: [
              Google::Cloud::Compute::V1::Items.new(
                key: "startup-script",
                value: script
              )
            ]
          )
        end

        # Tags
        if params[:tags].present?
          instance.labels = params[:tags].transform_keys(&:to_s).transform_values(&:to_s)
        end

        instance
      end

      def build_filter_string(filters)
        conditions = []

        if filters[:status]
          gcp_status = GCP_STATUS_MAP.invert[filters[:status]]
          conditions << "status = #{gcp_status}" if gcp_status
        end

        conditions.join(" AND ")
      end

      def disk_type_url(type)
        "zones/#{zone}/diskTypes/#{type}"
      end

      def disk_url(disk_name)
        "zones/#{zone}/disks/#{disk_name}"
      end

      def extract_private_ip(instance)
        instance.network_interfaces&.first&.network_i_p
      end

      def extract_public_ip(instance)
        instance.network_interfaces&.first&.access_configs&.first&.nat_i_p
      end

      def extract_machine_type(machine_type_url)
        machine_type_url&.split("/")&.last
      end

      def extract_disk_type(disk_type_url)
        disk_type_url&.split("/")&.last
      end

      def handle_gcp_error(error)
        logger.error("[GcpProvider] GCP Error: #{error.class} - #{error.message}")

        case error
        when Google::Cloud::PermissionDeniedError
          raise AuthenticationError, "GCP authentication failed: #{error.message}"
        when Google::Cloud::ResourceExhaustedError
          raise RateLimitError, "GCP rate limit exceeded: #{error.message}"
        when Google::Cloud::NotFoundError
          raise ResourceNotFoundError, error.message
        else
          if error.message.include?("quota")
            raise QuotaExceededError, error.message
          else
            build_error_response(error.message, code: error.class.name)
          end
        end
      end
    end
  end
end
