# frozen_string_literal: true

module Database
  class Backup < ApplicationRecord
    # Table name handled by Database.table_name_prefix

    # Associations
    belongs_to :created_by, class_name: "User"
    has_many :database_restores, class_name: "Database::Restore", foreign_key: "database_backup_id", dependent: :destroy

    # Validations
    validates :backup_type, presence: true, inclusion: { in: %w[full incremental manual] }
    validates :status, presence: true, inclusion: { in: %w[pending running completed failed] }

    # Scopes
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_type, ->(type) { where(backup_type: type) }

    # Callbacks
    after_create :log_backup_creation
    after_update :log_backup_status_change, if: :saved_change_to_status?

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def in_progress?
      status == "running"
    end

    def pending?
      status == "pending"
    end

    def duration
      return nil unless started_at && completed_at
      completed_at - started_at
    end

    def file_exists?
      file_path.present? && File.exist?(file_path)
    end

    def file_size_human
      return "N/A" unless file_size_bytes

      units = [ "B", "KB", "MB", "GB", "TB" ]
      base = 1024
      exp = (Math.log(file_size_bytes) / Math.log(base)).floor
      exp = units.length - 1 if exp >= units.length

      formatted = (file_size_bytes.to_f / (base ** exp)).round(2)
      "#{formatted} #{units[exp]}"
    end

    private

    def log_backup_creation
      AuditLog.create!(
        user: created_by,
        account: created_by.account,
        action: "system_backup",
        resource_type: "Database::Backup",
        resource_id: id,
        details: {
          backup_type: backup_type,
          description: description
        }
      )
    rescue StandardError => e
      Rails.logger.error "Failed to log backup creation: #{e.message}"
    end

    def log_backup_status_change
      AuditLog.create!(
        user: created_by,
        account: created_by.account,
        action: "system_backup",
        resource_type: "Database::Backup",
        resource_id: id,
        details: {
          previous_status: status_before_last_save,
          new_status: status,
          duration_seconds: duration_seconds,
          file_size_bytes: file_size_bytes,
          error_message: error_message
        }
      )
    rescue StandardError => e
      Rails.logger.error "Failed to log backup status change: #{e.message}"
    end
  end
end

# Backwards compatibility alias
