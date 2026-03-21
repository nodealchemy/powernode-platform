# frozen_string_literal: true

module System
  module Providers
    # Mock cloud provider for testing and development
    # Simulates cloud operations without making actual API calls
    class MockProvider < BaseProvider
      # In-memory storage for mock resources
      @@instances = {}
      @@volumes = {}
      @@ips = {}
      @@images = {}

      def provider_type
        "mock"
      end

      # ===========================================
      # Instance Lifecycle Operations
      # ===========================================

      def create_instance(params)
        log_operation("create_instance", params: params)

        instance_id = "mock-#{SecureRandom.hex(8)}"
        private_ip = generate_private_ip

        instance_data = {
          id: instance_id,
          name: params[:name],
          status: "pending",
          private_ip: private_ip,
          public_ip: nil,
          instance_type: params[:instance_type],
          image_id: params[:image_id],
          created_at: Time.current
        }

        @@instances[instance_id] = instance_data

        # Simulate async startup
        Thread.new do
          sleep(0.5)
          @@instances[instance_id][:status] = "running" if @@instances[instance_id]
        end

        build_instance_response(
          cloud_id: instance_id,
          status: "pending",
          private_ip: private_ip,
          instance_type: params[:instance_type]
        )
      end

      def start_instance(instance_id)
        log_operation("start_instance", instance_id: instance_id)

        instance = @@instances[instance_id]
        return build_error_response("Instance not found") unless instance

        if instance[:status] == "running"
          return build_instance_response(
            cloud_id: instance_id,
            status: "running",
            private_ip: instance[:private_ip],
            public_ip: instance[:public_ip],
            message: "Instance already running"
          )
        end

        instance[:status] = "starting"

        Thread.new do
          sleep(0.3)
          @@instances[instance_id][:status] = "running" if @@instances[instance_id]
        end

        build_instance_response(
          cloud_id: instance_id,
          status: "starting",
          private_ip: instance[:private_ip],
          public_ip: instance[:public_ip]
        )
      end

      def stop_instance(instance_id, force: false)
        log_operation("stop_instance", instance_id: instance_id, force: force)

        instance = @@instances[instance_id]
        return build_error_response("Instance not found") unless instance

        if instance[:status] == "stopped"
          return build_instance_response(
            cloud_id: instance_id,
            status: "stopped",
            private_ip: instance[:private_ip],
            message: "Instance already stopped"
          )
        end

        instance[:status] = "stopping"

        Thread.new do
          sleep(force ? 0.1 : 0.5)
          @@instances[instance_id][:status] = "stopped" if @@instances[instance_id]
        end

        build_instance_response(
          cloud_id: instance_id,
          status: "stopping",
          private_ip: instance[:private_ip]
        )
      end

      def reboot_instance(instance_id)
        log_operation("reboot_instance", instance_id: instance_id)

        instance = @@instances[instance_id]
        return build_error_response("Instance not found") unless instance

        instance[:status] = "rebooting"

        Thread.new do
          sleep(0.5)
          @@instances[instance_id][:status] = "running" if @@instances[instance_id]
        end

        build_instance_response(
          cloud_id: instance_id,
          status: "rebooting",
          private_ip: instance[:private_ip],
          public_ip: instance[:public_ip]
        )
      end

      def terminate_instance(instance_id)
        log_operation("terminate_instance", instance_id: instance_id)

        instance = @@instances[instance_id]
        return build_error_response("Instance not found") unless instance

        instance[:status] = "terminating"

        Thread.new do
          sleep(0.3)
          if @@instances[instance_id]
            @@instances[instance_id][:status] = "terminated"
            # Clean up after a delay
            sleep(1)
            @@instances.delete(instance_id)
          end
        end

        build_instance_response(
          cloud_id: instance_id,
          status: "terminating"
        )
      end

      def get_instance(instance_id)
        log_operation("get_instance", instance_id: instance_id)

        instance = @@instances[instance_id]
        return build_error_response("Instance not found", code: "NotFound") unless instance

        build_instance_response(
          cloud_id: instance_id,
          status: instance[:status],
          private_ip: instance[:private_ip],
          public_ip: instance[:public_ip],
          instance_type: instance[:instance_type]
        )
      end

      def list_instances(filters = {})
        log_operation("list_instances", filters: filters)

        instances = @@instances.values

        # Apply filters
        if filters[:status]
          instances = instances.select { |i| i[:status] == filters[:status] }
        end

        {
          success: true,
          instances: instances.map do |instance|
            build_instance_response(
              cloud_id: instance[:id],
              status: instance[:status],
              private_ip: instance[:private_ip],
              public_ip: instance[:public_ip]
            )
          end
        }
      end

      # ===========================================
      # IP Address Operations
      # ===========================================

      def allocate_ip
        log_operation("allocate_ip")

        allocation_id = "eipalloc-mock-#{SecureRandom.hex(4)}"
        public_ip = generate_public_ip

        @@ips[allocation_id] = {
          id: allocation_id,
          public_ip: public_ip,
          associated: false,
          instance_id: nil,
          association_id: nil
        }

        {
          success: true,
          allocation_id: allocation_id,
          public_ip: public_ip
        }
      end

      def associate_ip(instance_id, allocation_id: nil)
        log_operation("associate_ip", instance_id: instance_id, allocation_id: allocation_id)

        instance = @@instances[instance_id]
        return build_error_response("Instance not found") unless instance

        # Allocate new IP if not provided
        unless allocation_id
          result = allocate_ip
          return result unless result[:success]
          allocation_id = result[:allocation_id]
        end

        ip_data = @@ips[allocation_id]
        return build_error_response("IP allocation not found") unless ip_data

        association_id = "eipassoc-mock-#{SecureRandom.hex(4)}"

        ip_data[:associated] = true
        ip_data[:instance_id] = instance_id
        ip_data[:association_id] = association_id

        instance[:public_ip] = ip_data[:public_ip]

        {
          success: true,
          public_ip: ip_data[:public_ip],
          allocation_id: allocation_id,
          association_id: association_id
        }
      end

      def disassociate_ip(association_id)
        log_operation("disassociate_ip", association_id: association_id)

        ip_data = @@ips.values.find { |ip| ip[:association_id] == association_id }
        return build_error_response("Association not found") unless ip_data

        if ip_data[:instance_id] && @@instances[ip_data[:instance_id]]
          @@instances[ip_data[:instance_id]][:public_ip] = nil
        end

        ip_data[:associated] = false
        ip_data[:instance_id] = nil
        ip_data[:association_id] = nil

        { success: true }
      end

      def release_ip(allocation_id)
        log_operation("release_ip", allocation_id: allocation_id)

        ip_data = @@ips[allocation_id]
        return build_error_response("IP allocation not found") unless ip_data

        if ip_data[:associated]
          return build_error_response("IP is still associated, disassociate first")
        end

        @@ips.delete(allocation_id)

        { success: true }
      end

      # ===========================================
      # Volume Operations
      # ===========================================

      def create_volume(params)
        log_operation("create_volume", params: params)

        volume_id = "vol-mock-#{SecureRandom.hex(8)}"

        @@volumes[volume_id] = {
          id: volume_id,
          size_gb: params[:size_gb],
          volume_type: params[:volume_type] || "standard",
          status: "available",
          attached_to: nil,
          device: nil,
          created_at: Time.current
        }

        {
          success: true,
          volume_id: volume_id,
          status: "available"
        }
      end

      def attach_volume(volume_id, instance_id, device: nil)
        log_operation("attach_volume", volume_id: volume_id, instance_id: instance_id, device: device)

        volume = @@volumes[volume_id]
        return build_error_response("Volume not found") unless volume

        instance = @@instances[instance_id]
        return build_error_response("Instance not found") unless instance

        if volume[:attached_to]
          return build_error_response("Volume already attached")
        end

        device ||= next_available_device(instance_id)

        volume[:status] = "attached"
        volume[:attached_to] = instance_id
        volume[:device] = device

        {
          success: true,
          device: device,
          status: "attached"
        }
      end

      def detach_volume(volume_id, force: false)
        log_operation("detach_volume", volume_id: volume_id, force: force)

        volume = @@volumes[volume_id]
        return build_error_response("Volume not found") unless volume

        unless volume[:attached_to]
          return { success: true, message: "Volume not attached" }
        end

        volume[:status] = "available"
        volume[:attached_to] = nil
        volume[:device] = nil

        { success: true }
      end

      def delete_volume(volume_id)
        log_operation("delete_volume", volume_id: volume_id)

        volume = @@volumes[volume_id]
        return build_error_response("Volume not found") unless volume

        if volume[:attached_to]
          return build_error_response("Volume is attached, detach first")
        end

        @@volumes.delete(volume_id)

        { success: true }
      end

      def get_volume(volume_id)
        log_operation("get_volume", volume_id: volume_id)

        volume = @@volumes[volume_id]
        return build_error_response("Volume not found") unless volume

        {
          success: true,
          volume_id: volume_id,
          size_gb: volume[:size_gb],
          volume_type: volume[:volume_type],
          status: volume[:status],
          attached_to: volume[:attached_to],
          device: volume[:device]
        }
      end

      # ===========================================
      # Image Operations
      # ===========================================

      def create_image(instance_id, name:, description: nil)
        log_operation("create_image", instance_id: instance_id, name: name)

        instance = @@instances[instance_id]
        return build_error_response("Instance not found") unless instance

        image_id = "ami-mock-#{SecureRandom.hex(8)}"

        @@images[image_id] = {
          id: image_id,
          name: name,
          description: description,
          source_instance: instance_id,
          status: "pending",
          created_at: Time.current
        }

        Thread.new do
          sleep(1)
          @@images[image_id][:status] = "available" if @@images[image_id]
        end

        {
          success: true,
          image_id: image_id,
          status: "pending"
        }
      end

      def get_image(image_id)
        log_operation("get_image", image_id: image_id)

        image = @@images[image_id]
        return build_error_response("Image not found") unless image

        {
          success: true,
          image_id: image_id,
          name: image[:name],
          description: image[:description],
          status: image[:status]
        }
      end

      def delete_image(image_id)
        log_operation("delete_image", image_id: image_id)

        image = @@images[image_id]
        return build_error_response("Image not found") unless image

        @@images.delete(image_id)

        { success: true }
      end

      # ===========================================
      # Utility Methods
      # ===========================================

      def test_connection
        log_operation("test_connection")

        {
          success: true,
          message: "Mock provider connection successful",
          provider: "mock",
          features: %w[instances volumes ips images]
        }
      end

      def get_metadata
        {
          provider: "mock",
          regions: ["mock-region-1", "mock-region-2"],
          instance_types: ["mock.small", "mock.medium", "mock.large"],
          volume_types: ["standard", "ssd", "fast-ssd"]
        }
      end

      # ===========================================
      # Test Helpers (for specs)
      # ===========================================

      def self.reset!
        @@instances = {}
        @@volumes = {}
        @@ips = {}
        @@images = {}
      end

      def self.instances
        @@instances
      end

      def self.volumes
        @@volumes
      end

      def self.ips
        @@ips
      end

      def self.images
        @@images
      end

      protected

      def normalize_status(provider_status)
        # Mock provider uses standard statuses
        provider_status
      end

      private

      def generate_private_ip
        "172.16.#{rand(0..255)}.#{rand(1..254)}"
      end

      def generate_public_ip
        "203.0.113.#{rand(1..254)}" # TEST-NET-3 range
      end

      def next_available_device(instance_id)
        # Get all attached volumes for this instance
        attached_devices = @@volumes.values
                                    .select { |v| v[:attached_to] == instance_id }
                                    .map { |v| v[:device] }

        # Find next available device letter
        ("b".."z").each do |letter|
          device = "/dev/sd#{letter}"
          return device unless attached_devices.include?(device)
        end

        "/dev/sdz"
      end
    end
  end
end
