# frozen_string_literal: true

module DataManagement
  # GDPR Article 20 - Data Portability Requests
  class ExportRequest < ApplicationRecord
    # Table name handled by Data.table_name_prefix

    # Associations
    belongs_to :user
    belongs_to :account
    belongs_to :requested_by, class_name: "User", optional: true

    # Validations
    validates :status, presence: true, inclusion: {
      in: %w[pending processing completed failed expired]
    }
    validates :format, presence: true, inclusion: {
      in: %w[json csv zip]
    }
    validates :export_type, inclusion: { in: %w[full partial] }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :processing, -> { where(status: "processing") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :expired, -> { where(status: "expired").or(where("expires_at < ?", Time.current)) }
    scope :downloadable, -> { completed.where("download_token_expires_at > ?", Time.current) }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_create :set_defaults
    after_create :log_export_requested

    # Available data types for export
    EXPORTABLE_DATA_TYPES = %w[
      profile
      activity
      audit_logs
      payments
      invoices
      subscriptions
      files
      settings
      consents
      communications
    ].freeze

    # Status query methods
    def pending?
      status == "pending"
    end

    def processing?
      status == "processing"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def expired?
      status == "expired"
    end

    # Instance methods
    def start_processing!
      update!(
        status: "processing",
        processing_started_at: Time.current
      )
    end

    def complete!(file_path:, file_size_bytes:)
      update!(
        status: "completed",
        file_path: file_path,
        file_size_bytes: file_size_bytes,
        completed_at: Time.current,
        download_token: generate_download_token,
        download_token_expires_at: 7.days.from_now,
        expires_at: 30.days.from_now
      )

      log_export_completed
    end

    def fail!(error_message)
      update!(
        status: "failed",
        error_message: error_message,
        completed_at: Time.current
      )

      log_export_failed
    end

    def expire!
      update!(status: "expired")
      cleanup_file!
    end

    def downloadable?
      status == "completed" &&
        download_token.present? &&
        download_token_expires_at > Time.current &&
        file_exists?
    end

    def record_download!
      update!(downloaded_at: Time.current)

      AuditLog.log_compliance_event(
        action: "data_export",
        resource: self,
        user: user,
        account: account,
        metadata: { event_type: "export_downloaded" }
      )
    end

    def file_exists?
      file_path.present? && File.exist?(file_path)
    end

    def cleanup_file!
      return unless file_path.present? && File.exist?(file_path)

      File.delete(file_path)
      update!(file_path: nil)
    end

    def regenerate_download_token!
      update!(
        download_token: generate_download_token,
        download_token_expires_at: 7.days.from_now
      )
    end

    def time_remaining
      return nil unless status == "pending" || status == "processing"
      return nil unless created_at

      # Estimate based on typical processing time
      estimated_completion = created_at + 1.hour
      [estimated_completion - Time.current, 0].max
    end

    private

    def set_defaults
      self.status ||= "pending"
      self.format ||= "json"
      self.export_type ||= "full"
      self.include_data_types = EXPORTABLE_DATA_TYPES if include_data_types.blank? && export_type == "full"
      self.requested_by ||= user
    end

    def generate_download_token
      SecureRandom.urlsafe_base64(32)
    end

    def log_export_requested
      AuditLog.log_compliance_event(
        action: "data_export",
        resource: self,
        user: requested_by || user,
        account: account,
        metadata: {
          event_type: "export_requested",
          format: format,
          export_type: export_type
        }
      )
    end

    def log_export_completed
      AuditLog.log_compliance_event(
        action: "data_export",
        resource: self,
        user: user,
        account: account,
        metadata: {
          event_type: "export_completed",
          file_size_bytes: file_size_bytes
        }
      )
    end

    def log_export_failed
      AuditLog.log_compliance_event(
        action: "data_export",
        resource: self,
        user: user,
        account: account,
        metadata: {
          event_type: "export_failed",
          error: error_message
        }
      )
    end
  end
end

# Backwards compatibility alias
