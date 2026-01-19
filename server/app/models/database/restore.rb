# frozen_string_literal: true

module Database
  class Restore < ApplicationRecord
    # Table name handled by Database.table_name_prefix

    # Associations
    belongs_to :database_backup, class_name: "Database::Backup", foreign_key: "database_backup_id"
    belongs_to :user

    # Validations
    validates :status, presence: true, inclusion: { in: %w[pending in_progress completed failed] }

    # Scopes
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    after_create :log_restore_creation
    after_update :log_restore_status_change, if: :saved_change_to_status?

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def in_progress?
      status == "in_progress"
    end

    def pending?
      status == "pending"
    end

    def duration
      return nil unless started_at && completed_at
      completed_at - started_at
    end

    private

    def log_restore_creation
      AuditLog.create!(
        user: user,
        account: user.account,
        action: "database_restore_created",
        resource_type: "Database::Restore",
        resource_id: id,
        details: {
          backup_id: database_backup.id,
          backup_filename: database_backup.filename,
          backup_type: database_backup.backup_type
        }
      )
    rescue => e
      Rails.logger.error "Failed to log restore creation: #{e.message}"
    end

    def log_restore_status_change
      AuditLog.create!(
        user: user,
        account: user.account,
        action: "database_restore_status_changed",
        resource_type: "Database::Restore",
        resource_id: id,
        details: {
          previous_status: status_before_last_save,
          new_status: status,
          backup_filename: database_backup.filename,
          duration_seconds: duration_seconds,
          error_message: error_message
        }
      )
    rescue => e
      Rails.logger.error "Failed to log restore status change: #{e.message}"
    end
  end
end

# Backwards compatibility alias
