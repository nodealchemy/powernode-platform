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

    # IMP-0310a1351dab: THE single place that decides whether an export's
    # outcome is settled enough to let its row (and the account behind it,
    # via Api::V1::Internal::AccountsController#delete_data_export_requests)
    # be deleted. Both that endpoint's own scope and the worker's
    # pre-deletion gate (Compliance::AccountTerminationJob
    # #export_ready_for_deletion?, via the field this exposes over the
    # internal API) read this ONE predicate — neither re-derives the rule
    # independently — so a future policy change is a one-method change, not
    # a hunt across two codebases for every place that duplicated it.
    #
    # Operator ruling 2026-09-24: delivered = downloaded, or download window
    # elapsed unused.
    #   (a) downloaded_at present — the user actually retrieved the export.
    #   (b) download_token_expires_at has passed — the 7-day download window
    #       elapsed with nothing downloaded; nothing further can be
    #       delivered, so there is no more reason to keep the row.
    #   (c) status == 'expired' — the explicit terminal state written by
    #       DataExportRequestsController#expire_export, kept as its own
    #       check because that action also clears download_token_expires_at
    #       to nil, so (b) alone would no longer see the elapsed window once
    #       a row has been through that action.
    # A freshly 'completed' export with an OPEN download window and no
    # downloaded_at is deliberately NOT delivered — the whole point of the
    # ruling is that a user gets the full 7 days to retrieve it before its
    # row (and the account behind it) can be removed.
    # 'failed' is deliberately NOT delivered either (this replaces the
    # BLOCKER the review flagged: 'failed' used to count as ready
    # unconditionally) — a failed export has delivered nothing, and
    # Compliance::AccountTerminationJob is responsible for resetting it to
    # 'pending' and re-queuing generation (bounded, then parking the
    # termination) rather than this predicate quietly treating "generation
    # failed" as equivalent to "nothing left to deliver".
    # Timing check (requested by review, confirmed rather than assumed): the
    # export is generated at TERMINATION-REQUEST time (Account::Termination
    # .initiate queues Compliance::DataExportJob immediately), and the
    # deletion sweep only runs once the grace period ends
    # (Compliance::AccountTerminationJob only fetches grace_period_expired
    # terminations) — Account::Termination::DEFAULT_GRACE_PERIOD_DAYS is 30.
    # A completed export's 7-day download_token_expires_at window therefore
    # fits comfortably inside the grace period in the ordinary case (export
    # generation typically completes within ~1 hour of the request — see
    # AccountTerminationJob::EXPORT_STALE_PENDING_THRESHOLD's own comment —
    # so the window opens on day ~0 and closes around day ~7 of a 30-day
    # grace period). It does NOT always fit: an export that completes LATE
    # (e.g. after repeated stale-pending re-queues) can open a window that
    # closes AFTER grace ends. This predicate does not special-case that —
    # it is not supposed to. The gate just keeps deferring until the window
    # actually elapses, however long after grace end that is; the operator
    # has confirmed grace is never shortened to force it, and a termination
    # completing somewhat after its grace period ends is acceptable.
    def delivered_for_deletion?
      downloaded_at.present? ||
        status == "expired" ||
        (download_token_expires_at.present? && download_token_expires_at < Time.current)
    end

    scope :delivered_for_deletion, -> {
      where(
        "downloaded_at IS NOT NULL OR status = ? OR (download_token_expires_at IS NOT NULL AND download_token_expires_at < ?)",
        "expired", Time.current
      )
    }
    scope :undelivered_for_deletion, -> { where.not(id: delivered_for_deletion) }

    # Callbacks
    before_create :set_defaults
    after_create :log_export_requested

    # Available data types for export. `activity` was withdrawn
    # (IMP-8aab38f3ad62): no per-user activity model exists, its endpoint
    # answered an always-empty success, and the per-user trail it would have
    # named (AuditLog) is exported as `audit_logs`.
    EXPORTABLE_DATA_TYPES = %w[
      profile
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

    # Best effort: the path may belong to another host or another uid, and a
    # file this process cannot remove must not fail the request that asked
    # (an account termination's sweep has no path back). The row keeps its
    # path when the delete fails.
    def cleanup_file!
      return unless file_path.present? && File.exist?(file_path)

      File.delete(file_path)
      update!(file_path: nil)
    rescue SystemCallError => e
      Rails.logger.warn("[DataManagement::ExportRequest] could not remove the archive of export #{id}: #{e.class}")
      false
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
      [ estimated_completion - Time.current, 0 ].max
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
