# frozen_string_literal: true

require "aws-sdk-s3"

module StorageProviders
  # AWS S3 storage provider
  # Provides cloud storage with multipart uploads, signed URLs, and CDN support
  class S3Storage < Base
    attr_reader :s3_client, :bucket_name

    def initialize(storage_config)
      super
      @bucket_name = config("bucket")
      @region = config("region") || "us-east-1"
      @s3_client = create_s3_client
      @s3_resource = Aws::S3::Resource.new(client: @s3_client)
    end

    # Initialize storage backend
    def initialize_storage
      bucket = @s3_resource.bucket(@bucket_name)

      unless bucket.exists?
        log_info("Creating S3 bucket: #{@bucket_name}")
        bucket.create(create_bucket_configuration: { location_constraint: @region })
      end

      # Configure bucket settings
      configure_bucket_encryption(bucket) if config("encryption")
      configure_bucket_lifecycle(bucket) if config("lifecycle_rules")
      configure_bucket_cors(bucket) if config("enable_cors")

      log_info("Initialized S3 storage: #{@bucket_name} in #{@region}")
      true
    rescue Aws::S3::Errors::ServiceError => e
      log_error("Failed to initialize S3 storage: #{e.message}")
      false
    end

    # Test connection
    def test_connection
      return { success: false, error: "Bucket name not configured" } unless @bucket_name

      # Try to list objects (with limit 1 for performance)
      @s3_client.list_objects_v2(bucket: @bucket_name, max_keys: 1)

      {
        success: true,
        message: "S3 storage is accessible",
        bucket: @bucket_name,
        region: @region,
        endpoint: @s3_client.config.endpoint.to_s
      }
    rescue Aws::S3::Errors::NoSuchBucket
      {
        success: false,
        error: "Bucket does not exist: #{@bucket_name}"
      }
    rescue Aws::S3::Errors::ServiceError => e
      {
        success: false,
        error: "Connection test failed: #{e.message}"
      }
    end

    # Health check
    def health_check
      connection_test = test_connection

      if connection_test[:success]
        bucket_stats = get_bucket_statistics

        {
          status: "healthy",
          details: {
            "bucket" => @bucket_name,
            "region" => @region,
            "accessible" => true,
            "files_count" => storage_config.files_count,
            "total_size_bytes" => storage_config.total_size_bytes,
            "bucket_files_count" => bucket_stats[:object_count],
            "bucket_size_bytes" => bucket_stats[:total_size],
            "encryption_enabled" => bucket_stats[:encryption_enabled],
            "versioning_enabled" => bucket_stats[:versioning_enabled],
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

      # Handle IO vs String data
      if file_data.respond_to?(:read)
        file_data.rewind if file_data.respond_to?(:rewind)
        body = file_data
      else
        body = file_data
      end

      # Use multipart upload for large files
      file_size = validate_file_size!(file_data)
      if file_size > 100.megabytes
        multipart_upload(storage_key, body, upload_options)
      else
        @s3_client.put_object(
          bucket: @bucket_name,
          key: storage_key,
          body: body,
          **upload_options
        )
      end

      # Calculate and store checksums
      if file_data.respond_to?(:read)
        file_data.rewind if file_data.respond_to?(:rewind)
      end

      file_object.update_columns(
        checksum_md5: calculate_checksum(file_data, algorithm: :md5),
        checksum_sha256: calculate_checksum(file_data, algorithm: :sha256)
      )

      log_info("Uploaded file to S3: #{storage_key} (#{file_object.human_file_size})")
      true
    rescue Aws::S3::Errors::ServiceError => e
      log_error("Failed to upload file #{storage_key}: #{e.message}")
      raise e
    end

    # Read file content
    def read_file(file_object)
      response = @s3_client.get_object(
        bucket: @bucket_name,
        key: file_object.storage_key
      )

      response.body.read
    rescue Aws::S3::Errors::NoSuchKey
      raise "File not found: #{file_object.storage_key}"
    end

    # Stream file content
    def stream_file(file_object, &block)
      @s3_client.get_object(
        bucket: @bucket_name,
        key: file_object.storage_key
      ) do |chunk|
        yield chunk
      end
    rescue Aws::S3::Errors::NoSuchKey
      raise "File not found: #{file_object.storage_key}"
    end

    # Delete file
    def delete_file(file_object)
      @s3_client.delete_object(
        bucket: @bucket_name,
        key: file_object.storage_key
      )

      log_info("Deleted file from S3: #{file_object.storage_key}")
      true
    rescue Aws::S3::Errors::ServiceError => e
      log_error("Failed to delete file #{file_object.storage_key}: #{e.message}")
      false
    end

    # Copy file
    def copy_file(source_key, destination_key)
      @s3_client.copy_object(
        bucket: @bucket_name,
        copy_source: "#{@bucket_name}/#{source_key}",
        key: destination_key
      )

      log_info("Copied file in S3: #{source_key} -> #{destination_key}")
      true
    rescue Aws::S3::Errors::NoSuchKey
      raise "Source file not found: #{source_key}"
    rescue Aws::S3::Errors::ServiceError => e
      log_error("Failed to copy file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Move file
    def move_file(source_key, destination_key)
      # Copy then delete
      if copy_file(source_key, destination_key)
        @s3_client.delete_object(
          bucket: @bucket_name,
          key: source_key
        )
        log_info("Moved file in S3: #{source_key} -> #{destination_key}")
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
      @s3_client.head_object(
        bucket: @bucket_name,
        key: file_object.storage_key
      )
      true
    rescue Aws::S3::Errors::NotFound
      false
    end

    # Get file URL
    def file_url(file_object)
      if config("cdn_domain")
        "https://#{config('cdn_domain')}/#{file_object.storage_key}"
      else
        "https://#{@bucket_name}.s3.#{@region}.amazonaws.com/#{file_object.storage_key}"
      end
    end

    # Get download URL (presigned)
    def download_url(file_object, expires_in: 1.hour)
      signer = Aws::S3::Presigner.new(client: @s3_client)

      signer.presigned_url(
        :get_object,
        bucket: @bucket_name,
        key: file_object.storage_key,
        expires_in: expires_in.to_i,
        response_content_disposition: "attachment; filename=\"#{file_object.filename}\""
      )
    end

    # Get signed URL
    def signed_url(file_object, expires_in: 1.hour, disposition: "inline")
      signer = Aws::S3::Presigner.new(client: @s3_client)

      signer.presigned_url(
        :get_object,
        bucket: @bucket_name,
        key: file_object.storage_key,
        expires_in: expires_in.to_i,
        response_content_disposition: "#{disposition}; filename=\"#{file_object.filename}\""
      )
    end

    # Get presigned upload URL (for direct browser uploads)
    def presigned_upload_url(storage_key, filename:, content_type:, expires_in: 15.minutes)
      signer = Aws::S3::Presigner.new(client: @s3_client)

      signer.presigned_url(
        :put_object,
        bucket: @bucket_name,
        key: storage_key,
        expires_in: expires_in.to_i,
        content_type: content_type,
        metadata: {
          "original-filename" => filename
        }
      )
    end

    # Get file metadata
    def file_metadata(file_object)
      response = @s3_client.head_object(
        bucket: @bucket_name,
        key: file_object.storage_key
      )

      {
        "size" => response.content_length,
        "content_type" => response.content_type,
        "etag" => response.etag,
        "last_modified" => response.last_modified.iso8601,
        "storage_class" => response.storage_class,
        "server_side_encryption" => response.server_side_encryption,
        "metadata" => response.metadata,
        "version_id" => response.version_id
      }
    rescue Aws::S3::Errors::NotFound
      raise "File not found: #{file_object.storage_key}"
    end

    # List files in bucket
    def list_files(prefix: nil, options: {})
      list_options = {
        bucket: @bucket_name,
        max_keys: options[:max_keys] || 1000
      }
      list_options[:prefix] = prefix if prefix

      files = []
      @s3_client.list_objects_v2(list_options).each do |response|
        response.contents.each do |object|
          files << {
            "key" => object.key,
            "size" => object.size,
            "modified_at" => object.last_modified.iso8601,
            "etag" => object.etag,
            "storage_class" => object.storage_class
          }
        end
      end

      files
    rescue Aws::S3::Errors::ServiceError => e
      log_error("Failed to list files: #{e.message}")
      []
    end

    # Batch delete
    def batch_delete(file_objects)
      results = { success: [], failed: [] }

      # S3 supports batch delete (max 1000 objects)
      file_objects.each_slice(1000) do |batch|
        objects = batch.map { |fo| { key: fo.storage_key } }

        begin
          response = @s3_client.delete_objects(
            bucket: @bucket_name,
            delete: { objects: objects }
          )

          # Track successes
          response.deleted.each do |deleted|
            file_obj = batch.find { |fo| fo.storage_key == deleted.key }
            results[:success] << file_obj.id if file_obj
          end

          # Track failures
          response.errors.each do |error|
            file_obj = batch.find { |fo| fo.storage_key == error.key }
            results[:failed] << file_obj.id if file_obj
            log_error("Batch delete failed for #{error.key}: #{error.message}")
          end
        rescue Aws::S3::Errors::ServiceError => e
          log_error("Batch delete request failed: #{e.message}")
          batch.each { |fo| results[:failed] << fo.id }
        end
      end

      results
    end

    # Get bucket statistics
    def get_bucket_statistics
      # Note: This can be expensive for large buckets
      # Consider using CloudWatch metrics for production
      object_count = 0
      total_size = 0

      @s3_client.list_objects_v2(bucket: @bucket_name).each do |response|
        object_count += response.contents.size
        total_size += response.contents.sum(&:size)
      end

      # Check encryption
      encryption_enabled = false
      begin
        @s3_client.get_bucket_encryption(bucket: @bucket_name)
        encryption_enabled = true
      rescue Aws::S3::Errors::ServerSideEncryptionConfigurationNotFoundError
        encryption_enabled = false
      end

      # Check versioning
      versioning_response = @s3_client.get_bucket_versioning(bucket: @bucket_name)
      versioning_enabled = versioning_response.status == "Enabled"

      {
        object_count: object_count,
        total_size: total_size,
        encryption_enabled: encryption_enabled,
        versioning_enabled: versioning_enabled
      }
    rescue Aws::S3::Errors::ServiceError => e
      log_error("Failed to get bucket statistics: #{e.message}")
      {
        object_count: 0,
        total_size: 0,
        encryption_enabled: false,
        versioning_enabled: false
      }
    end

    private

    def create_s3_client
      client_options = {
        region: @region,
        credentials: create_credentials
      }

      # Support for S3-compatible services (Minio, DigitalOcean Spaces, etc.)
      if config("endpoint")
        client_options[:endpoint] = config("endpoint")
        client_options[:force_path_style] = config("force_path_style") || true
      end

      Aws::S3::Client.new(client_options)
    end

    def create_credentials
      access_key_id = decrypt_config("access_key_id")
      secret_access_key = decrypt_config("secret_access_key")

      if access_key_id && secret_access_key
        Aws::Credentials.new(access_key_id, secret_access_key)
      else
        # Use IAM role or environment credentials
        Aws::InstanceProfileCredentials.new
      end
    end

    def build_upload_options(options)
      upload_opts = {}

      # Content type
      upload_opts[:content_type] = options[:content_type] if options[:content_type]

      # Server-side encryption
      if config("encryption")
        upload_opts[:server_side_encryption] = config("encryption")
        upload_opts[:ssekms_key_id] = config("kms_key_id") if config("kms_key_id")
      end

      # Storage class
      if config("storage_class")
        upload_opts[:storage_class] = config("storage_class")
      end

      # ACL
      if config("acl")
        upload_opts[:acl] = config("acl")
      end

      # Metadata
      if options[:metadata]
        upload_opts[:metadata] = options[:metadata]
      end

      # Cache control
      if config("cache_control")
        upload_opts[:cache_control] = config("cache_control")
      end

      upload_opts
    end

    def multipart_upload(storage_key, body, options)
      # Initiate multipart upload
      response = @s3_client.create_multipart_upload(
        bucket: @bucket_name,
        key: storage_key,
        **options
      )

      upload_id = response.upload_id
      parts = []
      part_number = 1
      chunk_size = 100.megabytes

      begin
        # Upload parts
        loop do
          chunk = body.read(chunk_size)
          break if chunk.nil? || chunk.empty?

          part_response = @s3_client.upload_part(
            bucket: @bucket_name,
            key: storage_key,
            upload_id: upload_id,
            part_number: part_number,
            body: chunk
          )

          parts << { etag: part_response.etag, part_number: part_number }
          part_number += 1
        end

        # Complete multipart upload
        @s3_client.complete_multipart_upload(
          bucket: @bucket_name,
          key: storage_key,
          upload_id: upload_id,
          multipart_upload: { parts: parts }
        )

        log_info("Completed multipart upload: #{storage_key} (#{parts.size} parts)")
      rescue StandardError => e
        # Abort multipart upload on failure
        @s3_client.abort_multipart_upload(
          bucket: @bucket_name,
          key: storage_key,
          upload_id: upload_id
        )
        raise e
      end
    end

    def configure_bucket_encryption(bucket)
      encryption_config = config("encryption")

      bucket.encryption.put(
        server_side_encryption_configuration: {
          rules: [
            {
              apply_server_side_encryption_by_default: {
                sse_algorithm: encryption_config,
                kms_master_key_id: config("kms_key_id")
              }.compact
            }
          ]
        }
      )

      log_info("Configured bucket encryption: #{encryption_config}")
    rescue Aws::S3::Errors::ServiceError => e
      log_error("Failed to configure bucket encryption: #{e.message}")
    end

    def configure_bucket_lifecycle(bucket)
      lifecycle_rules = config("lifecycle_rules")

      bucket.lifecycle_configuration.put(
        lifecycle_configuration: {
          rules: lifecycle_rules
        }
      )

      log_info("Configured bucket lifecycle rules")
    rescue Aws::S3::Errors::ServiceError => e
      log_error("Failed to configure bucket lifecycle: #{e.message}")
    end

    def configure_bucket_cors(bucket)
      cors_config = {
        cors_rules: [
          {
            allowed_headers: [ "*" ],
            allowed_methods: [ "GET", "PUT", "POST", "DELETE" ],
            allowed_origins: config("cors_origins") || [ "*" ],
            max_age_seconds: 3600
          }
        ]
      }

      bucket.cors.put(cors_configuration: cors_config)

      log_info("Configured bucket CORS")
    rescue Aws::S3::Errors::ServiceError => e
      log_error("Failed to configure bucket CORS: #{e.message}")
    end
  end
end
