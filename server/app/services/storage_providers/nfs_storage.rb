# frozen_string_literal: true

module StorageProviders
  # NFS (Network File System) storage provider
  # Provides network filesystem storage using mounted NFS shares
  class NfsStorage < Base
    attr_reader :mount_path

    def initialize(storage_config)
      super
      @mount_path = config("mount_path")
      @server_address = config("server_address")
      @share_path = config("share_path")
    end

    # Initialize storage backend
    def initialize_storage
      # Verify mount point exists and is mounted
      unless File.directory?(@mount_path)
        log_error("NFS mount path does not exist: #{@mount_path}")
        return false
      end

      unless mounted?
        log_info("Attempting to mount NFS share")
        success = mount_nfs_share
        unless success
          log_error("Failed to mount NFS share")
          return false
        end
      end

      # Create base directory structure if needed
      ensure_directory_structure

      log_info("Initialized NFS storage at #{@mount_path}")
      true
    rescue StandardError => e
      log_error("Failed to initialize NFS storage: #{e.message}")
      false
    end

    # Test connection
    def test_connection
      return { success: false, error: "Mount path not configured" } unless @mount_path

      unless File.directory?(@mount_path)
        return { success: false, error: "Mount path does not exist: #{@mount_path}" }
      end

      unless mounted?
        return { success: false, error: "NFS share is not mounted" }
      end

      # Test write access
      test_file = File.join(@mount_path, ".powernode_test_#{Time.current.to_i}")
      begin
        File.write(test_file, "test")
        File.delete(test_file)
      rescue StandardError => e
        return { success: false, error: "Write test failed: #{e.message}" }
      end

      {
        success: true,
        message: "NFS storage is accessible",
        mount_path: @mount_path,
        server: @server_address,
        share: @share_path
      }
    end

    # Health check
    def health_check
      connection_test = test_connection

      if connection_test[:success]
        disk_stats = get_disk_stats

        {
          status: "healthy",
          details: {
            "mount_path" => @mount_path,
            "server" => @server_address,
            "accessible" => true,
            "mounted" => mounted?,
            "files_count" => storage_config.files_count,
            "total_size_bytes" => storage_config.total_size_bytes,
            "disk_total_bytes" => disk_stats[:total],
            "disk_free_bytes" => disk_stats[:free],
            "disk_used_percentage" => disk_stats[:used_percentage],
            "checked_at" => Time.current.iso8601
          }
        }
      else
        {
          status: "failed",
          details: {
            "error" => connection_test[:error],
            "mounted" => mounted?,
            "checked_at" => Time.current.iso8601
          }
        }
      end
    end

    # Upload file
    def upload_file(file_object, file_data, options = {})
      storage_key = file_object.storage_key
      full_path = full_path_for(storage_key)

      # Ensure parent directory exists
      FileUtils.mkdir_p(File.dirname(full_path))

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

      # Write file
      File.open(full_path, "wb") do |f|
        f.write(content)
      end

      # Set permissions
      FileUtils.chmod(0o644, full_path)

      # Calculate and store checksums
      file_object.update_columns(
        checksum_md5: calculate_checksum(content, algorithm: :md5),
        checksum_sha256: calculate_checksum(content, algorithm: :sha256)
      )

      log_info("Uploaded file to NFS: #{storage_key} (#{file_object.human_file_size})")
      true
    rescue StandardError => e
      log_error("Failed to upload file #{storage_key}: #{e.message}")
      raise e
    end

    # Read file content
    def read_file(file_object)
      full_path = full_path_for(file_object.storage_key)

      raise "File not found: #{file_object.storage_key}" unless File.exist?(full_path)

      File.binread(full_path)
    end

    # Stream file content
    def stream_file(file_object, &block)
      full_path = full_path_for(file_object.storage_key)

      raise "File not found: #{file_object.storage_key}" unless File.exist?(full_path)

      File.open(full_path, "rb") do |f|
        while (chunk = f.read(4.megabytes))
          yield chunk
        end
      end
    end

    # Delete file
    def delete_file(file_object)
      full_path = full_path_for(file_object.storage_key)

      return true unless File.exist?(full_path)

      File.delete(full_path)

      # Clean up empty parent directories
      cleanup_empty_directories(File.dirname(full_path))

      log_info("Deleted file from NFS: #{file_object.storage_key}")
      true
    rescue StandardError => e
      log_error("Failed to delete file #{file_object.storage_key}: #{e.message}")
      false
    end

    # Copy file
    def copy_file(source_key, destination_key)
      source_path = full_path_for(source_key)
      destination_path = full_path_for(destination_key)

      raise "Source file not found: #{source_key}" unless File.exist?(source_path)

      # Ensure parent directory exists
      FileUtils.mkdir_p(File.dirname(destination_path))

      FileUtils.cp(source_path, destination_path)

      log_info("Copied file in NFS: #{source_key} -> #{destination_key}")
      true
    rescue StandardError => e
      log_error("Failed to copy file #{source_key} to #{destination_key}: #{e.message}")
      raise e if e.message.include?("Source file not found")
      false
    end

    # Move file
    def move_file(source_key, destination_key)
      source_path = full_path_for(source_key)
      destination_path = full_path_for(destination_key)

      raise "Source file not found: #{source_key}" unless File.exist?(source_path)

      # Ensure parent directory exists
      FileUtils.mkdir_p(File.dirname(destination_path))

      FileUtils.mv(source_path, destination_path)

      # Clean up empty parent directories
      cleanup_empty_directories(File.dirname(source_path))

      log_info("Moved file in NFS: #{source_key} -> #{destination_key}")
      true
    rescue StandardError => e
      log_error("Failed to move file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Check if file exists
    def file_exists?(file_object)
      File.exist?(full_path_for(file_object.storage_key))
    end

    # Get file URL (local path for NFS)
    def file_url(file_object)
      "file://#{full_path_for(file_object.storage_key)}"
    end

    # Get download URL (not supported for NFS, return local path)
    def download_url(file_object, expires_in: 1.hour)
      # NFS doesn't support signed URLs - return local file URL
      # Applications should handle serving files through a web server
      file_url(file_object)
    end

    # Get signed URL (not supported for NFS)
    def signed_url(file_object, expires_in: 1.hour, disposition: "inline")
      file_url(file_object)
    end

    # Get file metadata
    def file_metadata(file_object)
      full_path = full_path_for(file_object.storage_key)

      raise "File not found: #{file_object.storage_key}" unless File.exist?(full_path)

      stat = File.stat(full_path)

      {
        "size" => stat.size,
        "created_at" => stat.ctime&.iso8601,
        "modified_at" => stat.mtime&.iso8601,
        "accessed_at" => stat.atime&.iso8601,
        "mode" => stat.mode.to_s(8),
        "uid" => stat.uid,
        "gid" => stat.gid,
        "inode" => stat.ino
      }
    end

    # List files
    def list_files(prefix: nil, options: {})
      search_path = prefix ? File.join(@mount_path, prefix, "**", "*") : File.join(@mount_path, "**", "*")
      max_results = options[:max_keys] || 1000

      files = []
      Dir.glob(search_path).select { |f| File.file?(f) }.first(max_results).each do |full_path|
        relative_path = full_path.sub("#{@mount_path}/", "")
        stat = File.stat(full_path)

        files << {
          "key" => relative_path,
          "size" => stat.size,
          "modified_at" => stat.mtime&.iso8601
        }
      end

      files
    rescue StandardError => e
      log_error("Failed to list files: #{e.message}")
      []
    end

    private

    def full_path_for(storage_key)
      File.join(@mount_path, sanitize_key(storage_key))
    end

    def mounted?
      return false unless @mount_path

      # Check if the mount point is a mount (on Linux/macOS)
      mount_output = `mount 2>/dev/null`
      mount_output.include?(@mount_path) || mount_output.include?(@server_address.to_s)
    rescue StandardError
      # If we can't check, assume it's mounted if the directory exists and is writable
      File.directory?(@mount_path) && File.writable?(@mount_path)
    end

    def mount_nfs_share
      return true unless @server_address && @share_path

      # Attempt to mount (requires appropriate permissions)
      mount_command = "mount -t nfs #{@server_address}:#{@share_path} #{@mount_path}"

      system(mount_command)
    rescue StandardError => e
      log_error("Failed to mount NFS share: #{e.message}")
      false
    end

    def ensure_directory_structure
      # Create base directories for organization
      %w[files temp archive].each do |subdir|
        dir_path = File.join(@mount_path, subdir)
        FileUtils.mkdir_p(dir_path) unless File.directory?(dir_path)
      end
    end

    def cleanup_empty_directories(directory_path)
      # Don't clean up if we're at the mount path
      return if directory_path == @mount_path
      return unless File.directory?(directory_path)
      return unless Dir.empty?(directory_path)

      Dir.rmdir(directory_path)
      cleanup_empty_directories(File.dirname(directory_path))
    rescue StandardError
      # Ignore errors during cleanup
    end

    def get_disk_stats
      stat = Sys::Filesystem.stat(@mount_path)
      {
        total: stat.blocks * stat.block_size,
        free: stat.blocks_available * stat.block_size,
        used_percentage: ((1 - (stat.blocks_available.to_f / stat.blocks)) * 100).round(1)
      }
    rescue StandardError
      { total: 0, free: 0, used_percentage: 0 }
    end
  end
end
