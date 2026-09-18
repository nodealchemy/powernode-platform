# frozen_string_literal: true

module Database
  class Backup < ApplicationRecord
    # Table name handled by Database.table_name_prefix

    # Associations
    # optional: true (IMP-8b25fb48368e) — a worker-initiated backup (the only
    # caller today: Api::V1::Internal::MaintenanceController#create_backup)
    # has no user. Matches the established platform convention for
    # system/worker-initiated rows (Devops::Pipeline, ApiKey, WebhookEndpoint,
    # Ai::Campaign, ... all declare `created_by` optional for the same reason).
    belongs_to :created_by, class_name: "User", optional: true
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
      write_backup_audit!(
        metadata: {
          backup_type: backup_type,
          description: description
        }
      )
    rescue StandardError => e
      Rails.logger.error "Failed to log backup creation: #{e.message}"
    end

    def log_backup_status_change
      write_backup_audit!(
        metadata: {
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

    # IMP-8b25fb48368e / IMP-19c753c1e8a9. The single writer both callbacks
    # above now share (previously each called AuditLog.create! directly, with
    # two independent, latent defects: `details:` is not a real AuditLog
    # attribute — the free-form column is `metadata` — so every call always
    # raised ActiveModel::UnknownAttributeError, silently swallowed by the
    # rescue below, and account: created_by.account raised NoMethodError for
    # any accountless (worker-initiated) backup once created_by stopped being
    # a hard failure).
    #
    # Account resolution: a real created_by has a real tenant, so its account
    # is used (the ordinary user-initiated path — unused today, since the only
    # caller is the worker, but the association is not worker-only). A
    # worker-initiated backup has no created_by, so this falls through to
    # Audit::PlatformAccount — the platform sentinel, never `Account.first`
    # (that shape was already rejected twice at this exact call site: see
    # this file's git history and internal_base_controller.rb's D1 comment).
    # `resolve_for` returns nil AND emits Auditable::SKIPPED_NOTIFICATION when
    # no sentinel exists, which is the accepted countable signal for "this
    # platform event went unaudited" — so `return unless account` here is a
    # deliberate skip, not a dropped error.
    #
    # This is the ONLY audit write for backup creation now — the caller
    # (Api::V1::Internal::MaintenanceController#create_backup) no longer
    # writes its own "backup.create" row, so there is exactly one row per
    # event instead of two competing (and previously, two silently failing)
    # writers.
    #
    # requires_new: true (S2, IMP-8b25fb48368e second review). This callback
    # runs inside the Database::Backup save's own open transaction
    # (after_create/after_update). Before this fix, `details:` always raised
    # at Ruby ATTRIBUTE ASSIGNMENT — before any SQL reached Postgres — so the
    # surrounding transaction was never actually at risk. Now the INSERT is
    # real, so a genuine DB-level failure here (a constraint violation, the
    # integrity-hash chain in audit_log.rb) would abort the whole Postgres
    # transaction; the `rescue StandardError` below only catches the RUBY
    # exception, it does not un-abort the connection, so the backup's own
    # save would then fail with PG::InFailedSqlTransaction on its next
    # statement (or roll back outright) — an audit failure turning into a
    # failed backup. `requires_new: true` issues a real SAVEPOINT, so a
    # failure here rolls back to it and the outer (backup) transaction stays
    # usable. Same precedent and same reasoning as
    # Ai::Tools::BaseTool#persist_undeclared_action_audit ("SAVEPOINT, not
    # just a rescue").
    def write_backup_audit!(metadata:)
      account = created_by&.account || ::Audit::PlatformAccount.resolve_for(
        model: self.class.name, record_id: id, action: "system_backup"
      )
      return unless account

      AuditLog.transaction(requires_new: true) do
        AuditLog.create!(
          user: created_by,
          account: account,
          action: "system_backup",
          source: created_by ? "web" : "system",
          resource_type: "Database::Backup",
          resource_id: id,
          metadata: metadata
        )
      end
    end
  end
end

# Backwards compatibility alias
