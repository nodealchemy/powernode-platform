# frozen_string_literal: true

class DatabaseBackupService
  include ActiveModel::Model

  BACKUP_TYPES = %w[full incremental schema_only].freeze
  BACKUP_RETENTION_DAYS = 30

  class << self
    def list_backups
      backups = DatabaseBackup.includes(:user).order(created_at: :desc)

      backups.map do |backup|
        {
          id: backup.id,
          filename: backup.filename,
          type: backup.backup_type,
          size: backup.file_size,
          size_human: format_file_size(backup.file_size),
          status: backup.status,
          created_at: backup.created_at.iso8601,
          created_by: backup.user&.email,
          description: backup.description,
          duration: backup.duration_seconds,
          download_url: backup.status == "completed" ? "/api/v1/admin/maintenance/backups/#{backup.id}/download" : nil
        }
      end
    end

    def create_backup(backup_type, description, user)
      unless BACKUP_TYPES.include?(backup_type)
        return { success: false, error: "Invalid backup type. Must be one of: #{BACKUP_TYPES.join(', ')}" }
      end

      backup = DatabaseBackup.create!(
        backup_type: backup_type,
        description: description,
        user: user,
        status: "pending",
        filename: generate_backup_filename(backup_type),
        started_at: Time.current
      )

      # Enqueue backup job
      DatabaseBackupJob.perform_async(backup.id)

      {
        success: true,
        backup: {
          id: backup.id,
          type: backup_type,
          status: "pending",
          filename: backup.filename,
          created_at: backup.created_at.iso8601
        }
      }
    rescue => e
      Rails.logger.error "Failed to create backup: #{e.message}"
      { success: false, error: e.message }
    end

    def delete_backup(backup_id)
      backup = DatabaseBackup.find_by(id: backup_id)
      return { success: false, error: "Backup not found" } unless backup

      # Delete the physical file with path validation
      if backup.file_path && File.exist?(backup.file_path)
        # Security: Validate file path is within allowed backups directory
        backups_base = Rails.root.join("tmp", "backups").to_s
        expanded_path = File.expand_path(backup.file_path)
        if expanded_path.start_with?(backups_base)
          File.delete(backup.file_path)
        else
          Rails.logger.error "Attempted to delete file outside backups directory: #{backup.file_path}"
          return { success: false, error: "Invalid backup file path" }
        end
      end

      backup.destroy!
      { success: true }
    rescue => e
      Rails.logger.error "Failed to delete backup: #{e.message}"
      { success: false, error: e.message }
    end

    def restore_backup(backup_id, user)
      backup = DatabaseBackup.find_by(id: backup_id)
      return { success: false, error: "Backup not found" } unless backup
      return { success: false, error: "Backup file not completed" } unless backup.status == "completed"
      return { success: false, error: "Backup file not found" } unless backup.file_path && File.exist?(backup.file_path)

      # Create restore record
      restore = DatabaseRestore.create!(
        database_backup: backup,
        user: user,
        status: "pending",
        started_at: Time.current
      )

      # Enqueue restore job
      DatabaseRestoreJob.perform_async(restore.id)

      { success: true, restore_id: restore.id }
    rescue => e
      Rails.logger.error "Failed to initiate restore: #{e.message}"
      { success: false, error: e.message }
    end

    def perform_backup(backup_id)
      backup = DatabaseBackup.find(backup_id)
      backup.update!(status: "in_progress", started_at: Time.current)

      begin
        case backup.backup_type
        when "full"
          perform_full_backup(backup)
        when "incremental"
          perform_incremental_backup(backup)
        when "schema_only"
          perform_schema_backup(backup)
        end

        backup.update!(
          status: "completed",
          completed_at: Time.current,
          duration_seconds: (Time.current - backup.started_at).to_i,
          file_size: File.size(backup.file_path)
        )

        # Clean up old backups
        cleanup_old_backups

        Rails.logger.info "Database backup completed: #{backup.filename}"
      rescue => e
        backup.update!(
          status: "failed",
          error_message: e.message,
          completed_at: Time.current
        )
        Rails.logger.error "Database backup failed: #{e.message}"
        raise e
      end
    end

    def perform_restore(restore_id)
      restore = DatabaseRestore.find(restore_id)
      backup = restore.database_backup

      restore.update!(status: "in_progress", started_at: Time.current)

      begin
        case backup.backup_type
        when "full"
          perform_full_restore(backup.file_path)
        when "schema_only"
          perform_schema_restore(backup.file_path)
        else
          raise "Incremental restores are not supported"
        end

        restore.update!(
          status: "completed",
          completed_at: Time.current,
          duration_seconds: (Time.current - restore.started_at).to_i
        )

        Rails.logger.info "Database restore completed: #{backup.filename}"
      rescue => e
        restore.update!(
          status: "failed",
          error_message: e.message,
          completed_at: Time.current
        )
        Rails.logger.error "Database restore failed: #{e.message}"
        raise e
      end
    end

    private

    def generate_backup_filename(backup_type)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      "powernode_#{backup_type}_#{timestamp}.sql"
    end

    def backup_directory
      @backup_directory ||= Rails.root.join("storage", "backups").tap do |dir|
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end
    end

    def perform_full_backup(backup)
      file_path = backup_directory.join(backup.filename)
      backup.update!(file_path: file_path.to_s)

      db_config = ActiveRecord::Base.connection_db_config.configuration_hash

      command = [
        "pg_dump",
        "--host", db_config[:host] || "localhost",
        "--port", (db_config[:port] || 5432).to_s,
        "--username", db_config[:username],
        "--no-password",
        "--verbose",
        "--clean",
        "--no-acl",
        "--no-owner",
        "--format=custom",
        "--file", file_path.to_s,
        db_config[:database]
      ]

      env = { "PGPASSWORD" => db_config[:password] }

      result = system(env, *command)
      raise "pg_dump failed with exit code #{$?.exitstatus}" unless result
    end

    def perform_incremental_backup(backup)
      # Incremental backup implementation would go here
      # For now, fall back to full backup
      perform_full_backup(backup)
    end

    def perform_schema_backup(backup)
      file_path = backup_directory.join(backup.filename)
      backup.update!(file_path: file_path.to_s)

      db_config = ActiveRecord::Base.connection_db_config.configuration_hash

      command = [
        "pg_dump",
        "--host", db_config[:host] || "localhost",
        "--port", (db_config[:port] || 5432).to_s,
        "--username", db_config[:username],
        "--no-password",
        "--schema-only",
        "--verbose",
        "--clean",
        "--no-acl",
        "--no-owner",
        "--format=custom",
        "--file", file_path.to_s,
        db_config[:database]
      ]

      env = { "PGPASSWORD" => db_config[:password] }

      result = system(env, *command)
      raise "pg_dump failed with exit code #{$?.exitstatus}" unless result
    end

    def perform_full_restore(backup_file_path)
      db_config = ActiveRecord::Base.connection_db_config.configuration_hash

      command = [
        "pg_restore",
        "--host", db_config[:host] || "localhost",
        "--port", (db_config[:port] || 5432).to_s,
        "--username", db_config[:username],
        "--no-password",
        "--verbose",
        "--clean",
        "--no-acl",
        "--no-owner",
        "--dbname", db_config[:database],
        backup_file_path
      ]

      env = { "PGPASSWORD" => db_config[:password] }

      result = system(env, *command)
      raise "pg_restore failed with exit code #{$?.exitstatus}" unless result
    end

    def perform_schema_restore(backup_file_path)
      perform_full_restore(backup_file_path)
    end

    def cleanup_old_backups
      old_backups = DatabaseBackup.where(
        "created_at < ?",
        BACKUP_RETENTION_DAYS.days.ago
      )

      old_backups.each do |backup|
        if backup.file_path && File.exist?(backup.file_path)
          File.delete(backup.file_path)
        end
        backup.destroy!
      end

      Rails.logger.info "Cleaned up #{old_backups.count} old backups"
    end

    def format_file_size(bytes)
      return "0 B" if bytes.nil? || bytes.zero?

      units = [ "B", "KB", "MB", "GB", "TB" ]
      base = 1024
      exp = (Math.log(bytes) / Math.log(base)).floor
      exp = units.length - 1 if exp >= units.length

      formatted = (bytes.to_f / (base ** exp)).round(2)
      "#{formatted} #{units[exp]}"
    end
  end
end
