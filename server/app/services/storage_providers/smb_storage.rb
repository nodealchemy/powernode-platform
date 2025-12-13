# frozen_string_literal: true

module StorageProviders
  # SMB/CIFS storage provider
  # Provides network filesystem storage using mounted SMB/CIFS shares
  class SmbStorage < Base
    attr_reader :mount_path

    def initialize(storage_config)
      super
      @mount_path = config("mount_path")
      @server_address = config("server_address")
      @share_name = config("share_name")
      @username = config("username")
      @domain = config("domain")
    end

    # Initialize storage backend
    def initialize_storage
      # Verify mount point exists
      unless File.directory?(@mount_path)
        log_info("Creating mount point: #{@mount_path}")
        FileUtils.mkdir_p(@mount_path)
      end

      unless mounted?
        log_info("Attempting to mount SMB share")
        success = mount_smb_share
        unless success
          log_error("Failed to mount SMB share")
          return false
        end
      end

      # Create base directory structure if needed
      ensure_directory_structure

      log_info("Initialized SMB storage at #{@mount_path}")
      true
    rescue StandardError => e
      log_error("Failed to initialize SMB storage: #{e.message}")
      false
    end

    # Test connection
    def test_connection
      return { success: false, error: "Mount path not configured" } unless @mount_path

      unless File.directory?(@mount_path)
        return { success: false, error: "Mount path does not exist: #{@mount_path}" }
      end

      unless mounted?
        return { success: false, error: "SMB share is not mounted" }
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
        message: "SMB storage is accessible",
        mount_path: @mount_path,
        server: @server_address,
        share: @share_name
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
            "share" => @share_name,
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

      # Calculate and store checksums
      file_object.update_columns(
        checksum_md5: calculate_checksum(content, algorithm: :md5),
        checksum_sha256: calculate_checksum(content, algorithm: :sha256)
      )

      log_info("Uploaded file to SMB: #{storage_key} (#{file_object.human_file_size})")
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

      log_info("Deleted file from SMB: #{file_object.storage_key}")
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

      log_info("Copied file in SMB: #{source_key} -> #{destination_key}")
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

      log_info("Moved file in SMB: #{source_key} -> #{destination_key}")
      true
    rescue StandardError => e
      log_error("Failed to move file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Check if file exists
    def file_exists?(file_object)
      File.exist?(full_path_for(file_object.storage_key))
    end

    # Get file URL (local path for SMB)
    def file_url(file_object)
      "file://#{full_path_for(file_object.storage_key)}"
    end

    # Get download URL (not supported for SMB, return local path)
    def download_url(file_object, expires_in: 1.hour)
      # SMB doesn't support signed URLs - return local file URL
      file_url(file_object)
    end

    # Get signed URL (not supported for SMB)
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
        "gid" => stat.gid
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

      # Check if the mount point is a mount
      mount_output = `mount 2>/dev/null`
      mount_output.include?(@mount_path) ||
        mount_output.include?("//#{@server_address}") ||
        mount_output.include?("cifs")
    rescue StandardError
      # If we can't check, assume it's mounted if the directory exists and is writable
      File.directory?(@mount_path) && File.writable?(@mount_path)
    end

    def mount_smb_share
      return true unless @server_address && @share_name

      password = decrypt_config("password")
      credentials_file = create_credentials_file(password) if password

      begin
        # Build mount command
        mount_options = []
        mount_options << "username=#{@username}" if @username
        mount_options << "domain=#{@domain}" if @domain
        mount_options << "credentials=#{credentials_file}" if credentials_file
        mount_options << "uid=#{Process.uid}"
        mount_options << "gid=#{Process.gid}"
        mount_options << "file_mode=0644"
        mount_options << "dir_mode=0755"

        mount_command = "mount -t cifs //#{@server_address}/#{@share_name} #{@mount_path} -o #{mount_options.join(',')}"

        system(mount_command)
      ensure
        # Clean up credentials file
        File.delete(credentials_file) if credentials_file && File.exist?(credentials_file)
      end
    rescue StandardError => e
      log_error("Failed to mount SMB share: #{e.message}")
      false
    end

    def create_credentials_file(password)
      credentials_file = "/tmp/.smb_credentials_#{SecureRandom.hex(8)}"

      File.open(credentials_file, "w", 0o600) do |f|
        f.puts "username=#{@username}" if @username
        f.puts "password=#{password}"
        f.puts "domain=#{@domain}" if @domain
      end

      credentials_file
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
