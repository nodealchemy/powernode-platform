# frozen_string_literal: true

module System
  module Providers
    # AWS EC2 cloud provider adapter
    # Uses aws-sdk-ec2 for cloud operations
    class AwsProvider < BaseProvider
      # AWS-specific status mappings
      AWS_STATUS_MAP = {
        "pending" => "pending",
        "running" => "running",
        "shutting-down" => "stopping",
        "terminated" => "terminated",
        "stopping" => "stopping",
        "stopped" => "stopped"
      }.freeze

      def provider_type
        "aws"
      end

      # ===========================================
      # Instance Lifecycle Operations
      # ===========================================

      def create_instance(params)
        log_operation("create_instance", params: params.except(:user_data))

        run_params = build_run_instance_params(params)

        begin
          response = ec2_client.run_instances(run_params)
          instance = response.instances.first

          # Tag the instance with name
          if params[:name].present?
            ec2_client.create_tags(
              resources: [instance.instance_id],
              tags: [{ key: "Name", value: params[:name] }]
            )
          end

          build_instance_response(
            cloud_id: instance.instance_id,
            status: normalize_status(instance.state.name),
            private_ip: instance.private_ip_address,
            instance_type: instance.instance_type
          )
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def start_instance(instance_id)
        log_operation("start_instance", instance_id: instance_id)

        begin
          ec2_client.start_instances(instance_ids: [instance_id])

          # Get updated instance state
          instance_data = describe_instance(instance_id)
          return instance_data unless instance_data[:success]

          build_instance_response(
            cloud_id: instance_id,
            status: "starting",
            private_ip: instance_data[:private_ip_address],
            public_ip: instance_data[:public_ip_address]
          )
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def stop_instance(instance_id, force: false)
        log_operation("stop_instance", instance_id: instance_id, force: force)

        begin
          ec2_client.stop_instances(
            instance_ids: [instance_id],
            force: force
          )

          instance_data = describe_instance(instance_id)
          return instance_data unless instance_data[:success]

          build_instance_response(
            cloud_id: instance_id,
            status: "stopping",
            private_ip: instance_data[:private_ip_address]
          )
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def reboot_instance(instance_id)
        log_operation("reboot_instance", instance_id: instance_id)

        begin
          ec2_client.reboot_instances(instance_ids: [instance_id])

          instance_data = describe_instance(instance_id)
          return instance_data unless instance_data[:success]

          build_instance_response(
            cloud_id: instance_id,
            status: "rebooting",
            private_ip: instance_data[:private_ip_address],
            public_ip: instance_data[:public_ip_address]
          )
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def terminate_instance(instance_id)
        log_operation("terminate_instance", instance_id: instance_id)

        begin
          ec2_client.terminate_instances(instance_ids: [instance_id])

          build_instance_response(
            cloud_id: instance_id,
            status: "terminating"
          )
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def get_instance(instance_id)
        log_operation("get_instance", instance_id: instance_id)
        describe_instance(instance_id)
      end

      def list_instances(filters = {})
        log_operation("list_instances", filters: filters)

        begin
          ec2_filters = build_ec2_filters(filters)

          response = ec2_client.describe_instances(filters: ec2_filters)

          instances = response.reservations.flat_map(&:instances).map do |instance|
            build_instance_response(
              cloud_id: instance.instance_id,
              status: normalize_status(instance.state.name),
              private_ip: instance.private_ip_address,
              public_ip: instance.public_ip_address,
              instance_type: instance.instance_type
            )
          end

          { success: true, instances: instances }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      # ===========================================
      # IP Address Operations
      # ===========================================

      def allocate_ip
        log_operation("allocate_ip")

        begin
          response = ec2_client.allocate_address(domain: "vpc")

          {
            success: true,
            allocation_id: response.allocation_id,
            public_ip: response.public_ip
          }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
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

          response = ec2_client.associate_address(
            instance_id: instance_id,
            allocation_id: allocation_id
          )

          # Get the public IP
          address = ec2_client.describe_addresses(allocation_ids: [allocation_id]).addresses.first

          {
            success: true,
            public_ip: address&.public_ip,
            allocation_id: allocation_id,
            association_id: response.association_id
          }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def disassociate_ip(association_id)
        log_operation("disassociate_ip", association_id: association_id)

        begin
          ec2_client.disassociate_address(association_id: association_id)
          { success: true }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def release_ip(allocation_id)
        log_operation("release_ip", allocation_id: allocation_id)

        begin
          ec2_client.release_address(allocation_id: allocation_id)
          { success: true }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
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
            volume_type: params[:volume_type] || "gp3",
            availability_zone: params[:availability_zone] || default_availability_zone
          }

          volume_params[:iops] = params[:iops] if params[:iops]
          volume_params[:throughput] = params[:throughput] if params[:throughput]
          volume_params[:encrypted] = params[:encrypted] if params.key?(:encrypted)
          volume_params[:kms_key_id] = params[:kms_key_id] if params[:kms_key_id]

          response = ec2_client.create_volume(volume_params)

          {
            success: true,
            volume_id: response.volume_id,
            status: response.state
          }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def attach_volume(volume_id, instance_id, device: nil)
        log_operation("attach_volume", volume_id: volume_id, instance_id: instance_id, device: device)

        begin
          device ||= next_available_device(instance_id)

          ec2_client.attach_volume(
            volume_id: volume_id,
            instance_id: instance_id,
            device: device
          )

          {
            success: true,
            device: device,
            status: "attaching"
          }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def detach_volume(volume_id, force: false)
        log_operation("detach_volume", volume_id: volume_id, force: force)

        begin
          ec2_client.detach_volume(
            volume_id: volume_id,
            force: force
          )

          { success: true }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def delete_volume(volume_id)
        log_operation("delete_volume", volume_id: volume_id)

        begin
          ec2_client.delete_volume(volume_id: volume_id)
          { success: true }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def get_volume(volume_id)
        log_operation("get_volume", volume_id: volume_id)

        begin
          response = ec2_client.describe_volumes(volume_ids: [volume_id])
          volume = response.volumes.first

          return build_error_response("Volume not found", code: "NotFound") unless volume

          attachment = volume.attachments.first

          {
            success: true,
            volume_id: volume.volume_id,
            size_gb: volume.size,
            volume_type: volume.volume_type,
            status: volume.state,
            attached_to: attachment&.instance_id,
            device: attachment&.device
          }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      # ===========================================
      # Image Operations
      # ===========================================

      def create_image(instance_id, name:, description: nil)
        log_operation("create_image", instance_id: instance_id, name: name)

        begin
          response = ec2_client.create_image(
            instance_id: instance_id,
            name: name,
            description: description || "Created by Powernode",
            no_reboot: false
          )

          {
            success: true,
            image_id: response.image_id,
            status: "pending"
          }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def get_image(image_id)
        log_operation("get_image", image_id: image_id)

        begin
          response = ec2_client.describe_images(image_ids: [image_id])
          image = response.images.first

          return build_error_response("Image not found", code: "NotFound") unless image

          {
            success: true,
            image_id: image.image_id,
            name: image.name,
            description: image.description,
            status: image.state
          }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      def delete_image(image_id)
        log_operation("delete_image", image_id: image_id)

        begin
          ec2_client.deregister_image(image_id: image_id)
          { success: true }
        rescue Aws::EC2::Errors::ServiceError => e
          handle_aws_error(e)
        end
      end

      # ===========================================
      # Utility Methods
      # ===========================================

      def test_connection
        log_operation("test_connection")

        begin
          # Try to describe regions as a connection test
          response = ec2_client.describe_regions

          {
            success: true,
            message: "AWS connection successful",
            provider: "aws",
            region: aws_region,
            available_regions: response.regions.map(&:region_name)
          }
        rescue Aws::EC2::Errors::ServiceError => e
          {
            success: false,
            error: "AWS connection failed: #{e.message}",
            error_code: e.code
          }
        end
      end

      def get_metadata
        {
          provider: "aws",
          region: aws_region,
          features: %w[instances volumes ips images snapshots security_groups vpcs]
        }
      end

      protected

      def normalize_status(provider_status)
        AWS_STATUS_MAP[provider_status] || "unknown"
      end

      private

      def ec2_client
        @ec2_client ||= Aws::EC2::Client.new(
          region: aws_region,
          credentials: aws_credentials
        )
      end

      def aws_credentials
        Aws::Credentials.new(
          connection.access_key,
          connection.secret_key
        )
      end

      def aws_region
        region&.region_code || connection.config&.dig("default_region") || "us-east-1"
      end

      def default_availability_zone
        "#{aws_region}a"
      end

      def describe_instance(instance_id)
        response = ec2_client.describe_instances(instance_ids: [instance_id])
        instance = response.reservations.first&.instances&.first

        return build_error_response("Instance not found", code: "NotFound") unless instance

        build_instance_response(
          cloud_id: instance.instance_id,
          status: normalize_status(instance.state.name),
          private_ip: instance.private_ip_address,
          public_ip: instance.public_ip_address,
          instance_type: instance.instance_type
        )
      rescue Aws::EC2::Errors::InvalidInstanceIDNotFound
        build_error_response("Instance not found", code: "NotFound")
      end

      def build_run_instance_params(params)
        run_params = {
          image_id: params[:image_id],
          instance_type: params[:instance_type],
          min_count: 1,
          max_count: 1
        }

        run_params[:key_name] = params[:key_name] if params[:key_name]
        run_params[:security_group_ids] = Array(params[:security_groups]) if params[:security_groups]
        run_params[:subnet_id] = params[:subnet_id] if params[:subnet_id]
        run_params[:user_data] = Base64.encode64(params[:user_data]) if params[:user_data]

        if params[:tags].present?
          run_params[:tag_specifications] = [{
            resource_type: "instance",
            tags: params[:tags].map { |k, v| { key: k.to_s, value: v.to_s } }
          }]
        end

        # Block device mappings for root volume
        if params[:root_volume_size]
          run_params[:block_device_mappings] = [{
            device_name: "/dev/xvda",
            ebs: {
              volume_size: params[:root_volume_size],
              volume_type: params[:root_volume_type] || "gp3",
              delete_on_termination: true
            }
          }]
        end

        run_params
      end

      def build_ec2_filters(filters)
        ec2_filters = []

        if filters[:status]
          ec2_filters << { name: "instance-state-name", values: [filters[:status]] }
        end

        if filters[:instance_ids]
          ec2_filters << { name: "instance-id", values: Array(filters[:instance_ids]) }
        end

        if filters[:tags]
          filters[:tags].each do |key, value|
            ec2_filters << { name: "tag:#{key}", values: [value] }
          end
        end

        ec2_filters
      end

      def next_available_device(instance_id)
        # Get current block device mappings
        response = ec2_client.describe_instances(instance_ids: [instance_id])
        instance = response.reservations.first&.instances&.first

        return "/dev/sdf" unless instance

        used_devices = instance.block_device_mappings.map(&:device_name)

        # Find next available device letter
        ("f".."p").each do |letter|
          device = "/dev/sd#{letter}"
          return device unless used_devices.include?(device)
        end

        "/dev/sdp"
      end

      def handle_aws_error(error)
        logger.error("[AwsProvider] AWS Error: #{error.class} - #{error.message}")

        case error
        when Aws::EC2::Errors::UnauthorizedOperation
          raise AuthenticationError, "AWS authentication failed: #{error.message}"
        when Aws::EC2::Errors::RequestLimitExceeded
          raise RateLimitError, "AWS rate limit exceeded: #{error.message}"
        when Aws::EC2::Errors::InvalidInstanceIDNotFound,
             Aws::EC2::Errors::InvalidVolumeNotFound,
             Aws::EC2::Errors::InvalidAMIIDNotFound
          raise ResourceNotFoundError, error.message
        when Aws::EC2::Errors::InstanceLimitExceeded,
             Aws::EC2::Errors::InsufficientInstanceCapacity
          raise QuotaExceededError, error.message
        else
          build_error_response(error.message, code: error.code)
        end
      end
    end
  end
end
