# frozen_string_literal: true

module System
  module Providers
    # Abstract base class for cloud provider adapters
    # All provider implementations must inherit from this class and implement the abstract methods
    #
    # This provides a unified interface for cloud operations across AWS, GCP, Azure, OpenStack, etc.
    # Each provider normalizes responses to a common format for consistent handling.
    class BaseProvider
      class ProviderError < StandardError; end
      class NotImplementedError < ProviderError; end
      class AuthenticationError < ProviderError; end
      class RateLimitError < ProviderError; end
      class ResourceNotFoundError < ProviderError; end
      class QuotaExceededError < ProviderError; end

      # Common instance statuses (normalized across providers)
      STATUSES = {
        pending: "pending",
        starting: "starting",
        running: "running",
        stopping: "stopping",
        stopped: "stopped",
        rebooting: "rebooting",
        terminating: "terminating",
        terminated: "terminated",
        failed: "failed",
        unknown: "unknown"
      }.freeze

      attr_reader :connection, :region, :logger

      # Initialize provider with connection credentials
      #
      # @param connection [System::ProviderConnection] The provider connection with credentials
      # @param region [System::ProviderRegion, nil] Optional region override
      def initialize(connection, region: nil)
        @connection = connection
        @region = region || connection.provider_regions.first
        @logger = Rails.logger
      end

      # Provider type identifier
      #
      # @return [String] The provider type (aws, gcp, azure, openstack, mock)
      def provider_type
        raise NotImplementedError, "#{self.class} must implement #provider_type"
      end

      # ===========================================
      # Instance Lifecycle Operations
      # ===========================================

      # Create a new compute instance
      #
      # @param params [Hash] Instance creation parameters
      # @option params [String] :name Instance name
      # @option params [String] :image_id Machine image ID
      # @option params [String] :instance_type Instance type/size
      # @option params [String] :key_name SSH key name
      # @option params [Array<String>] :security_groups Security group IDs
      # @option params [String] :subnet_id Subnet ID
      # @option params [Hash] :tags Resource tags
      # @return [Hash] Normalized instance data
      def create_instance(params)
        raise NotImplementedError, "#{self.class} must implement #create_instance"
      end

      # Start a stopped instance
      #
      # @param instance_id [String] Cloud instance ID
      # @return [Hash] Result with :success, :status
      def start_instance(instance_id)
        raise NotImplementedError, "#{self.class} must implement #start_instance"
      end

      # Stop a running instance
      #
      # @param instance_id [String] Cloud instance ID
      # @param force [Boolean] Force stop without graceful shutdown
      # @return [Hash] Result with :success, :status
      def stop_instance(instance_id, force: false)
        raise NotImplementedError, "#{self.class} must implement #stop_instance"
      end

      # Reboot an instance
      #
      # @param instance_id [String] Cloud instance ID
      # @return [Hash] Result with :success, :status
      def reboot_instance(instance_id)
        raise NotImplementedError, "#{self.class} must implement #reboot_instance"
      end

      # Terminate/delete an instance
      #
      # @param instance_id [String] Cloud instance ID
      # @return [Hash] Result with :success
      def terminate_instance(instance_id)
        raise NotImplementedError, "#{self.class} must implement #terminate_instance"
      end

      # Get current instance state
      #
      # @param instance_id [String] Cloud instance ID
      # @return [Hash] Normalized instance data with current state
      def get_instance(instance_id)
        raise NotImplementedError, "#{self.class} must implement #get_instance"
      end

      # List instances with optional filters
      #
      # @param filters [Hash] Optional filters
      # @return [Array<Hash>] Array of normalized instance data
      def list_instances(filters = {})
        raise NotImplementedError, "#{self.class} must implement #list_instances"
      end

      # ===========================================
      # IP Address Operations
      # ===========================================

      # Allocate a new public/elastic IP
      #
      # @return [Hash] Result with :success, :allocation_id, :public_ip
      def allocate_ip
        raise NotImplementedError, "#{self.class} must implement #allocate_ip"
      end

      # Associate an IP with an instance
      #
      # @param instance_id [String] Cloud instance ID
      # @param allocation_id [String, nil] IP allocation ID (if pre-allocated)
      # @return [Hash] Result with :success, :public_ip, :association_id
      def associate_ip(instance_id, allocation_id: nil)
        raise NotImplementedError, "#{self.class} must implement #associate_ip"
      end

      # Disassociate an IP from an instance
      #
      # @param association_id [String] IP association ID
      # @return [Hash] Result with :success
      def disassociate_ip(association_id)
        raise NotImplementedError, "#{self.class} must implement #disassociate_ip"
      end

      # Release an allocated IP
      #
      # @param allocation_id [String] IP allocation ID
      # @return [Hash] Result with :success
      def release_ip(allocation_id)
        raise NotImplementedError, "#{self.class} must implement #release_ip"
      end

      # ===========================================
      # Volume Operations
      # ===========================================

      # Create a new storage volume
      #
      # @param params [Hash] Volume creation parameters
      # @option params [Integer] :size_gb Volume size in GB
      # @option params [String] :volume_type Volume type
      # @option params [String] :availability_zone AZ for the volume
      # @return [Hash] Result with :success, :volume_id
      def create_volume(params)
        raise NotImplementedError, "#{self.class} must implement #create_volume"
      end

      # Attach a volume to an instance
      #
      # @param volume_id [String] Cloud volume ID
      # @param instance_id [String] Cloud instance ID
      # @param device [String] Device path (e.g., /dev/sdb)
      # @return [Hash] Result with :success, :device
      def attach_volume(volume_id, instance_id, device: nil)
        raise NotImplementedError, "#{self.class} must implement #attach_volume"
      end

      # Detach a volume from an instance
      #
      # @param volume_id [String] Cloud volume ID
      # @param force [Boolean] Force detach
      # @return [Hash] Result with :success
      def detach_volume(volume_id, force: false)
        raise NotImplementedError, "#{self.class} must implement #detach_volume"
      end

      # Delete a volume
      #
      # @param volume_id [String] Cloud volume ID
      # @return [Hash] Result with :success
      def delete_volume(volume_id)
        raise NotImplementedError, "#{self.class} must implement #delete_volume"
      end

      # Get volume information
      #
      # @param volume_id [String] Cloud volume ID
      # @return [Hash] Normalized volume data
      def get_volume(volume_id)
        raise NotImplementedError, "#{self.class} must implement #get_volume"
      end

      # ===========================================
      # Image Operations
      # ===========================================

      # Create an image from an instance
      #
      # @param instance_id [String] Cloud instance ID
      # @param name [String] Image name
      # @param description [String, nil] Image description
      # @return [Hash] Result with :success, :image_id
      def create_image(instance_id, name:, description: nil)
        raise NotImplementedError, "#{self.class} must implement #create_image"
      end

      # Get image information
      #
      # @param image_id [String] Cloud image ID
      # @return [Hash] Normalized image data
      def get_image(image_id)
        raise NotImplementedError, "#{self.class} must implement #get_image"
      end

      # Delete an image
      #
      # @param image_id [String] Cloud image ID
      # @return [Hash] Result with :success
      def delete_image(image_id)
        raise NotImplementedError, "#{self.class} must implement #delete_image"
      end

      # ===========================================
      # Utility Methods
      # ===========================================

      # Test provider connection
      #
      # @return [Hash] Result with :success, :message
      def test_connection
        raise NotImplementedError, "#{self.class} must implement #test_connection"
      end

      # Get provider-specific metadata
      #
      # @return [Hash] Provider metadata (regions, instance types, etc.)
      def get_metadata
        raise NotImplementedError, "#{self.class} must implement #get_metadata"
      end

      protected

      # Normalize instance status from provider-specific to common format
      #
      # @param provider_status [String] Provider-specific status
      # @return [String] Normalized status
      def normalize_status(provider_status)
        raise NotImplementedError, "#{self.class} must implement #normalize_status"
      end

      # Build normalized instance response
      #
      # @param cloud_id [String] Cloud instance ID
      # @param status [String] Normalized status
      # @param private_ip [String, nil] Private IP address
      # @param public_ip [String, nil] Public IP address
      # @param metadata [Hash] Additional metadata
      # @return [Hash] Normalized instance data
      def build_instance_response(cloud_id:, status:, private_ip: nil, public_ip: nil, **metadata)
        {
          success: true,
          cloud_instance_id: cloud_id,
          status: status,
          private_ip_address: private_ip,
          public_ip_address: public_ip,
          provider_type: provider_type,
          synced_at: Time.current
        }.merge(metadata)
      end

      # Build error response
      #
      # @param message [String] Error message
      # @param code [String, nil] Error code
      # @return [Hash] Error response
      def build_error_response(message, code: nil)
        {
          success: false,
          error: message,
          error_code: code,
          provider_type: provider_type
        }
      end

      # Log provider operation
      #
      # @param operation [String] Operation name
      # @param details [Hash] Operation details
      def log_operation(operation, **details)
        logger.info("[#{self.class.name}] #{operation}: #{details.to_json}")
      end

      # Handle provider-specific errors and convert to common errors
      #
      # @param error [StandardError] The caught error
      # @raise [ProviderError] Converted error
      def handle_error(error)
        logger.error("[#{self.class.name}] Error: #{error.class} - #{error.message}")
        raise ProviderError, error.message
      end
    end
  end
end
