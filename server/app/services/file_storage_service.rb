# frozen_string_literal: true

# Main service for file storage operations
# Provides a unified interface for file management across all storage providers
class FileStorageService
  class QuotaExceededError < StandardError; end
  class StorageNotFoundError < StandardError; end
  class FileNotFoundError < StandardError; end
  class InvalidFileError < StandardError; end

  attr_reader :account, :storage_config, :provider

  def initialize(account, storage_config: nil)
    @account = account
    @storage_config = storage_config || account.file_storages.default.first
    raise StorageNotFoundError, "No storage configuration found" unless @storage_config

    @provider = @storage_config.storage_provider
    @logger = Rails.logger
  end

  # Upload a file
  # @param uploaded_file [ActionDispatch::Http::UploadedFile, IO, String] file to upload
  # @param filename [String] original filename
  # @param content_type [String] MIME type
  # @param options [Hash] additional options
  # @return [FileManagement::Object] created file object
  def upload_file(uploaded_file, filename:, content_type: nil, **options)
    # Validate file
    validate_file!(uploaded_file, filename)

    # Check quota
    file_size = get_file_size(uploaded_file)
    check_quota!(file_size)

    # Generate storage key
    storage_key = generate_storage_key(filename, options[:category])

    # Create file object
    file_object = FileManagement::Object.create!(
      account: account,
      storage: storage_config,
      filename: filename,
      content_type: content_type || detect_content_type(uploaded_file, filename),
      file_size: file_size,
      storage_key: storage_key,
      visibility: options[:visibility] || "private",
      category: options[:category],
      metadata: options[:metadata] || {},
      attachable: options[:attachable],
      uploaded_by_id: options[:uploaded_by_id]
    )

    # Upload to storage provider
    begin
      provider.upload_file(file_object, uploaded_file, options)

      # Update storage statistics
      storage_config.add_file_size(file_size)

      # Queue processing job if needed
      queue_processing_jobs(file_object, options[:processing_tasks] || [])

      log_info("File uploaded successfully: #{filename} (#{file_object.id})")
      file_object
    rescue StandardError => e
      # Cleanup on failure
      file_object.destroy
      raise e
    end
  end

  # Download file content
  # @param file_object [FileManagement::Object] file to download
  # @return [String] file content
  def download_file(file_object)
    validate_file_access!(file_object)
    provider.read_file(file_object)
  end

  # Stream file content (for large files)
  # @param file_object [FileManagement::Object] file to stream
  # @yield [chunk] yields chunks of file content
  def stream_file(file_object, &block)
    validate_file_access!(file_object)
    provider.stream_file(file_object, &block)
  end

  # Delete file
  # @param file_object [FileManagement::Object] file to delete
  # @param permanent [Boolean] permanently delete or soft delete
  # @param deleted_by_user [User] user performing deletion (required for soft delete)
  # @return [Boolean] success status
  def delete_file(file_object, permanent: false, deleted_by_user: nil)
    validate_file_access!(file_object)

    if permanent
      # Delete from storage provider
      if provider.delete_file(file_object)
        # Update storage statistics
        storage_config.remove_file_size(file_object.file_size)

        # Delete file object
        file_object.destroy!
        log_info("File permanently deleted: #{file_object.filename} (#{file_object.id})")
        true
      else
        false
      end
    else
      # Soft delete
      file_object.soft_delete!(deleted_by_user)
      log_info("File soft deleted: #{file_object.filename} (#{file_object.id})")
      true
    end
  end

  # Restore soft-deleted file
  # @param file_object [FileManagement::Object] file to restore
  # @return [Boolean] success status
  def restore_file(file_object)
    validate_file_access!(file_object)

    if file_object.deleted? && provider.file_exists?(file_object)
      file_object.restore!
      log_info("File restored: #{file_object.filename} (#{file_object.id})")
      true
    else
      false
    end
  end

  # Create new file version
  # @param file_object [FileManagement::Object] original file
  # @param uploaded_file [IO] new version content
  # @param created_by_user [User] user creating version
  # @param change_description [String] description of changes
  # @return [FileManagement::Object] new version file object
  def create_version(file_object, uploaded_file, created_by_user:, change_description: nil)
    validate_file_access!(file_object)

    file_object.create_new_version!(
      uploaded_file,
      created_by_user,
      change_description: change_description
    )
  end

  # Rollback to previous version
  # @param file_object [FileManagement::Object] current file
  # @param version_number [Integer] version to rollback to
  # @param created_by_user [User] user performing rollback
  # @return [FileManagement::Object] restored version
  def rollback_version(file_object, version_number, created_by_user:)
    validate_file_access!(file_object)

    previous_version = file_object.versions.find_by(version: version_number)
    raise FileNotFoundError, "Version #{version_number} not found" unless previous_version

    # Download previous version content
    previous_content = download_file(previous_version)

    # Create new version with previous content
    create_version(
      file_object,
      StringIO.new(previous_content),
      created_by_user: created_by_user,
      change_description: "Rolled back to version #{version_number}"
    )
  end

  # Create file share
  # @param file_object [FileManagement::Object] file to share
  # @param options [Hash] share options
  # @return [FileManagement::Share] created share
  def create_share(file_object, **options)
    validate_file_access!(file_object)

    FileManagement::Share.create!(
      object: file_object,
      account: account,
      created_by_id: options[:created_by_id],
      share_type: options[:share_type] || "public_link",
      access_level: options[:access_level] || "download",
      status: "active",
      expires_at: options[:expires_at],
      max_downloads: options[:max_downloads],
      password_digest: options[:password] ? BCrypt::Password.create(options[:password]) : nil,
      download_count: 0
    )
  end

  # Get share URL
  # @param file_share [FileManagement::Share] file share
  # @return [String] share URL
  def share_url(file_share)
    # This should be configured based on your application's base URL
    base_url = ENV.fetch("APP_BASE_URL", "http://localhost:3000")
    "#{base_url}/shares/#{file_share.share_token}"
  end

  # Access shared file
  # @param share_token [String] share token
  # @param password [String] password if required
  # @param options [Hash] access options
  # @return [FileManagement::Object] file object if access granted
  def access_shared_file(share_token, password: nil, **options)
    file_share = FileManagement::Share.active.find_by(share_token: share_token)
    raise FileNotFoundError, "Share not found or expired" unless file_share

    # Verify password if required
    if file_share.password_protected? && !file_share.verify_password(password)
      raise InvalidFileError, "Invalid password"
    end

    # Check download limit
    if file_share.has_download_limit? && file_share.download_count >= file_share.max_downloads
      raise InvalidFileError, "Download limit exceeded"
    end

    # Record access
    file_share.record_access!(
      ip_address: options[:ip_address],
      user_agent: options[:user_agent],
      user_id: options[:user_id]
    )

    file_share.object
  end

  # Add tags to file
  # @param file_object [FileManagement::Object] file to tag
  # @param tag_names [Array<String>] tag names
  # @return [Array<FileManagement::Tag>] applied tags
  def add_tags(file_object, tag_names)
    validate_file_access!(file_object)

    tags = tag_names.map do |name|
      FileManagement::Tag.find_or_create_by!(account: account, name: name.strip.downcase)
    end

    tags.each do |tag|
      FileManagement::ObjectTag.find_or_create_by!(
        object: file_object,
        tag: tag,
        account: account
      )
    end

    tags
  end

  # Remove tags from file
  # @param file_object [FileManagement::Object] file to untag
  # @param tag_names [Array<String>] tag names to remove
  def remove_tags(file_object, tag_names)
    validate_file_access!(file_object)

    tag_ids = FileManagement::Tag.where(account: account, name: tag_names.map(&:downcase)).pluck(:id)
    FileManagement::ObjectTag.where(object: file_object, file_tag_id: tag_ids).destroy_all
  end

  # Queue processing job
  # @param file_object [FileManagement::Object] file to process
  # @param job_type [String] processing job type
  # @param configuration [Hash] job configuration
  # @return [FileManagement::ProcessingJob] created job
  def queue_processing_job(file_object, job_type, configuration = {})
    validate_file_access!(file_object)

    job = FileManagement::ProcessingJob.create!(
      object: file_object,
      account: account,
      job_type: job_type,
      configuration: configuration,
      status: "pending"
    )

    # Dispatch Sidekiq job based on type
    # Note: Job classes exist in worker service, so we push via Sidekiq client
    job_class = case job_type
    when "thumbnail"
                  "ThumbnailGenerationJob"
    when "metadata_extract"
                  "MetadataExtractionJob"
    when "video_processing"
                  "VideoProcessingJob"
    when "audio_processing"
                  "AudioProcessingJob"
    when "ocr"
                  # Future: OCR job
                  "MetadataExtractionJob"
    when "virus_scan"
                  # Future: Virus scan job
                  log_info("Virus scan job queued but not implemented: #{job.id}")
                  nil
    else
                  log_warn("Unknown job type #{job_type}, using metadata extraction")
                  "MetadataExtractionJob"
    end

    # Push job to Sidekiq queue
    if job_class
      Sidekiq::Client.push(
        "class" => job_class,
        "queue" => "file_processing",
        "args" => [ job.id ]
      )
      log_info("Queued #{job_class} for processing job #{job.id}")
    end

    job
  end

  # Copy file to different storage
  # @param file_object [FileManagement::Object] file to copy
  # @param destination_storage [FileStorage] destination storage config
  # @return [FileManagement::Object] new file object in destination
  def copy_to_storage(file_object, destination_storage)
    validate_file_access!(file_object)

    # Download from source
    content = download_file(file_object)

    # Create service for destination storage
    dest_service = self.class.new(account, storage_config: destination_storage)

    # Upload to destination
    dest_service.upload_file(
      StringIO.new(content),
      filename: file_object.filename,
      content_type: file_object.content_type,
      category: file_object.category,
      metadata: file_object.metadata,
      visibility: file_object.visibility
    )
  end

  # Move file to different storage
  # @param file_object [FileManagement::Object] file to move
  # @param destination_storage [FileStorage] destination storage config
  # @return [FileManagement::Object] file object in new storage
  def move_to_storage(file_object, destination_storage)
    validate_file_access!(file_object)

    new_file = copy_to_storage(file_object, destination_storage)
    delete_file(file_object, permanent: true)
    new_file
  end

  # Get file URL
  # @param file_object [FileManagement::Object] file
  # @param options [Hash] URL options
  # @return [String] file URL
  def file_url(file_object, **options)
    validate_file_access!(file_object)

    if options[:signed]
      provider.signed_url(
        file_object,
        expires_in: options[:expires_in] || 1.hour,
        disposition: options[:disposition] || "inline"
      )
    elsif options[:download]
      provider.download_url(file_object, expires_in: options[:expires_in] || 1.hour)
    else
      provider.file_url(file_object)
    end
  end

  # Batch delete files
  # @param file_objects [Array<FileManagement::Object>] files to delete
  # @param permanent [Boolean] permanent or soft delete
  # @param deleted_by_user [User] user performing deletion (required for soft delete)
  # @return [Hash] results with success and failed IDs
  def batch_delete(file_objects, permanent: false, deleted_by_user: nil)
    results = { success: [], failed: [] }

    if permanent
      # Use provider batch delete
      provider_results = provider.batch_delete(file_objects)

      # Update storage statistics and destroy objects
      provider_results[:success].each do |file_id|
        file_obj = file_objects.find { |f| f.id == file_id }
        if file_obj
          storage_config.remove_file_size(file_obj.file_size)
          file_obj.destroy
          results[:success] << file_id
        end
      end

      results[:failed] = provider_results[:failed]
    else
      # Soft delete
      file_objects.each do |file_object|
        begin
          file_object.soft_delete!(deleted_by_user)
          results[:success] << file_object.id
        rescue StandardError => e
          log_error("Batch soft delete failed for #{file_object.id}: #{e.message}")
          results[:failed] << file_object.id
        end
      end
    end

    results
  end

  # Get storage statistics
  # @return [Hash] storage statistics
  def storage_statistics
    provider.storage_statistics
  end

  # Health check
  # @return [Hash] health status
  def health_check
    provider.health_check
  end

  # Test connection
  # @return [Hash] connection test results
  def test_connection
    provider.test_connection
  end

  private

  def validate_file!(uploaded_file, filename)
    raise InvalidFileError, "File is required" if uploaded_file.nil?
    raise InvalidFileError, "Filename is required" if filename.blank?

    # Validate file extension
    extension = File.extname(filename).downcase
    if storage_config.blocked_extensions.include?(extension)
      raise InvalidFileError, "File type #{extension} is not allowed"
    end

    # Validate MIME type
    content_type = detect_content_type(uploaded_file, filename)
    if storage_config.blocked_mime_types.include?(content_type)
      raise InvalidFileError, "Content type #{content_type} is not allowed"
    end
  end

  def check_quota!(file_size)
    return unless storage_config.quota_enabled?

    unless storage_config.has_space_for?(file_size)
      raise QuotaExceededError,
            "Storage quota exceeded. Available: #{storage_config.available_space_bytes} bytes, " \
            "Required: #{file_size} bytes"
    end
  end

  def validate_file_access!(file_object)
    raise FileNotFoundError, "File not found" unless file_object
    raise InvalidFileError, "File belongs to different account" unless file_object.account_id == account.id
    raise InvalidFileError, "File belongs to different storage" unless file_object.file_storage_id == storage_config.id
  end

  def get_file_size(file)
    if file.respond_to?(:size)
      file.size
    elsif file.respond_to?(:length)
      file.length
    elsif file.respond_to?(:read)
      file.rewind if file.respond_to?(:rewind)
      size = file.read.bytesize
      file.rewind if file.respond_to?(:rewind)
      size
    else
      0
    end
  end

  def detect_content_type(file, filename)
    # Try to get content type from file
    if file.respond_to?(:content_type) && file.content_type.present?
      return file.content_type
    end

    # Fallback to filename extension
    extension = File.extname(filename).downcase
    MIME::Types.type_for(filename).first&.content_type || "application/octet-stream"
  end

  def generate_storage_key(filename, category = nil)
    # Generate unique storage key with optional category prefix
    timestamp = Time.current.strftime("%Y%m%d")
    random = SecureRandom.hex(16)
    extension = File.extname(filename)
    base_name = File.basename(filename, extension).parameterize

    if category
      "#{category}/#{timestamp}/#{random}_#{base_name}#{extension}"
    else
      "#{timestamp}/#{random}_#{base_name}#{extension}"
    end
  end

  def queue_processing_jobs(file_object, processing_tasks)
    processing_tasks.each do |task|
      queue_processing_job(file_object, task)
    end
  end

  def log_info(message)
    @logger.info "[FileStorageService] #{message}"
  end

  def log_warn(message)
    @logger.warn "[FileStorageService] #{message}"
  end

  def log_error(message)
    @logger.error "[FileStorageService] #{message}"
  end
end
