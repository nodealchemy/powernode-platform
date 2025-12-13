# frozen_string_literal: true

require "azure/storage/blob"

module StorageProviders
  # Azure Blob Storage provider
  # Provides cloud storage with block blobs, SAS tokens, and Azure-specific features
  class AzureStorage < Base
    attr_reader :blob_client, :container_name

    def initialize(storage_config)
      super
      @container_name = config("container")
      @account_name = config("account_name")
      @blob_client = create_blob_client
    end

    # Initialize storage backend
    def initialize_storage
      begin
        @blob_client.get_container_properties(@container_name)
        log_info("Azure container exists: #{@container_name}")
      rescue Azure::Core::Http::HTTPError => e
        if e.status_code == 404
          log_info("Creating Azure container: #{@container_name}")
          @blob_client.create_container(@container_name)
        else
          raise e
        end
      end

      log_info("Initialized Azure Blob storage: #{@container_name}")
      true
    rescue Azure::Core::Http::HTTPError => e
      log_error("Failed to initialize Azure storage: #{e.message}")
      false
    end

    # Test connection
    def test_connection
      return { success: false, error: "Container name not configured" } unless @container_name

      @blob_client.get_container_properties(@container_name)

      {
        success: true,
        message: "Azure Blob storage is accessible",
        container: @container_name,
        account: @account_name
      }
    rescue Azure::Core::Http::HTTPError => e
      if e.status_code == 404
        {
          success: false,
          error: "Container does not exist: #{@container_name}"
        }
      else
        {
          success: false,
          error: "Connection test failed: #{e.message}"
        }
      end
    end

    # Health check
    def health_check
      connection_test = test_connection

      if connection_test[:success]
        {
          status: "healthy",
          details: {
            "container" => @container_name,
            "account" => @account_name,
            "accessible" => true,
            "files_count" => storage_config.files_count,
            "total_size_bytes" => storage_config.total_size_bytes,
            "checked_at" => Time.current.iso8601
          }
        }
      else
        {
          status: "failed",
          details: {
            "error" => connection_test[:error],
            "checked_at" => Time.current.iso8601
          }
        }
      end
    end

    # Upload file
    def upload_file(file_object, file_data, options = {})
      storage_key = file_object.storage_key

      # Handle IO vs String data
      if file_data.respond_to?(:read)
        file_data.rewind if file_data.respond_to?(:rewind)
        content = file_data.read
        file_data.rewind if file_data.respond_to?(:rewind)
      else
        content = file_data
      end

      # Validate file size
      validate_file_size!(content)

      # Build options
      blob_options = build_upload_options(options)

      # Upload as block blob
      @blob_client.create_block_blob(
        @container_name,
        storage_key,
        content,
        blob_options
      )

      # Calculate and store checksums
      file_object.update_columns(
        checksum_md5: calculate_checksum(content, algorithm: :md5),
        checksum_sha256: calculate_checksum(content, algorithm: :sha256)
      )

      log_info("Uploaded file to Azure: #{storage_key} (#{file_object.human_file_size})")
      true
    rescue Azure::Core::Http::HTTPError => e
      log_error("Failed to upload file #{storage_key}: #{e.message}")
      raise e
    end

    # Read file content
    def read_file(file_object)
      blob, content = @blob_client.get_blob(@container_name, file_object.storage_key)
      content
    rescue Azure::Core::Http::HTTPError => e
      if e.status_code == 404
        raise "File not found: #{file_object.storage_key}"
      end
      raise e
    end

    # Stream file content
    def stream_file(file_object, &block)
      # Azure SDK doesn't have native streaming, so we download in chunks
      blob_properties = @blob_client.get_blob_properties(@container_name, file_object.storage_key)
      blob_size = blob_properties.properties[:content_length]

      chunk_size = 4.megabytes
      offset = 0

      while offset < blob_size
        end_range = [offset + chunk_size - 1, blob_size - 1].min
        _, chunk = @blob_client.get_blob(
          @container_name,
          file_object.storage_key,
          start_range: offset,
          end_range: end_range
        )
        yield chunk
        offset = end_range + 1
      end
    rescue Azure::Core::Http::HTTPError => e
      if e.status_code == 404
        raise "File not found: #{file_object.storage_key}"
      end
      raise e
    end

    # Delete file
    def delete_file(file_object)
      @blob_client.delete_blob(@container_name, file_object.storage_key)

      log_info("Deleted file from Azure: #{file_object.storage_key}")
      true
    rescue Azure::Core::Http::HTTPError => e
      if e.status_code == 404
        # File doesn't exist, consider it a success
        return true
      end
      log_error("Failed to delete file #{file_object.storage_key}: #{e.message}")
      false
    end

    # Copy file
    def copy_file(source_key, destination_key)
      source_uri = generate_blob_uri(source_key)

      @blob_client.copy_blob_from_uri(@container_name, destination_key, source_uri)

      log_info("Copied file in Azure: #{source_key} -> #{destination_key}")
      true
    rescue Azure::Core::Http::HTTPError => e
      if e.status_code == 404
        raise "Source file not found: #{source_key}"
      end
      log_error("Failed to copy file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Move file
    def move_file(source_key, destination_key)
      if copy_file(source_key, destination_key)
        @blob_client.delete_blob(@container_name, source_key)
        log_info("Moved file in Azure: #{source_key} -> #{destination_key}")
        true
      else
        false
      end
    rescue StandardError => e
      log_error("Failed to move file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Check if file exists
    def file_exists?(file_object)
      @blob_client.get_blob_properties(@container_name, file_object.storage_key)
      true
    rescue Azure::Core::Http::HTTPError => e
      return false if e.status_code == 404

      raise e
    end

    # Get file URL
    def file_url(file_object)
      if config("cdn_domain")
        "https://#{config('cdn_domain')}/#{@container_name}/#{file_object.storage_key}"
      else
        "https://#{@account_name}.blob.core.windows.net/#{@container_name}/#{file_object.storage_key}"
      end
    end

    # Get download URL (SAS token)
    def download_url(file_object, expires_in: 1.hour)
      generate_sas_url(
        file_object.storage_key,
        expires_in: expires_in,
        permissions: "r",
        content_disposition: "attachment; filename=\"#{file_object.filename}\""
      )
    end

    # Get signed URL (SAS token)
    def signed_url(file_object, expires_in: 1.hour, disposition: "inline")
      generate_sas_url(
        file_object.storage_key,
        expires_in: expires_in,
        permissions: "r",
        content_disposition: "#{disposition}; filename=\"#{file_object.filename}\""
      )
    end

    # Get presigned upload URL
    def presigned_upload_url(storage_key, filename:, content_type:, expires_in: 15.minutes)
      generate_sas_url(
        storage_key,
        expires_in: expires_in,
        permissions: "cw", # Create and Write
        content_type: content_type
      )
    end

    # Get file metadata
    def file_metadata(file_object)
      blob_properties = @blob_client.get_blob_properties(@container_name, file_object.storage_key)
      props = blob_properties.properties

      {
        "size" => props[:content_length],
        "content_type" => props[:content_type],
        "etag" => props[:etag],
        "last_modified" => props[:last_modified]&.iso8601,
        "content_md5" => props[:content_md5],
        "blob_type" => props[:blob_type],
        "lease_status" => props[:lease_status],
        "metadata" => blob_properties.metadata
      }
    rescue Azure::Core::Http::HTTPError => e
      if e.status_code == 404
        raise "File not found: #{file_object.storage_key}"
      end
      raise e
    end

    # List files in container
    def list_files(prefix: nil, options: {})
      list_options = {}
      list_options[:prefix] = prefix if prefix
      list_options[:max_results] = options[:max_keys] || 1000

      files = []
      blobs = @blob_client.list_blobs(@container_name, list_options)

      blobs.each do |blob|
        files << {
          "key" => blob.name,
          "size" => blob.properties[:content_length],
          "modified_at" => blob.properties[:last_modified]&.iso8601,
          "content_type" => blob.properties[:content_type],
          "blob_type" => blob.properties[:blob_type]
        }
      end

      files
    rescue Azure::Core::Http::HTTPError => e
      log_error("Failed to list files: #{e.message}")
      []
    end

    # Batch delete
    def batch_delete(file_objects)
      results = { success: [], failed: [] }

      file_objects.each do |file_object|
        begin
          @blob_client.delete_blob(@container_name, file_object.storage_key)
          results[:success] << file_object.id
        rescue Azure::Core::Http::HTTPError => e
          if e.status_code == 404
            # File doesn't exist, consider it a success
            results[:success] << file_object.id
          else
            log_error("Batch delete failed for #{file_object.storage_key}: #{e.message}")
            results[:failed] << file_object.id
          end
        end
      end

      results
    end

    private

    def create_blob_client
      account_key = decrypt_config("account_key")
      connection_string = decrypt_config("connection_string")

      if connection_string
        Azure::Storage::Blob::BlobService.create_from_connection_string(connection_string)
      elsif account_key
        Azure::Storage::Blob::BlobService.create(
          storage_account_name: @account_name,
          storage_access_key: account_key
        )
      else
        raise "Azure storage credentials not configured"
      end
    end

    def build_upload_options(options)
      blob_options = {}

      blob_options[:content_type] = options[:content_type] if options[:content_type]
      blob_options[:metadata] = options[:metadata] if options[:metadata]

      # Cache control
      if config("cache_control")
        blob_options[:cache_control] = config("cache_control")
      end

      blob_options
    end

    def generate_blob_uri(storage_key)
      "https://#{@account_name}.blob.core.windows.net/#{@container_name}/#{storage_key}"
    end

    def generate_sas_url(storage_key, expires_in:, permissions:, content_disposition: nil, content_type: nil)
      account_key = decrypt_config("account_key")

      signer = Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(
        @account_name,
        account_key
      )

      expiry_time = (Time.current + expires_in).utc.iso8601

      sas_token = signer.generate_service_sas_token(
        @container_name,
        storage_key,
        service: "b",
        resource: "b",
        permissions: permissions,
        expiry: expiry_time,
        content_disposition: content_disposition,
        content_type: content_type
      )

      "#{generate_blob_uri(storage_key)}?#{sas_token}"
    end
  end
end
