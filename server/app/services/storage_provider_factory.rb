# frozen_string_literal: true

# Factory for creating storage provider instances
# Supports local and S3 storage backends
class StorageProviderFactory
  class UnsupportedProviderError < StandardError; end
  class ProviderNotAvailableError < StandardError; end

  PROVIDER_CLASSES = {
    "local" => "StorageProviders::LocalStorage",
    "s3" => "StorageProviders::S3Storage"
  }.freeze

  class << self
    # Create a storage provider instance
    # @param storage_config [FileStorage] storage configuration record
    # @return [StorageProviders::Base] provider instance
    def create(storage_config)
      validate_storage_config!(storage_config)

      provider_class = get_provider_class(storage_config.provider_type)

      begin
        provider_class.constantize.new(storage_config)
      rescue NameError => e
        raise ProviderNotAvailableError,
              "Provider class #{provider_class} not found. #{e.message}"
      end
    end

    # Alias for create (for backward compatibility)
    alias_method :get_provider, :create

    # Check if provider type is supported
    # @param provider_type [String] provider type
    # @return [Boolean] support status
    def supported?(provider_type)
      PROVIDER_CLASSES.key?(provider_type.to_s.downcase)
    end

    # List all supported provider types
    # @return [Array<String>] provider types
    def supported_providers
      PROVIDER_CLASSES.keys
    end

    # Get provider class name
    # @param provider_type [String] provider type
    # @return [String] provider class name
    def get_provider_class(provider_type)
      normalized_type = provider_type.to_s.downcase

      unless supported?(normalized_type)
        raise UnsupportedProviderError,
              "Unsupported provider type: #{provider_type}. " \
              "Supported types: #{supported_providers.join(', ')}"
      end

      PROVIDER_CLASSES[normalized_type]
    end

    # Check if provider dependencies are available
    # @param provider_type [String] provider type
    # @return [Hash] availability status and missing dependencies
    def check_dependencies(provider_type)
      case provider_type.to_s.downcase
      when "s3"
        check_s3_dependencies
      when "local"
        { available: true, missing: [] }
      else
        { available: false, missing: [ "Unknown provider type" ] }
      end
    end

    # Get provider capabilities
    # @param provider_type [String] provider type
    # @return [Hash] provider capabilities
    def provider_capabilities(provider_type)
      case provider_type.to_s.downcase
      when "local"
        local_capabilities
      when "s3"
        s3_capabilities
      else
        default_capabilities
      end
    end

    private

    def validate_storage_config!(storage_config)
      unless storage_config.is_a?(FileStorage)
        raise ArgumentError, "Expected FileStorage, got #{storage_config.class}"
      end

      unless storage_config.provider_type.present?
        raise ArgumentError, "Provider type must be specified"
      end

      unless storage_config.configuration.is_a?(Hash)
        raise ArgumentError, "Configuration must be a Hash"
      end
    end

    def check_s3_dependencies
      missing = []

      begin
        require "aws-sdk-s3"
      rescue LoadError
        missing << "aws-sdk-s3 gem"
      end

      {
        available: missing.empty?,
        missing: missing
      }
    end

    def local_capabilities
      {
        "multipart_upload" => false,
        "resumable_upload" => false,
        "direct_upload" => false,
        "cdn" => false,
        "versioning" => true,
        "encryption" => false,
        "access_control" => true,
        "signed_urls" => false,
        "streaming" => true,
        "batch_operations" => true
      }
    end

    def s3_capabilities
      {
        "multipart_upload" => true,
        "resumable_upload" => true,
        "direct_upload" => true,
        "cdn" => true,
        "versioning" => true,
        "encryption" => true,
        "access_control" => true,
        "signed_urls" => true,
        "streaming" => true,
        "batch_operations" => true,
        "lifecycle_policies" => true
      }
    end

    def default_capabilities
      {
        "multipart_upload" => false,
        "resumable_upload" => false,
        "direct_upload" => false,
        "cdn" => false,
        "versioning" => false,
        "encryption" => false,
        "access_control" => false,
        "signed_urls" => false,
        "streaming" => false,
        "batch_operations" => false
      }
    end
  end
end
