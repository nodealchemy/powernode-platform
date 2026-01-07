# frozen_string_literal: true

module Maintenance
  # Job for executing database restores from backups
  #
  # This job is triggered when a restore is initiated via the admin API.
  # It fetches restore details from the backend, executes pg_restore,
  # and updates the restore status via API.
  #
  class DatabaseRestoreJob < BaseJob
    sidekiq_options queue: 'maintenance',
                    retry: 0, # Don't retry restores automatically
                    dead: true

    def execute(restore_id)
      log_info "Starting database restore", restore_id: restore_id

      # Fetch restore details from backend
      restore = fetch_restore(restore_id)

      # Validate backup file exists
      backup_path = restore['backup_file_path']
      unless backup_path.present? && File.exist?(backup_path)
        update_restore_status(restore_id, "failed",
          error_message: "Backup file not found: #{backup_path}"
        )
        raise "Backup file not found: #{backup_path}"
      end

      # Update status to in_progress
      update_restore_status(restore_id, "in_progress")

      # Execute the restore
      start_time = Time.current

      result = case restore['restore_type']
      when 'full'
                 execute_full_restore(restore, backup_path)
      when 'schema'
                 execute_schema_restore(restore, backup_path)
      when 'data_only'
                 execute_data_restore(restore, backup_path)
      else
                 execute_full_restore(restore, backup_path)
      end

      duration = (Time.current - start_time).round(2)

      if result[:success]
        log_info "Restore completed successfully",
                restore_id: restore_id,
                tables: result[:tables_restored],
                duration: duration

        update_restore_status(restore_id, "completed",
          duration_seconds: duration,
          tables_restored: result[:tables_restored],
          rows_restored: result[:rows_restored]
        )
      else
        log_error "Restore failed", nil,
                 restore_id: restore_id,
                 error: result[:error]

        update_restore_status(restore_id, "failed",
          error_message: result[:error],
          duration_seconds: duration
        )

        raise "Restore failed: #{result[:error]}"
      end

      result
    end

    private

    def fetch_restore(restore_id)
      response = api_client.get("/api/v1/internal/maintenance/restores/#{restore_id}")
      response['data']
    rescue => e
      log_error "Failed to fetch restore details", e, restore_id: restore_id
      raise
    end

    def update_restore_status(restore_id, status, **params)
      api_client.patch(
        "/api/v1/internal/maintenance/restores/#{restore_id}",
        { status: status }.merge(params)
      )
    rescue => e
      log_error "Failed to update restore status", e,
               restore_id: restore_id,
               status: status
    end

    def execute_full_restore(restore, backup_path)
      db_config = database_config(restore['target_database'])

      # Build pg_restore command
      command = build_pg_restore_command(db_config, backup_path,
        clean: true,
        if_exists: true
      )

      success, output = execute_command(command, db_config['password'])

      if success
        stats = extract_restore_stats(output)
        {
          success: true,
          tables_restored: stats[:tables],
          rows_restored: stats[:rows]
        }
      else
        {
          success: false,
          error: sanitize_error_output(output)
        }
      end
    end

    def execute_schema_restore(restore, backup_path)
      db_config = database_config(restore['target_database'])

      command = build_pg_restore_command(db_config, backup_path,
        schema_only: true,
        clean: true,
        if_exists: true
      )

      success, output = execute_command(command, db_config['password'])

      if success
        {
          success: true,
          tables_restored: count_tables_in_backup(backup_path),
          rows_restored: 0
        }
      else
        {
          success: false,
          error: sanitize_error_output(output)
        }
      end
    end

    def execute_data_restore(restore, backup_path)
      db_config = database_config(restore['target_database'])

      command = build_pg_restore_command(db_config, backup_path,
        data_only: true
      )

      success, output = execute_command(command, db_config['password'])

      if success
        stats = extract_restore_stats(output)
        {
          success: true,
          tables_restored: stats[:tables],
          rows_restored: stats[:rows]
        }
      else
        {
          success: false,
          error: sanitize_error_output(output)
        }
      end
    end

    def build_pg_restore_command(config, backup_path, options = {})
      cmd = ["pg_restore"]

      # Connection options
      cmd << "-h" << config['host'] if config['host']
      cmd << "-p" << config['port'].to_s if config['port']
      cmd << "-U" << config['username'] if config['username']

      # Target database
      cmd << "-d" << config['database']

      # Restore options
      cmd << "--clean" if options[:clean]
      cmd << "--if-exists" if options[:if_exists]
      cmd << "--schema-only" if options[:schema_only]
      cmd << "--data-only" if options[:data_only]

      # Don't stop on errors (collect all errors at the end)
      cmd << "--no-owner" # Don't restore ownership
      cmd << "--no-privileges" # Don't restore privileges
      cmd << "-v" # Verbose output for stats

      # Backup file
      cmd << backup_path

      cmd
    end

    def execute_command(command, password = nil)
      env = password ? { 'PGPASSWORD' => password } : {}

      stdout, stderr, status = Open3.capture3(env, *command)

      # pg_restore may return non-zero even on success with warnings
      # Check for critical errors in stderr
      if status.success? || !stderr.include?('FATAL') && !stderr.include?('could not connect')
        [true, stdout + stderr]
      else
        [false, stderr.presence || stdout]
      end
    rescue => e
      [false, e.message]
    end

    def database_config(target_database = nil)
      {
        'host' => ENV.fetch('DATABASE_HOST', 'localhost'),
        'port' => ENV.fetch('DATABASE_PORT', '5432'),
        'username' => ENV.fetch('DATABASE_USERNAME', 'postgres'),
        'password' => ENV['DATABASE_PASSWORD'],
        'database' => target_database || ENV.fetch('DATABASE_NAME', 'powernode_production')
      }
    end

    def extract_restore_stats(output)
      tables = output.scan(/restoring table/).count
      rows = output.scan(/COPY (\d+)/).flatten.map(&:to_i).sum

      { tables: tables, rows: rows }
    rescue
      { tables: 0, rows: 0 }
    end

    def count_tables_in_backup(backup_path)
      # Use pg_restore to list contents
      output, _ = Open3.capture2("pg_restore", "-l", backup_path)
      output.scan(/TABLE/).count
    rescue
      0
    end

    def sanitize_error_output(output)
      # Remove sensitive info from error output
      output.to_s
            .gsub(/password=\S+/, 'password=***')
            .gsub(/PGPASSWORD=\S+/, 'PGPASSWORD=***')
            .truncate(1000)
    end
  end
end
