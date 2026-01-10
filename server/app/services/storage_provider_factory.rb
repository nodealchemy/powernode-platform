# frozen_string_literal: true

# Factory for creating storage provider instances
# Supports multiple cloud storage backends including S3, GCS, Azure, and S3-compatible providers
class StorageProviderFactory
  class UnsupportedProviderError < StandardError; end
  class ProviderNotAvailableError < StandardError; end

  # Core provider classes
  PROVIDER_CLASSES = {
    "local" => "StorageProviders::LocalStorage",
    "s3" => "StorageProviders::S3Storage",
    "gcs" => "StorageProviders::GcsStorage",
    "azure" => "StorageProviders::AzureStorage",
    # Network filesystem providers
    "nfs" => "StorageProviders::NfsStorage",
    "smb" => "StorageProviders::SmbStorage",
    # S3-compatible providers use S3Storage with custom endpoints
    "backblaze_b2" => "StorageProviders::S3Storage",
    "digitalocean_spaces" => "StorageProviders::S3Storage",
    "cloudflare_r2" => "StorageProviders::S3Storage",
    "minio" => "StorageProviders::S3Storage",
    "wasabi" => "StorageProviders::S3Storage"
  }.freeze

  # S3-compatible providers that use S3Storage with custom endpoints
  S3_COMPATIBLE_PROVIDERS = %w[backblaze_b2 digitalocean_spaces cloudflare_r2 minio wasabi].freeze

  # Network filesystem providers
  NETWORK_FS_PROVIDERS = %w[nfs smb].freeze

  # Provider display names and descriptions
  PROVIDER_INFO = {
    "local" => { name: "Local Storage", description: "Store files on the local filesystem" },
    "s3" => { name: "Amazon S3", description: "Amazon Simple Storage Service" },
    "gcs" => { name: "Google Cloud Storage", description: "Google Cloud Platform object storage" },
    "azure" => { name: "Azure Blob Storage", description: "Microsoft Azure object storage" },
    "nfs" => { name: "NFS", description: "Network File System for Unix/Linux environments" },
    "smb" => { name: "SMB/CIFS", description: "Server Message Block for Windows network shares" },
    "backblaze_b2" => { name: "Backblaze B2", description: "Cost-effective S3-compatible cloud storage" },
    "digitalocean_spaces" => { name: "DigitalOcean Spaces", description: "S3-compatible object storage" },
    "cloudflare_r2" => { name: "Cloudflare R2", description: "S3-compatible storage with zero egress fees" },
    "minio" => { name: "MinIO", description: "Self-hosted S3-compatible object storage" },
    "wasabi" => { name: "Wasabi", description: "Hot cloud storage with no egress fees" }
  }.freeze

  class << self
    # Create a storage provider instance
    # @param storage_config [FileManagement::Storage] storage configuration record
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

    # Check if provider is S3-compatible
    # @param provider_type [String] provider type
    # @return [Boolean] true if S3-compatible
    def s3_compatible?(provider_type)
      S3_COMPATIBLE_PROVIDERS.include?(provider_type.to_s.downcase)
    end

    # Check if provider is a network filesystem
    # @param provider_type [String] provider type
    # @return [Boolean] true if network filesystem
    def network_filesystem?(provider_type)
      NETWORK_FS_PROVIDERS.include?(provider_type.to_s.downcase)
    end

    # Get provider info (name and description)
    # @param provider_type [String] provider type
    # @return [Hash] provider info or nil
    def provider_info(provider_type)
      PROVIDER_INFO[provider_type.to_s.downcase]
    end

    # List providers with their info
    # @return [Array<Hash>] providers with type, name, description
    def providers_with_info
      PROVIDER_CLASSES.keys.map do |type|
        info = PROVIDER_INFO[type] || {}
        {
          type: type,
          name: info[:name] || type.titleize,
          description: info[:description] || "",
          s3_compatible: s3_compatible?(type),
          network_filesystem: network_filesystem?(type)
        }
      end
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
      normalized = provider_type.to_s.downcase

      case normalized
      when "local"
        { available: true, missing: [] }
      when "s3", *S3_COMPATIBLE_PROVIDERS
        check_s3_dependencies
      when "gcs"
        check_gcs_dependencies
      when "azure"
        check_azure_dependencies
      when "nfs"
        check_nfs_dependencies
      when "smb"
        check_smb_dependencies
      else
        { available: false, missing: [ "Unknown provider type" ] }
      end
    end

    # Get provider capabilities
    # @param provider_type [String] provider type
    # @return [Hash] provider capabilities
    def provider_capabilities(provider_type)
      normalized = provider_type.to_s.downcase

      case normalized
      when "local"
        local_capabilities
      when "s3", *S3_COMPATIBLE_PROVIDERS
        s3_capabilities
      when "gcs"
        gcs_capabilities
      when "azure"
        azure_capabilities
      when "nfs"
        nfs_capabilities
      when "smb"
        smb_capabilities
      else
        default_capabilities
      end
    end

    private

    def validate_storage_config!(storage_config)
      unless storage_config.is_a?(FileManagement::Storage)
        raise ArgumentError, "Expected FileManagement::Storage, got #{storage_config.class}"
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

    def check_gcs_dependencies
      missing = []

      begin
        require "google/cloud/storage"
      rescue LoadError
        missing << "google-cloud-storage gem"
      end

      {
        available: missing.empty?,
        missing: missing
      }
    end

    def check_azure_dependencies
      missing = []

      begin
        require "azure/storage/blob"
      rescue LoadError
        missing << "azure-storage-blob gem"
      end

      {
        available: missing.empty?,
        missing: missing
      }
    end

    def check_nfs_dependencies
      missing = []

      # NFS requires system-level mount capability
      unless system_command_available?("mount.nfs") || system_command_available?("mount")
        missing << "nfs-common package (mount.nfs command)"
      end

      {
        available: missing.empty?,
        missing: missing
      }
    end

    def check_smb_dependencies
      missing = []

      # SMB requires smbclient or mount.cifs
      unless system_command_available?("smbclient") || system_command_available?("mount.cifs")
        missing << "samba-client or cifs-utils package"
      end

      {
        available: missing.empty?,
        missing: missing
      }
    end

    def system_command_available?(command)
      system("which #{command} > /dev/null 2>&1")
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

    def gcs_capabilities
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
        "lifecycle_policies" => true,
        "object_retention" => true
      }
    end

    def azure_capabilities
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
        "lifecycle_policies" => true,
        "blob_tiers" => true
      }
    end

    def nfs_capabilities
      {
        "multipart_upload" => false,
        "resumable_upload" => false,
        "direct_upload" => false,
        "cdn" => false,
        "versioning" => false,
        "encryption" => false,
        "access_control" => true,
        "signed_urls" => false,
        "streaming" => true,
        "batch_operations" => true,
        "network_mount" => true,
        "unix_permissions" => true,
        "file_locking" => true
      }
    end

    def smb_capabilities
      {
        "multipart_upload" => false,
        "resumable_upload" => false,
        "direct_upload" => false,
        "cdn" => false,
        "versioning" => false,
        "encryption" => true,
        "access_control" => true,
        "signed_urls" => false,
        "streaming" => true,
        "batch_operations" => true,
        "network_mount" => true,
        "windows_acls" => true,
        "file_locking" => true
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
