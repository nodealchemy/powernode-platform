# frozen_string_literal: true

module System
  module Providers
    # OpenStack cloud provider adapter
    # Uses fog-openstack for cloud operations
    class OpenStackProvider < BaseProvider
      # OpenStack-specific status mappings
      OPENSTACK_STATUS_MAP = {
        "BUILD" => "pending",
        "ACTIVE" => "running",
        "SHUTOFF" => "stopped",
        "SUSPENDED" => "stopped",
        "PAUSED" => "stopped",
        "REBOOT" => "rebooting",
        "HARD_REBOOT" => "rebooting",
        "DELETED" => "terminated",
        "SOFT_DELETED" => "terminated",
        "ERROR" => "failed",
        "UNKNOWN" => "unknown"
      }.freeze

      def provider_type
        "openstack"
      end

      # ===========================================
      # Instance Lifecycle Operations
      # ===========================================

      def create_instance(params)
        log_operation("create_instance", params: params.except(:user_data))

        begin
          server_params = build_server_params(params)
          server = compute_client.servers.create(server_params)

          build_instance_response(
            cloud_id: server.id,
            status: normalize_status(server.state),
            private_ip: extract_private_ip(server),
            instance_type: params[:instance_type]
          )
        rescue Fog::OpenStack::Compute::NotFound => e
          build_error_response(e.message, code: "NotFound")
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def start_instance(instance_id)
        log_operation("start_instance", instance_id: instance_id)

        begin
          server = compute_client.servers.get(instance_id)
          return build_error_response("Instance not found") unless server

          server.start

          build_instance_response(
            cloud_id: instance_id,
            status: "starting",
            private_ip: extract_private_ip(server),
            public_ip: extract_public_ip(server)
          )
        rescue Fog::OpenStack::Compute::NotFound
          build_error_response("Instance not found", code: "NotFound")
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def stop_instance(instance_id, force: false)
        log_operation("stop_instance", instance_id: instance_id, force: force)

        begin
          server = compute_client.servers.get(instance_id)
          return build_error_response("Instance not found") unless server

          server.stop

          build_instance_response(
            cloud_id: instance_id,
            status: "stopping",
            private_ip: extract_private_ip(server)
          )
        rescue Fog::OpenStack::Compute::NotFound
          build_error_response("Instance not found", code: "NotFound")
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def reboot_instance(instance_id)
        log_operation("reboot_instance", instance_id: instance_id)

        begin
          server = compute_client.servers.get(instance_id)
          return build_error_response("Instance not found") unless server

          server.reboot("SOFT")

          build_instance_response(
            cloud_id: instance_id,
            status: "rebooting",
            private_ip: extract_private_ip(server),
            public_ip: extract_public_ip(server)
          )
        rescue Fog::OpenStack::Compute::NotFound
          build_error_response("Instance not found", code: "NotFound")
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def terminate_instance(instance_id)
        log_operation("terminate_instance", instance_id: instance_id)

        begin
          server = compute_client.servers.get(instance_id)
          return build_error_response("Instance not found") unless server

          server.destroy

          build_instance_response(
            cloud_id: instance_id,
            status: "terminating"
          )
        rescue Fog::OpenStack::Compute::NotFound
          build_error_response("Instance not found", code: "NotFound")
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def get_instance(instance_id)
        log_operation("get_instance", instance_id: instance_id)

        begin
          server = compute_client.servers.get(instance_id)
          return build_error_response("Instance not found", code: "NotFound") unless server

          build_instance_response(
            cloud_id: server.id,
            status: normalize_status(server.state),
            private_ip: extract_private_ip(server),
            public_ip: extract_public_ip(server),
            instance_type: server.flavor&.dig("id")
          )
        rescue Fog::OpenStack::Compute::NotFound
          build_error_response("Instance not found", code: "NotFound")
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def list_instances(filters = {})
        log_operation("list_instances", filters: filters)

        begin
          servers = compute_client.servers.all

          # Apply filters
          if filters[:status]
            target_status = filters[:status]
            servers = servers.select { |s| normalize_status(s.state) == target_status }
          end

          instances = servers.map do |server|
            build_instance_response(
              cloud_id: server.id,
              status: normalize_status(server.state),
              private_ip: extract_private_ip(server),
              public_ip: extract_public_ip(server)
            )
          end

          { success: true, instances: instances }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      # ===========================================
      # IP Address Operations
      # ===========================================

      def allocate_ip
        log_operation("allocate_ip")

        begin
          # Get floating IP pool from connection config
          pool_name = connection.config&.dig("floating_ip_pool") || "public"

          floating_ip = network_client.floating_ips.create(
            floating_network_id: get_external_network_id(pool_name)
          )

          {
            success: true,
            allocation_id: floating_ip.id,
            public_ip: floating_ip.floating_ip_address
          }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def associate_ip(instance_id, allocation_id: nil)
        log_operation("associate_ip", instance_id: instance_id, allocation_id: allocation_id)

        begin
          server = compute_client.servers.get(instance_id)
          return build_error_response("Instance not found") unless server

          # Allocate new IP if not provided
          unless allocation_id
            alloc_result = allocate_ip
            return alloc_result unless alloc_result[:success]
            allocation_id = alloc_result[:allocation_id]
          end

          floating_ip = network_client.floating_ips.get(allocation_id)
          return build_error_response("Floating IP not found") unless floating_ip

          # Get the first port of the server
          ports = network_client.ports.all(device_id: instance_id)
          port = ports.first
          return build_error_response("No port found for instance") unless port

          floating_ip.port_id = port.id
          floating_ip.save

          {
            success: true,
            public_ip: floating_ip.floating_ip_address,
            allocation_id: allocation_id,
            association_id: "#{allocation_id}:#{port.id}"
          }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def disassociate_ip(association_id)
        log_operation("disassociate_ip", association_id: association_id)

        begin
          floating_ip_id = association_id.split(":").first
          floating_ip = network_client.floating_ips.get(floating_ip_id)
          return build_error_response("Floating IP not found") unless floating_ip

          floating_ip.port_id = nil
          floating_ip.save

          { success: true }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def release_ip(allocation_id)
        log_operation("release_ip", allocation_id: allocation_id)

        begin
          floating_ip = network_client.floating_ips.get(allocation_id)
          return build_error_response("Floating IP not found") unless floating_ip

          if floating_ip.port_id.present?
            return build_error_response("IP is still associated, disassociate first")
          end

          floating_ip.destroy

          { success: true }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      # ===========================================
      # Volume Operations
      # ===========================================

      def create_volume(params)
        log_operation("create_volume", params: params)

        begin
          volume_params = {
            size: params[:size_gb],
            name: params[:name],
            description: params[:description],
            volume_type: params[:volume_type]
          }

          volume_params[:availability_zone] = params[:availability_zone] if params[:availability_zone]

          volume = volume_client.volumes.create(volume_params)

          {
            success: true,
            volume_id: volume.id,
            status: volume.status
          }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def attach_volume(volume_id, instance_id, device: nil)
        log_operation("attach_volume", volume_id: volume_id, instance_id: instance_id, device: device)

        begin
          volume = volume_client.volumes.get(volume_id)
          return build_error_response("Volume not found") unless volume

          server = compute_client.servers.get(instance_id)
          return build_error_response("Instance not found") unless server

          # Attach volume to server
          server.attach_volume(volume.id, device || "/dev/vdb")

          {
            success: true,
            device: device || "/dev/vdb",
            status: "attaching"
          }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def detach_volume(volume_id, force: false)
        log_operation("detach_volume", volume_id: volume_id, force: force)

        begin
          volume = volume_client.volumes.get(volume_id)
          return build_error_response("Volume not found") unless volume

          attachments = volume.attachments || []
          attachment = attachments.first

          unless attachment
            return { success: true, message: "Volume not attached" }
          end

          server = compute_client.servers.get(attachment["server_id"])
          server&.detach_volume(volume_id)

          { success: true }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def delete_volume(volume_id)
        log_operation("delete_volume", volume_id: volume_id)

        begin
          volume = volume_client.volumes.get(volume_id)
          return build_error_response("Volume not found") unless volume

          if volume.attachments&.any?
            return build_error_response("Volume is attached, detach first")
          end

          volume.destroy

          { success: true }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def get_volume(volume_id)
        log_operation("get_volume", volume_id: volume_id)

        begin
          volume = volume_client.volumes.get(volume_id)
          return build_error_response("Volume not found") unless volume

          attachment = volume.attachments&.first

          {
            success: true,
            volume_id: volume.id,
            size_gb: volume.size,
            volume_type: volume.volume_type,
            status: volume.status,
            attached_to: attachment&.dig("server_id"),
            device: attachment&.dig("device")
          }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      # ===========================================
      # Image Operations
      # ===========================================

      def create_image(instance_id, name:, description: nil)
        log_operation("create_image", instance_id: instance_id, name: name)

        begin
          server = compute_client.servers.get(instance_id)
          return build_error_response("Instance not found") unless server

          # Create snapshot image
          image_id = server.create_image(name, metadata: { description: description || "" })

          {
            success: true,
            image_id: image_id,
            status: "pending"
          }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def get_image(image_id)
        log_operation("get_image", image_id: image_id)

        begin
          image = image_client.images.get(image_id)
          return build_error_response("Image not found") unless image

          {
            success: true,
            image_id: image.id,
            name: image.name,
            description: image.metadata&.dig("description"),
            status: image.status&.downcase
          }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      def delete_image(image_id)
        log_operation("delete_image", image_id: image_id)

        begin
          image = image_client.images.get(image_id)
          return build_error_response("Image not found") unless image

          image.destroy

          { success: true }
        rescue Excon::Error => e
          handle_openstack_error(e)
        end
      end

      # ===========================================
      # Utility Methods
      # ===========================================

      def test_connection
        log_operation("test_connection")

        begin
          # Try to list flavors as a connection test
          flavors = compute_client.flavors.all

          {
            success: true,
            message: "OpenStack connection successful",
            provider: "openstack",
            endpoint: auth_url,
            available_flavors: flavors.map(&:name)
          }
        rescue Excon::Error => e
          {
            success: false,
            error: "OpenStack connection failed: #{e.message}",
            error_code: e.class.name
          }
        end
      end

      def get_metadata
        {
          provider: "openstack",
          endpoint: auth_url,
          project: project_name,
          features: %w[instances volumes ips images snapshots security_groups networks]
        }
      end

      protected

      def normalize_status(provider_status)
        OPENSTACK_STATUS_MAP[provider_status&.upcase] || "unknown"
      end

      private

      def compute_client
        @compute_client ||= Fog::OpenStack::Compute.new(fog_credentials)
      end

      def network_client
        @network_client ||= Fog::OpenStack::Network.new(fog_credentials)
      end

      def volume_client
        @volume_client ||= Fog::OpenStack::Volume.new(fog_credentials.merge(openstack_volume_v3: true))
      end

      def image_client
        @image_client ||= Fog::OpenStack::Image.new(fog_credentials.merge(openstack_image_v2: true))
      end

      def fog_credentials
        {
          openstack_auth_url: auth_url,
          openstack_username: connection.access_key,
          openstack_api_key: connection.secret_key,
          openstack_project_name: project_name,
          openstack_domain_name: domain_name,
          openstack_region: openstack_region
        }
      end

      def auth_url
        connection.endpoint_url || connection.config&.dig("auth_url") || "http://localhost:5000/v3"
      end

      def project_name
        connection.tenant || connection.config&.dig("project_name") || "admin"
      end

      def domain_name
        connection.config&.dig("domain_name") || "Default"
      end

      def openstack_region
        region&.region_code || connection.config&.dig("default_region")
      end

      def extract_private_ip(server)
        addresses = server.addresses || {}
        addresses.each do |_network, ips|
          ips.each do |ip|
            return ip["addr"] if ip["OS-EXT-IPS:type"] == "fixed" || ip["version"] == 4
          end
        end
        nil
      end

      def extract_public_ip(server)
        addresses = server.addresses || {}
        addresses.each do |_network, ips|
          ips.each do |ip|
            return ip["addr"] if ip["OS-EXT-IPS:type"] == "floating"
          end
        end
        nil
      end

      def build_server_params(params)
        server_params = {
          name: params[:name],
          image_ref: params[:image_id],
          flavor_ref: params[:instance_type]
        }

        server_params[:key_name] = params[:key_name] if params[:key_name]
        server_params[:security_groups] = Array(params[:security_groups]) if params[:security_groups]
        server_params[:nics] = [{ net_id: params[:network_id] }] if params[:network_id]
        server_params[:user_data] = Base64.encode64(params[:user_data]) if params[:user_data]
        server_params[:availability_zone] = params[:availability_zone] if params[:availability_zone]

        if params[:metadata].present?
          server_params[:metadata] = params[:metadata]
        end

        server_params
      end

      def get_external_network_id(pool_name)
        networks = network_client.networks.all
        external_network = networks.find { |n| n.name == pool_name && n.router_external }
        external_network&.id || networks.find(&:router_external)&.id
      end

      def handle_openstack_error(error)
        logger.error("[OpenStackProvider] OpenStack Error: #{error.class} - #{error.message}")

        error_message = error.message

        if error_message.include?("401") || error_message.include?("Unauthorized")
          raise AuthenticationError, "OpenStack authentication failed: #{error_message}"
        elsif error_message.include?("429") || error_message.include?("Too Many Requests")
          raise RateLimitError, "OpenStack rate limit exceeded: #{error_message}"
        elsif error_message.include?("404") || error_message.include?("Not Found")
          raise ResourceNotFoundError, error_message
        elsif error_message.include?("quota") || error_message.include?("Quota")
          raise QuotaExceededError, error_message
        else
          build_error_response(error_message)
        end
      end
    end
  end
end
