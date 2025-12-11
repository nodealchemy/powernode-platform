# frozen_string_literal: true

require 'fileutils'

module StorageProviders
  # Local filesystem storage provider
  # Stores files on the local disk with configurable root path
  class LocalStorage < Base
    DEFAULT_ROOT_PATH = Rails.root.join('storage', 'files')

    def initialize(storage_config)
      super
      @root_path = Pathname.new(config('root_path') || DEFAULT_ROOT_PATH)
      ensure_root_directory_exists
    end

    # Initialize storage backend
    def initialize_storage
      ensure_root_directory_exists
      create_subdirectories

      log_info("Initialized local storage at #{@root_path}")
      true
    rescue StandardError => e
      log_error("Failed to initialize local storage: #{e.message}")
      false
    end

    # Test connection
    def test_connection
      return { success: false, error: 'Root path not set' } unless @root_path

      unless @root_path.directory?
        return { success: false, error: "Directory does not exist: #{@root_path}" }
      end

      unless @root_path.writable?
        return { success: false, error: "Directory is not writable: #{@root_path}" }
      end

      # Try to create a test file
      test_file = @root_path.join('.health_check')
      File.write(test_file, 'test')
      File.delete(test_file)

      {
        success: true,
        message: 'Local storage is accessible',
        root_path: @root_path.to_s,
        writable: true
      }
    rescue StandardError => e
      {
        success: false,
        error: "Connection test failed: #{e.message}"
      }
    end

    # Health check
    def health_check
      connection_test = test_connection

      if connection_test[:success]
        disk_stats = get_disk_statistics

        {
          status: disk_stats[:usage_percentage] < 90 ? 'healthy' : 'degraded',
          details: {
            'root_path' => @root_path.to_s,
            'writable' => true,
            'disk_total_bytes' => disk_stats[:total_bytes],
            'disk_free_bytes' => disk_stats[:free_bytes],
            'disk_usage_percentage' => disk_stats[:usage_percentage],
            'files_count' => storage_config.files_count,
            'total_size_bytes' => storage_config.total_size_bytes,
            'checked_at' => Time.current.iso8601
          }
        }
      else
        {
          status: 'failed',
          details: {
            'error' => connection_test[:error],
            'checked_at' => Time.current.iso8601
          }
        }
      end
    end

    # Upload file
    def upload_file(file_object, file_data, options = {})
      file_path = full_path(file_object.storage_key)

      # Ensure directory exists
      FileUtils.mkdir_p(file_path.dirname)

      # Write file
      if file_data.respond_to?(:read)
        File.open(file_path, 'wb') do |f|
          file_data.rewind if file_data.respond_to?(:rewind)
          IO.copy_stream(file_data, f)
        end
      else
        File.write(file_path, file_data, mode: 'wb')
      end

      # Calculate checksums
      file_object.update_columns(
        checksum_md5: calculate_checksum(File.read(file_path), algorithm: :md5),
        checksum_sha256: calculate_checksum(File.read(file_path), algorithm: :sha256)
      )

      log_info("Uploaded file: #{file_object.storage_key} (#{file_object.human_file_size})")
      true
    rescue StandardError => e
      log_error("Failed to upload file #{file_object.storage_key}: #{e.message}")
      raise e
    end

    # Read file content
    def read_file(file_object)
      file_path = full_path(file_object.storage_key)

      unless file_path.exist?
        raise "File not found: #{file_object.storage_key}"
      end

      File.read(file_path, mode: 'rb')
    end

    # Stream file content
    def stream_file(file_object, &block)
      file_path = full_path(file_object.storage_key)

      unless file_path.exist?
        raise "File not found: #{file_object.storage_key}"
      end

      File.open(file_path, 'rb') do |file|
        while (chunk = file.read(64.kilobytes))
          yield chunk
        end
      end
    end

    # Delete file
    def delete_file(file_object)
      file_path = full_path(file_object.storage_key)

      return true unless file_path.exist?  # Already deleted

      File.delete(file_path)
      log_info("Deleted file: #{file_object.storage_key}")
      true
    rescue StandardError => e
      log_error("Failed to delete file #{file_object.storage_key}: #{e.message}")
      false
    end

    # Copy file
    def copy_file(source_key, destination_key)
      source_path = full_path(source_key)
      dest_path = full_path(destination_key)

      unless source_path.exist?
        raise "Source file not found: #{source_key}"
      end

      # Ensure destination directory exists
      FileUtils.mkdir_p(dest_path.dirname)

      FileUtils.cp(source_path, dest_path)
      log_info("Copied file: #{source_key} -> #{destination_key}")
      true
    rescue StandardError => e
      log_error("Failed to copy file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Move file
    def move_file(source_key, destination_key)
      source_path = full_path(source_key)
      dest_path = full_path(destination_key)

      unless source_path.exist?
        raise "Source file not found: #{source_key}"
      end

      # Ensure destination directory exists
      FileUtils.mkdir_p(dest_path.dirname)

      FileUtils.mv(source_path, dest_path)
      log_info("Moved file: #{source_key} -> #{destination_key}")
      true
    rescue StandardError => e
      log_error("Failed to move file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Check if file exists
    def file_exists?(file_object)
      full_path(file_object.storage_key).exist?
    end

    # Get file URL (for viewing/displaying the file)
    def file_url(file_object)
      # Return public endpoint for public files (no auth), or download endpoint for others
      if file_object.visibility == 'public'
        "/api/v1/files/#{file_object.id}/public"
      else
        "/api/v1/files/#{file_object.id}/download?disposition=inline"
      end
    end

    # Get download URL (for downloading as attachment)
    def download_url(file_object, expires_in: 1.hour)
      # Local storage doesn't support expiring URLs
      "/api/v1/files/#{file_object.id}/download"
    end

    # Get signed URL
    def signed_url(file_object, expires_in: 1.hour, disposition: 'inline')
      # Local storage doesn't support signed URLs
      # Return the same as file_url with disposition
      "/api/v1/files/#{file_object.id}/download?disposition=#{disposition}"
    end

    # Get file metadata
    def file_metadata(file_object)
      file_path = full_path(file_object.storage_key)

      unless file_path.exist?
        raise "File not found: #{file_object.storage_key}"
      end

      stat = file_path.stat

      {
        'size' => stat.size,
        'modified_at' => stat.mtime.iso8601,
        'created_at' => stat.ctime.iso8601,
        'mode' => stat.mode.to_s(8),
        'readable' => file_path.readable?,
        'writable' => file_path.writable?,
        'path' => file_path.to_s
      }
    end

    # List files in directory
    def list_files(prefix: nil, options: {})
      search_path = prefix ? @root_path.join(prefix) : @root_path

      return [] unless search_path.directory?

      files = []
      search_path.find do |path|
        next if path.directory?

        relative_path = path.relative_path_from(@root_path).to_s

        files << {
          'key' => relative_path,
          'size' => path.size,
          'modified_at' => path.mtime.iso8601,
          'etag' => Digest::MD5.hexdigest(path.to_s)
        }
      end

      files
    rescue StandardError => e
      log_error("Failed to list files: #{e.message}")
      []
    end

    # Batch operations
    def batch_delete(file_objects)
      results = { success: [], failed: [] }

      file_objects.each do |file_object|
        if delete_file(file_object)
          results[:success] << file_object.id
        else
          results[:failed] << file_object.id
        end
      end

      results
    end

    # Get disk statistics
    def get_disk_statistics
      stat = Sys::Filesystem.stat(@root_path.to_s) if defined?(Sys::Filesystem)

      if stat
        total_bytes = stat.blocks * stat.block_size
        free_bytes = stat.blocks_free * stat.block_size
        used_bytes = total_bytes - free_bytes

        {
          total_bytes: total_bytes,
          free_bytes: free_bytes,
          used_bytes: used_bytes,
          usage_percentage: ((used_bytes.to_f / total_bytes) * 100).round(2)
        }
      else
        # Fallback if Sys::Filesystem not available
        {
          total_bytes: 0,
          free_bytes: 0,
          used_bytes: 0,
          usage_percentage: 0
        }
      end
    end

    private

    def full_path(storage_key)
      @root_path.join(storage_key)
    end

    def ensure_root_directory_exists
      FileUtils.mkdir_p(@root_path) unless @root_path.directory?
    end

    def create_subdirectories
      # Create subdirectories for different file categories
      categories = %w[user_upload workflow_output ai_generated temp system import]

      categories.each do |category|
        category_path = @root_path.join(category)
        FileUtils.mkdir_p(category_path) unless category_path.directory?
      end
    end
  end
end
