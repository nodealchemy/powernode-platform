# frozen_string_literal: true

module System
  # ImageCreateJob - Creates bootable images for instances or architectures
  #
  # Migrated from legacy powernode-agent NodeInstance.do_create_image and NodeArchitecture.do_create_image
  # This job creates IMG or ISO bootable images with proper kernel, ramdisk, and syslinux configuration.
  #
  # @example Create an IMG image for an instance
  #   System::ImageCreateJob.perform_async('instance', instance_id, operation_id, 'img')
  #
  # @example Create an image for an architecture
  #   System::ImageCreateJob.perform_async('architecture', architecture_id, operation_id, 'img')
  #
  class ImageCreateJob < BaseJob
    VALID_IMAGE_TYPES = %w[instance architecture].freeze
    VALID_IMAGE_FORMATS = %w[img iso].freeze

    sidekiq_options queue: 'system',
                    retry: 1,
                    dead: true

    # Execute image creation
    #
    # @param image_type [String] The type of image source (instance, architecture)
    # @param resource_id [String] The instance or architecture ID
    # @param operation_id [String] The operation ID for tracking
    # @param image_format [String] The output format (img, iso)
    def execute(image_type, resource_id, operation_id, image_format = 'img')
      validate_image_type!(image_type)
      validate_image_format!(image_format)

      log_info("Creating #{image_format.upcase} image",
               image_type: image_type,
               resource_id: resource_id,
               operation_id: operation_id,
               image_format: image_format)
      start_time = Time.current

      update_operation_status(operation_id, 'running')

      # Fetch resource details
      resource = fetch_resource(image_type, resource_id)
      return handle_not_found(image_type, resource_id, operation_id) unless resource

      # Execute image creation via backend
      update_operation_progress(operation_id, 10)
      result = create_image(image_type, resource, image_format, operation_id)

      if result['success']
        handle_success(operation_id, image_type, resource, image_format, result, start_time)
      else
        handle_failure(operation_id, image_type, resource, image_format, result)
      end
    rescue ArgumentError => e
      log_error('Invalid parameters', e, image_type: image_type, image_format: image_format)
      update_operation_status(operation_id, 'failed', error_message: e.message)
      raise
    rescue StandardError => e
      log_error('Image creation failed', e, resource_id: resource_id)
      update_operation_status(operation_id, 'failed', error_message: e.message)
      track_error_metric('image_create_failed', image_type: image_type)
      raise
    end

    private

    def validate_image_type!(image_type)
      return if VALID_IMAGE_TYPES.include?(image_type)

      raise ArgumentError, "Invalid image type: #{image_type}. Valid: #{VALID_IMAGE_TYPES.join(', ')}"
    end

    def validate_image_format!(image_format)
      return if VALID_IMAGE_FORMATS.include?(image_format)

      raise ArgumentError, "Invalid image format: #{image_format}. Valid: #{VALID_IMAGE_FORMATS.join(', ')}"
    end

    def fetch_resource(image_type, resource_id)
      endpoint = case image_type
                 when 'instance'
                   "/api/v1/internal/system/node_instances/#{resource_id}"
                 when 'architecture'
                   "/api/v1/internal/system/node_architectures/#{resource_id}"
                 end

      with_api_retry do
        api_client.get(endpoint)
      end
    rescue BackendApiClient::ApiError => e
      return nil if e.status == 404

      raise
    end

    def handle_not_found(image_type, resource_id, operation_id)
      error_message = "#{image_type.capitalize} not found"
      log_warn(error_message, resource_id: resource_id)
      update_operation_status(operation_id, 'failed', error_message: error_message)
      { success: false, error: error_message }
    end

    # Create bootable image via backend API
    #
    # For instances, the backend:
    # 1. Prepares image directory from architecture
    # 2. Writes identity.cfg with instance identity
    # 3. Writes node.cfg with instance configuration
    # 4. Creates syslinux.cfg with kernel options and network config
    # 5. Creates IMG/ISO using dd, mkfs, syslinux/isolinux
    # 6. Uploads the image to storage
    #
    # For architectures, the backend:
    # 1. Syncs kernel and ramdisk files
    # 2. Creates base image with syslinux
    # 3. Uploads the image to storage
    #
    # @param image_type [String] The type of image source
    # @param resource [Hash] The resource data
    # @param image_format [String] The output format
    # @param operation_id [String] The operation ID
    # @return [Hash] Creation result
    def create_image(image_type, resource, image_format, operation_id)
      resource_id = resource['id']
      resource_name = resource['name']

      log_info("Creating #{image_format.upcase} image for #{image_type}",
               resource_id: resource_id,
               resource_name: resource_name)

      endpoint = case image_type
                 when 'instance'
                   "/api/v1/internal/system/node_instances/#{resource_id}/create_image"
                 when 'architecture'
                   "/api/v1/internal/system/node_architectures/#{resource_id}/create_image"
                 end

      result = with_api_retry do
        api_client.post(endpoint, {
          image_format: image_format,
          operation_id: operation_id
        })
      end

      result
    end

    def handle_success(operation_id, image_type, resource, image_format, result, start_time)
      resource_name = resource['name']

      log_info("#{image_format.upcase} image created successfully",
               image_type: image_type,
               resource_id: resource['id'],
               resource_name: resource_name)

      add_operation_event(operation_id, :info,
                          "#{image_format.upcase} image created for #{image_type} #{resource_name}")

      update_operation_status(operation_id, 'complete')

      duration = Time.current - start_time
      track_performance_metric("system_image_#{image_format}_create_duration", duration)
      increment_counter("system_image_#{image_format}_created")

      {
        success: true,
        image_type: image_type,
        resource_id: resource['id'],
        image_format: image_format,
        duration: duration
      }
    end

    def handle_failure(operation_id, image_type, resource, image_format, result)
      resource_name = resource['name']
      error_message = result['error'] || "Failed to create #{image_format.upcase} image for #{image_type} #{resource_name}"

      log_error("Image creation failed", nil,
                image_type: image_type,
                resource_id: resource['id'],
                image_format: image_format,
                error: error_message)

      add_operation_event(operation_id, :error, error_message)

      update_operation_status(operation_id, 'failed', error_message: error_message)
      track_error_metric("image_#{image_format}_create_failed")

      { success: false, error: error_message }
    end

    def update_operation_status(operation_id, status, error_message: nil)
      return unless operation_id

      with_api_retry do
        api_client.patch("/api/v1/internal/system/operations/#{operation_id}", {
          status: status,
          error_message: error_message,
          completed_at: %w[complete failed].include?(status) ? Time.current.iso8601 : nil
        }.compact)
      end
    rescue StandardError => e
      log_warn('Failed to update operation status', operation_id: operation_id, error: e.message)
    end

    def update_operation_progress(operation_id, progress)
      return unless operation_id

      with_api_retry do
        api_client.patch("/api/v1/internal/system/operations/#{operation_id}", {
          progress: progress
        })
      end
    rescue StandardError => e
      log_warn('Failed to update operation progress', operation_id: operation_id, error: e.message)
    end

    def add_operation_event(operation_id, event_type, message)
      return unless operation_id

      with_api_retry do
        api_client.post("/api/v1/internal/system/operations/#{operation_id}/events", {
          event_type: event_type,
          message: message,
          timestamp: Time.current.iso8601
        })
      end
    rescue StandardError => e
      log_warn('Failed to add operation event', operation_id: operation_id, error: e.message)
    end
  end
end
