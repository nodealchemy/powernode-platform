# frozen_string_literal: true

require "google/cloud/storage"

module StorageProviders
  # Google Cloud Storage provider
  # Provides cloud storage with resumable uploads, signed URLs, and GCS-specific features
  class GcsStorage < Base
    attr_reader :gcs_client, :bucket_name

    def initialize(storage_config)
      super
      @bucket_name = config("bucket")
      @project_id = config("project_id")
      @gcs_client = create_gcs_client
    end

    # Initialize storage backend
    def initialize_storage
      bucket = @gcs_client.bucket(@bucket_name)

      unless bucket
        log_info("Creating GCS bucket: #{@bucket_name}")
        bucket = @gcs_client.create_bucket(@bucket_name, location: config("location") || "US")
      end

      # Configure bucket settings
      configure_bucket_lifecycle(bucket) if config("lifecycle_rules")
      configure_bucket_cors(bucket) if config("enable_cors")

      log_info("Initialized GCS storage: #{@bucket_name}")
      true
    rescue Google::Cloud::Error => e
      log_error("Failed to initialize GCS storage: #{e.message}")
      false
    end

    # Test connection
    def test_connection
      return { success: false, error: "Bucket name not configured" } unless @bucket_name

      bucket = @gcs_client.bucket(@bucket_name)

      if bucket
        {
          success: true,
          message: "GCS storage is accessible",
          bucket: @bucket_name,
          location: bucket.location,
          storage_class: bucket.storage_class
        }
      else
        {
          success: false,
          error: "Bucket does not exist: #{@bucket_name}"
        }
      end
    rescue Google::Cloud::Error => e
      {
        success: false,
        error: "Connection test failed: #{e.message}"
      }
    end

    # Health check
    def health_check
      connection_test = test_connection

      if connection_test[:success]
        bucket = @gcs_client.bucket(@bucket_name)

        {
          status: "healthy",
          details: {
            "bucket" => @bucket_name,
            "location" => bucket&.location,
            "storage_class" => bucket&.storage_class,
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
      upload_options = build_upload_options(options)

      bucket = @gcs_client.bucket(@bucket_name)

      # Handle IO vs String data
      if file_data.respond_to?(:read)
        file_data.rewind if file_data.respond_to?(:rewind)
      end

      # Validate file size
      validate_file_size!(file_data)

      # Upload file
      gcs_file = bucket.create_file(
        file_data,
        storage_key,
        **upload_options
      )

      # Calculate and store checksums
      if file_data.respond_to?(:read)
        file_data.rewind if file_data.respond_to?(:rewind)
      end

      file_object.update_columns(
        checksum_md5: calculate_checksum(file_data, algorithm: :md5),
        checksum_sha256: calculate_checksum(file_data, algorithm: :sha256)
      )

      log_info("Uploaded file to GCS: #{storage_key} (#{file_object.human_file_size})")
      true
    rescue Google::Cloud::Error => e
      log_error("Failed to upload file #{storage_key}: #{e.message}")
      raise e
    end

    # Read file content
    def read_file(file_object)
      bucket = @gcs_client.bucket(@bucket_name)
      gcs_file = bucket.file(file_object.storage_key)

      raise "File not found: #{file_object.storage_key}" unless gcs_file

      gcs_file.download.read
    end

    # Stream file content
    def stream_file(file_object, &block)
      bucket = @gcs_client.bucket(@bucket_name)
      gcs_file = bucket.file(file_object.storage_key)

      raise "File not found: #{file_object.storage_key}" unless gcs_file

      gcs_file.download do |chunk|
        yield chunk
      end
    end

    # Delete file
    def delete_file(file_object)
      bucket = @gcs_client.bucket(@bucket_name)
      gcs_file = bucket.file(file_object.storage_key)

      return true unless gcs_file

      gcs_file.delete

      log_info("Deleted file from GCS: #{file_object.storage_key}")
      true
    rescue Google::Cloud::Error => e
      log_error("Failed to delete file #{file_object.storage_key}: #{e.message}")
      false
    end

    # Copy file
    def copy_file(source_key, destination_key)
      bucket = @gcs_client.bucket(@bucket_name)
      source_file = bucket.file(source_key)

      raise "Source file not found: #{source_key}" unless source_file

      source_file.copy(destination_key)

      log_info("Copied file in GCS: #{source_key} -> #{destination_key}")
      true
    rescue Google::Cloud::Error => e
      log_error("Failed to copy file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Move file
    def move_file(source_key, destination_key)
      if copy_file(source_key, destination_key)
        bucket = @gcs_client.bucket(@bucket_name)
        source_file = bucket.file(source_key)
        source_file&.delete

        log_info("Moved file in GCS: #{source_key} -> #{destination_key}")
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
      bucket = @gcs_client.bucket(@bucket_name)
      gcs_file = bucket.file(file_object.storage_key)
      !gcs_file.nil?
    end

    # Get file URL
    def file_url(file_object)
      if config("cdn_domain")
        "https://#{config('cdn_domain')}/#{file_object.storage_key}"
      else
        "https://storage.googleapis.com/#{@bucket_name}/#{file_object.storage_key}"
      end
    end

    # Get download URL (signed)
    def download_url(file_object, expires_in: 1.hour)
      bucket = @gcs_client.bucket(@bucket_name)
      gcs_file = bucket.file(file_object.storage_key)

      raise "File not found: #{file_object.storage_key}" unless gcs_file

      gcs_file.signed_url(
        method: "GET",
        expires: expires_in.to_i,
        query: { "response-content-disposition" => "attachment; filename=\"#{file_object.filename}\"" }
      )
    end

    # Get signed URL
    def signed_url(file_object, expires_in: 1.hour, disposition: "inline")
      bucket = @gcs_client.bucket(@bucket_name)
      gcs_file = bucket.file(file_object.storage_key)

      raise "File not found: #{file_object.storage_key}" unless gcs_file

      gcs_file.signed_url(
        method: "GET",
        expires: expires_in.to_i,
        query: { "response-content-disposition" => "#{disposition}; filename=\"#{file_object.filename}\"" }
      )
    end

    # Get presigned upload URL
    def presigned_upload_url(storage_key, filename:, content_type:, expires_in: 15.minutes)
      bucket = @gcs_client.bucket(@bucket_name)

      bucket.signed_url(
        storage_key,
        method: "PUT",
        expires: expires_in.to_i,
        content_type: content_type,
        headers: {
          "x-goog-meta-original-filename" => filename
        }
      )
    end

    # Get file metadata
    def file_metadata(file_object)
      bucket = @gcs_client.bucket(@bucket_name)
      gcs_file = bucket.file(file_object.storage_key)

      raise "File not found: #{file_object.storage_key}" unless gcs_file

      {
        "size" => gcs_file.size,
        "content_type" => gcs_file.content_type,
        "md5" => gcs_file.md5,
        "crc32c" => gcs_file.crc32c,
        "created_at" => gcs_file.created_at&.iso8601,
        "updated_at" => gcs_file.updated_at&.iso8601,
        "storage_class" => gcs_file.storage_class,
        "generation" => gcs_file.generation,
        "metadata" => gcs_file.metadata
      }
    end

    # List files in bucket
    def list_files(prefix: nil, options: {})
      bucket = @gcs_client.bucket(@bucket_name)
      list_options = {}
      list_options[:prefix] = prefix if prefix
      list_options[:max] = options[:max_keys] || 1000

      files = []
      bucket.files(**list_options).each do |gcs_file|
        files << {
          "key" => gcs_file.name,
          "size" => gcs_file.size,
          "modified_at" => gcs_file.updated_at&.iso8601,
          "content_type" => gcs_file.content_type,
          "storage_class" => gcs_file.storage_class
        }
      end

      files
    rescue Google::Cloud::Error => e
      log_error("Failed to list files: #{e.message}")
      []
    end

    # Batch delete
    def batch_delete(file_objects)
      results = { success: [], failed: [] }
      bucket = @gcs_client.bucket(@bucket_name)

      file_objects.each do |file_object|
        begin
          gcs_file = bucket.file(file_object.storage_key)
          if gcs_file
            gcs_file.delete
            results[:success] << file_object.id
          else
            # File doesn't exist, consider it a success
            results[:success] << file_object.id
          end
        rescue Google::Cloud::Error => e
          log_error("Batch delete failed for #{file_object.storage_key}: #{e.message}")
          results[:failed] << file_object.id
        end
      end

      results
    end

    private

    def create_gcs_client
      credentials = build_credentials

      Google::Cloud::Storage.new(
        project_id: @project_id,
        credentials: credentials
      )
    end

    def build_credentials
      # Try service account JSON first
      service_account_json = decrypt_config("service_account_json")
      if service_account_json
        return JSON.parse(service_account_json)
      end

      # Try service account file path
      credentials_path = config("credentials_path")
      if credentials_path && File.exist?(credentials_path)
        return credentials_path
      end

      # Fall back to application default credentials
      nil
    end

    def build_upload_options(options)
      upload_opts = {}

      upload_opts[:content_type] = options[:content_type] if options[:content_type]
      upload_opts[:cache_control] = config("cache_control") if config("cache_control")
      upload_opts[:metadata] = options[:metadata] if options[:metadata]

      # Storage class
      if config("storage_class")
        upload_opts[:storage_class] = config("storage_class")
      end

      # Encryption
      if config("encryption_key")
        upload_opts[:encryption_key] = decrypt_config("encryption_key")
      end

      upload_opts
    end

    def configure_bucket_lifecycle(bucket)
      lifecycle_rules = config("lifecycle_rules")
      return unless lifecycle_rules

      bucket.lifecycle do |l|
        lifecycle_rules.each do |rule|
          l.add_delete_rule(
            age: rule["age"],
            storage_class: rule["storage_class"],
            is_live: rule["is_live"]
          )
        end
      end

      log_info("Configured bucket lifecycle rules")
    rescue Google::Cloud::Error => e
      log_error("Failed to configure bucket lifecycle: #{e.message}")
    end

    def configure_bucket_cors(bucket)
      cors_config = config("cors_config") || {
        "origin" => ["*"],
        "method" => ["GET", "PUT", "POST", "DELETE"],
        "response_header" => ["Content-Type"],
        "max_age_seconds" => 3600
      }

      bucket.cors do |c|
        c.add_rule(
          cors_config["origin"],
          cors_config["method"],
          headers: cors_config["response_header"],
          max_age: cors_config["max_age_seconds"]
        )
      end

      log_info("Configured bucket CORS")
    rescue Google::Cloud::Error => e
      log_error("Failed to configure bucket CORS: #{e.message}")
    end
  end
end
