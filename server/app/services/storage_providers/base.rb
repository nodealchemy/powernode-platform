# frozen_string_literal: true

module StorageProviders
  # Base class for all storage providers
  # Defines the interface that all storage providers must implement
  class Base
    attr_reader :storage_config

    def initialize(storage_config)
      @storage_config = storage_config
      @logger = Rails.logger
    end

    # Initialize storage backend (create directories, buckets, etc.)
    def initialize_storage
      raise NotImplementedError, "#{self.class} must implement initialize_storage"
    end

    # Test connection to storage backend
    def test_connection
      raise NotImplementedError, "#{self.class} must implement test_connection"
    end

    # Health check
    def health_check
      raise NotImplementedError, "#{self.class} must implement health_check"
    end

    # Upload file
    # @param file_object [FileObject] the file object record
    # @param file_data [IO, String] the file content
    # @param options [Hash] additional options
    # @return [Boolean] success status
    def upload_file(file_object, file_data, options = {})
      raise NotImplementedError, "#{self.class} must implement upload_file"
    end

    # Read file content
    # @param file_object [FileObject] the file object record
    # @return [String] file content
    def read_file(file_object)
      raise NotImplementedError, "#{self.class} must implement read_file"
    end

    # Stream file content (for large files)
    # @param file_object [FileObject] the file object record
    # @yield [chunk] yields chunks of file content
    def stream_file(file_object, &block)
      raise NotImplementedError, "#{self.class} must implement stream_file"
    end

    # Delete file
    # @param file_object [FileObject] the file object record
    # @return [Boolean] success status
    def delete_file(file_object)
      raise NotImplementedError, "#{self.class} must implement delete_file"
    end

    # Copy file
    # @param source_key [String] source storage key
    # @param destination_key [String] destination storage key
    # @return [Boolean] success status
    def copy_file(source_key, destination_key)
      raise NotImplementedError, "#{self.class} must implement copy_file"
    end

    # Move file
    # @param source_key [String] source storage key
    # @param destination_key [String] destination storage key
    # @return [Boolean] success status
    def move_file(source_key, destination_key)
      raise NotImplementedError, "#{self.class} must implement move_file"
    end

    # Check if file exists
    # @param file_object [FileObject] the file object record
    # @return [Boolean] existence status
    def file_exists?(file_object)
      raise NotImplementedError, "#{self.class} must implement file_exists?"
    end

    # Get file URL
    # @param file_object [FileObject] the file object record
    # @return [String] file URL
    def file_url(file_object)
      raise NotImplementedError, "#{self.class} must implement file_url"
    end

    # Get download URL (may be signed/temporary)
    # @param file_object [FileObject] the file object record
    # @param expires_in [ActiveSupport::Duration] expiration time
    # @return [String] download URL
    def download_url(file_object, expires_in: 1.hour)
      raise NotImplementedError, "#{self.class} must implement download_url"
    end

    # Get signed URL (for direct uploads/downloads)
    # @param file_object [FileObject] the file object record
    # @param expires_in [ActiveSupport::Duration] expiration time
    # @param disposition [String] content disposition (inline, attachment)
    # @return [String] signed URL
    def signed_url(file_object, expires_in: 1.hour, disposition: "inline")
      raise NotImplementedError, "#{self.class} must implement signed_url"
    end

    # Get file metadata
    # @param file_object [FileObject] the file object record
    # @return [Hash] file metadata
    def file_metadata(file_object)
      raise NotImplementedError, "#{self.class} must implement file_metadata"
    end

    # Calculate file checksum
    # @param file_data [IO, String] the file content
    # @param algorithm [Symbol] hash algorithm (:md5, :sha256)
    # @return [String] checksum
    def calculate_checksum(file_data, algorithm: :sha256)
      require "digest"

      digest_class = case algorithm
      when :md5
                       Digest::MD5
      when :sha256
                       Digest::SHA256
      else
                       raise ArgumentError, "Unsupported algorithm: #{algorithm}"
      end

      if file_data.respond_to?(:read)
        file_data.rewind if file_data.respond_to?(:rewind)
        digest = digest_class.hexdigest(file_data.read)
        file_data.rewind if file_data.respond_to?(:rewind)
        digest
      else
        digest_class.hexdigest(file_data.to_s)
      end
    end

    # List files in directory/bucket
    # @param prefix [String] directory prefix
    # @param options [Hash] additional options
    # @return [Array<Hash>] list of files
    def list_files(prefix: nil, options: {})
      raise NotImplementedError, "#{self.class} must implement list_files"
    end

    # Batch operations
    # @param file_objects [Array<FileObject>] array of file objects
    # @return [Hash] results of batch operation
    def batch_delete(file_objects)
      results = { success: [], failed: [] }

      file_objects.each do |file_object|
        if delete_file(file_object)
          results[:success] << file_object.id
        else
          results[:failed] << file_object.id
        end
      rescue StandardError => e
        log_error("Batch delete failed for file #{file_object.id}: #{e.message}")
        results[:failed] << file_object.id
      end

      results
    end

    # Get storage statistics
    # @return [Hash] storage statistics
    def storage_statistics
      {
        provider_type: storage_config.provider_type,
        files_count: storage_config.files_count,
        total_size_bytes: storage_config.total_size_bytes,
        quota_bytes: storage_config.quota_bytes,
        available_space_bytes: storage_config.available_space_bytes
      }
    end

    # ----------------------------------------------------------------------
    # Node-mount provider interface (Phase S1)
    #
    # These methods let the system extension drive per-instance, per-node
    # mounts that traverse the SDWAN with per-instance credentials. They
    # accept a plain-hash `context` from the extension to avoid any
    # upward type dependency on ::System::* classes. Providers that don't
    # support node mounts simply return false / nil.
    # ----------------------------------------------------------------------

    # Whether this provider can render a mount recipe for a remote node agent.
    # Override in concrete providers that support node mounts (NFS, SMB, S3, GCS, Azure).
    def supports_node_mount?
      false
    end

    # Compose a mount recipe for the agent to execute on a node.
    #
    # @param context [Hash] keys: :instance_id, :instance_hostname, :peer_ip,
    #   :uid, :gid, :account_id, :sdwan_network_id, :virtual_ip_address,
    #   :deployment_shape, :storage_configuration
    # @return [Hash] {type:, source:, options: [Array<String>], credential_kind:}
    def node_mount_recipe(context: {})
      return nil unless supports_node_mount?
      raise NotImplementedError, "#{self.class} must implement node_mount_recipe"
    end

    # Issue a per-instance credential the agent will use to authenticate at the
    # backend (e.g. peer_ip ACL line for NFS, Samba user/pass for SMB, STS token
    # for object storage). Materialization (writing exports.d, samba-tool, etc.)
    # is the system extension's responsibility — providers only describe.
    #
    # @return [Hash, nil] {kind:, payload:, ttl: ActiveSupport::Duration|nil,
    #   metadata: Hash} or nil if no credential needed
    def issue_node_credential(context: {})
      return nil unless supports_node_mount?
      raise NotImplementedError, "#{self.class} must implement issue_node_credential"
    end

    # Revoke a previously-issued credential. `handle` is the metadata bag the
    # provider returned at issue time. Idempotent.
    def revoke_node_credential(handle)
      true
    end

    protected

    # Get configuration value
    def config(key)
      storage_config.configuration[key.to_s]
    end

    # Decrypt sensitive configuration value
    def decrypt_config(key)
      value = config(key)
      return nil unless value

      if value.to_s.start_with?("encrypted:")
        encrypted_value = value.to_s.sub("encrypted:", "")
        Security::CredentialEncryptionService.decrypt_value(encrypted_value)
      else
        value
      end
    end

    # Log info
    def log_info(message)
      @logger.info "[#{self.class.name}] #{message}"
    end

    # Log error
    def log_error(message)
      @logger.error "[#{self.class.name}] #{message}"
    end

    # Log debug
    def log_debug(message)
      @logger.debug "[#{self.class.name}] #{message}"
    end

    # Validate file size
    def validate_file_size!(file_data, max_size = 5.gigabytes)
      file_size = if file_data.respond_to?(:size)
                    file_data.size
      elsif file_data.respond_to?(:length)
                    file_data.length
      else
                    0
      end

      if file_size > max_size
        raise ArgumentError, "File size #{file_size} bytes exceeds maximum #{max_size} bytes"
      end

      file_size
    end

    # Sanitize storage key
    def sanitize_key(key)
      # Remove leading/trailing slashes, ensure valid path
      key.to_s.gsub(%r{^/+|/+$}, "").gsub(/[^0-9A-Za-z.\-_\/]/, "_")
    end
  end
end
