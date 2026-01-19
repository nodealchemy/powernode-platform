# frozen_string_literal: true

module Maintenance
  # Job for executing database backups
  #
  # This job is triggered when a backup is created via the admin API.
  # It fetches backup details from the backend, executes pg_dump,
  # and updates the backup status via API.
  #
  class DatabaseBackupJob < BaseJob
    sidekiq_options queue: 'maintenance',
                    retry: 2,
                    dead: true

    BACKUP_DIR = ENV.fetch('BACKUP_DIR', '/var/backups/powernode')
    MAX_BACKUP_SIZE = 10.gigabytes

    def execute(backup_id)
      log_info "Starting database backup", backup_id: backup_id

      # Fetch backup details from backend
      backup = fetch_backup(backup_id)

      # Update status to in_progress
      update_backup_status(backup_id, "in_progress")

      # Ensure backup directory exists
      ensure_backup_directory

      # Execute the backup
      result = case backup['backup_type']
      when 'full'
                 execute_full_backup(backup)
      when 'incremental'
                 execute_incremental_backup(backup)
      when 'schema_only'
                 execute_schema_backup(backup)
      else
                 execute_full_backup(backup)
      end

      if result[:success]
        log_info "Backup completed successfully",
                backup_id: backup_id,
                file_size: result[:file_size],
                duration: result[:duration]

        update_backup_status(backup_id, "completed",
          file_path: result[:file_path],
          file_size: result[:file_size],
          duration_seconds: result[:duration],
          checksum: result[:checksum]
        )
      else
        log_error "Backup failed", nil,
                 backup_id: backup_id,
                 error: result[:error]

        update_backup_status(backup_id, "failed",
          error_message: result[:error],
          duration_seconds: result[:duration]
        )

        raise "Backup failed: #{result[:error]}"
      end

      result
    end

    private

    def fetch_backup(backup_id)
      response = api_client.get("/api/v1/internal/maintenance/backups/#{backup_id}")
      response['data']
    rescue => e
      log_error "Failed to fetch backup details", e, backup_id: backup_id
      raise
    end

    def update_backup_status(backup_id, status, **params)
      api_client.patch(
        "/api/v1/internal/maintenance/backups/#{backup_id}",
        { status: status }.merge(params)
      )
    rescue => e
      log_error "Failed to update backup status", e,
               backup_id: backup_id,
               status: status
    end

    def ensure_backup_directory
      FileUtils.mkdir_p(BACKUP_DIR) unless Dir.exist?(BACKUP_DIR)
    end

    def execute_full_backup(backup)
      filename = generate_filename(backup, 'full')
      file_path = File.join(BACKUP_DIR, filename)

      start_time = Time.current

      # Get database configuration
      db_config = database_config

      # Build pg_dump command
      command = build_pg_dump_command(db_config, file_path, custom_format: true)

      # Execute backup
      success, output = execute_command(command, db_config['password'])

      duration = (Time.current - start_time).round(2)

      if success && File.exist?(file_path)
        file_size = File.size(file_path)
        checksum = calculate_checksum(file_path)

        {
          success: true,
          file_path: file_path,
          file_size: file_size,
          duration: duration,
          checksum: checksum
        }
      else
        # Clean up partial file if exists
        File.delete(file_path) if File.exist?(file_path)

        {
          success: false,
          error: output || "pg_dump failed",
          duration: duration
        }
      end
    end

    def execute_incremental_backup(backup)
      # For incremental backup, we use pg_dump with --data-only
      # and filter by tables modified since last backup
      filename = generate_filename(backup, 'incremental')
      file_path = File.join(BACKUP_DIR, filename)

      start_time = Time.current
      db_config = database_config

      # Get tables modified since last backup
      last_backup_time = backup['metadata']&.dig('last_backup_at') || 7.days.ago.iso8601

      # Build command for data-only backup
      command = build_pg_dump_command(db_config, file_path,
        custom_format: true,
        data_only: true
      )

      success, output = execute_command(command, db_config['password'])

      duration = (Time.current - start_time).round(2)

      if success && File.exist?(file_path)
        file_size = File.size(file_path)
        checksum = calculate_checksum(file_path)

        {
          success: true,
          file_path: file_path,
          file_size: file_size,
          duration: duration,
          checksum: checksum
        }
      else
        File.delete(file_path) if File.exist?(file_path)
        {
          success: false,
          error: output || "pg_dump failed",
          duration: duration
        }
      end
    end

    def execute_schema_backup(backup)
      filename = generate_filename(backup, 'schema')
      file_path = File.join(BACKUP_DIR, filename)

      start_time = Time.current
      db_config = database_config

      command = build_pg_dump_command(db_config, file_path,
        schema_only: true
      )

      success, output = execute_command(command, db_config['password'])

      duration = (Time.current - start_time).round(2)

      if success && File.exist?(file_path)
        file_size = File.size(file_path)
        checksum = calculate_checksum(file_path)

        {
          success: true,
          file_path: file_path,
          file_size: file_size,
          duration: duration,
          checksum: checksum
        }
      else
        File.delete(file_path) if File.exist?(file_path)
        {
          success: false,
          error: output || "pg_dump failed",
          duration: duration
        }
      end
    end

    def build_pg_dump_command(config, output_path, options = {})
      cmd = ["pg_dump"]

      # Connection options
      cmd << "-h" << config['host'] if config['host']
      cmd << "-p" << config['port'].to_s if config['port']
      cmd << "-U" << config['username'] if config['username']

      # Format options
      if options[:custom_format]
        cmd << "-Fc" # Custom format (compressed, supports pg_restore)
      else
        cmd << "-Fp" # Plain SQL format
      end

      # Content options
      cmd << "--schema-only" if options[:schema_only]
      cmd << "--data-only" if options[:data_only]

      # Exclude large tables if needed
      if options[:exclude_tables]
        options[:exclude_tables].each do |table|
          cmd << "--exclude-table=#{table}"
        end
      end

      # Output file
      cmd << "-f" << output_path

      # Database name
      cmd << config['database']

      cmd
    end

    def execute_command(command, password = nil)
      env = password ? { 'PGPASSWORD' => password } : {}

      stdout, stderr, status = Open3.capture3(env, *command)

      if status.success?
        [true, stdout]
      else
        [false, stderr.presence || stdout]
      end
    rescue => e
      [false, e.message]
    end

    def database_config
      # Get database configuration from environment or config file
      {
        'host' => ENV.fetch('DATABASE_HOST', 'localhost'),
        'port' => ENV.fetch('DATABASE_PORT', '5432'),
        'username' => ENV.fetch('DATABASE_USERNAME', 'postgres'),
        'password' => ENV['DATABASE_PASSWORD'],
        'database' => ENV.fetch('DATABASE_NAME', 'powernode_production')
      }
    end

    def generate_filename(backup, type)
      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      database = backup['database_name'] || 'powernode'
      "#{database}_#{type}_#{timestamp}.dump"
    end

    def calculate_checksum(file_path)
      Digest::SHA256.file(file_path).hexdigest
    end
  end
end
