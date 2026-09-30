# frozen_string_literal: true

module DataManagement
  # GDPR Article 17 - Right to Erasure Requests
  class DeletionRequest < ApplicationRecord
    # Table name handled by Data.table_name_prefix

    # Default grace period before permanent deletion
    GRACE_PERIOD_DAYS = 30

    # Associations
    belongs_to :user
    belongs_to :account
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :processed_by, class_name: "User", optional: true

    # Validations
    #
    # 'failed' added (IMP-b33a3ecca331): Compliance::DataDeletionJob sets this
    # status on both a partial per-data-type erasure failure and an
    # unrecoverable processing error — the terminal, non-'processing' outcome
    # a stuck request needs so a Sidekiq retry can tell "still running" from
    # "done, unsuccessfully" instead of resuming forever. It was missing here,
    # so every one of the job's `status: 'failed'` writes was itself rejected
    # by this validation (422), on top of the params-contract bug that was
    # separately dropping the write.
    validates :status, presence: true, inclusion: {
      in: %w[pending approved processing completed failed rejected cancelled]
    }
    validates :deletion_type, presence: true, inclusion: {
      in: %w[full partial anonymize]
    }

    # Withdrawing a type from DELETABLE_DATA_TYPES is inert on its own —
    # nothing read the constant, and Api::V1::PrivacyController
    # #request_deletion permits an arbitrary `data_types_to_delete` array — so
    # a caller could still ask for 'analytics' and be told the request was
    # accepted. This is what makes the advertisement binding
    # (IMP-bf52b4da135b).
    #
    # `on: :create` deliberately. Compliance::DataDeletionJob PATCHes a
    # request repeatedly while processing it (status, deletion_log,
    # retention_log — #patch_deletion_request!), and rows created before the
    # withdrawal legitimately still carry 'activity'/'analytics'. Validating
    # on update would 422 every one of those writes and strand the request
    # mid-flight — precisely the failure mode IMP-b33a3ecca331 had to repair
    # when the status validation was rejecting the job's own writes.
    #
    # CAVEAT for anyone extending this: create-only is sufficient ONLY while
    # no update path permits `data_types_to_delete`. That holds today — the
    # internal controller's update params don't carry the field at all, so a
    # post-create change is structurally impossible rather than merely
    # unused. Add an update action that permits it and this validation is
    # bypassed SILENTLY, with no failing spec to notice; such a change needs
    # a matching `on: :update` guard that exempts the legacy values.
    validate :data_types_to_delete_are_deletable, on: :create

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :approved, -> { where(status: "approved") }
    scope :processing, -> { where(status: "processing") }
    scope :completed, -> { where(status: "completed") }
    scope :active, -> { where(status: %w[pending approved processing]) }
    scope :grace_period_expired, -> { where("grace_period_ends_at < ?", Time.current) }
    scope :ready_for_processing, -> { approved.grace_period_expired }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_create :set_defaults
    after_create :log_deletion_requested

    # Data types that can be deleted.
    #
    # This constant is the platform's ADVERTISEMENT of which GDPR Article 17
    # categories a data subject can actually have erased, so every entry must
    # have a real erasure backend behind it (IMP-bf52b4da135b, operator
    # direction: a type with no backend is withdrawn, not left listed):
    #
    #   profile        -> User row, anonymize-in-place
    #                     (Api::V1::Internal::UsersController#anonymize)
    #   audit_logs     -> AuditLog, anonymized in place (#anonymize_audit_logs)
    #   payments       -> account payments, anonymized in place
    #                     (Api::V1::Internal::AccountsController#anonymize_payments)
    #   settings       -> users.preferences / users.notification_preferences
    #                     (#delete_settings)
    #   consents       -> UserConsent (#delete_consents)
    #   communications -> Notification + EmailDelivery (#delete_communications)
    #
    # THREE types were WITHDRAWN (IMP-bf52b4da135b). Withdrawal means the
    # platform stops OFFERING a category it has no erasure path for — it is
    # not a claim that the underlying data does not exist:
    #
    #   files    -> FileManagement::Object exists and holds real personal
    #               data, but there is no correct erasure path for it yet and
    #               building one is its own piece of work. Five tables
    #               reference file_objects with no inverse association and no
    #               `on_delete` (chat_message_attachments,
    #               system_disk_image_publications x2,
    #               system_node_architectures x3), so they default to NO
    #               ACTION and a destroy raises InvalidForeignKey on any
    #               chat-attached file; FileManagement::Object's
    #               after_destroy :remove_from_storage swallows a blob-removal
    #               failure, so a naive implementation reports erasure it did
    #               not perform; and the same scope holds non-personal
    #               platform artifacts (disk_image, sbom_export,
    #               attestation_proof, vendor_certificate, ...) that must not
    #               be swept up by a data-subject request. Previously this was
    #               ADVERTISED AND INERT — Api::V1::Internal::AccountsController
    #               #delete_files is gated on `@account.respond_to?(:files)`
    #               and Account has no such association, so it always reported
    #               "Deleted 0 file records". Withdrawing makes the
    #               advertisement honest until the real implementation lands.
    #
    #   activity, analytics
    #            -> no CATEGORY-LEVEL erasure path was ever built for either,
    #               and no model in core is scoped to either category. Note
    #               this is NOT "no user-associated activity data exists": it
    #               plainly does — Devops::DockerActivity (belongs_to
    #               :triggered_by, class_name: "User"), McpToolExecution,
    #               Ai::AgentExecution, Ai::Conversation, Ai::Message,
    #               Ai::RagQuery, Ai::ContextAccessLog and
    #               KnowledgeBase::ArticleView are all user-associated and
    #               activity/analytics-shaped, and nothing erases any of them.
    #               Deciding which of those constitute a data subject's
    #               "activity" for Article 17 purposes is a policy question
    #               that has not been answered, so the category must not be
    #               offered as though it had been. (WorkerActivity is the one
    #               genuine exception: it belongs_to :worker only.)
    DELETABLE_DATA_TYPES = %w[
      profile
      audit_logs
      payments
      settings
      consents
      communications
    ].freeze

    # Data types that must be retained for legal reasons
    LEGALLY_RETAINED_DATA_TYPES = %w[
      financial_records
      tax_documents
      legal_agreements
    ].freeze

    # Status query methods
    def pending?
      status == "pending"
    end

    def approved?
      status == "approved"
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

    def rejected?
      status == "rejected"
    end

    def cancelled?
      status == "cancelled"
    end

    # Instance methods
    def approve!(processor)
      update!(
        status: "approved",
        processed_by: processor,
        approved_at: Time.current,
        grace_period_ends_at: GRACE_PERIOD_DAYS.days.from_now
      )

      log_status_change("approved")
      notify_user_of_approval
    end

    def reject!(processor, reason)
      update!(
        status: "rejected",
        processed_by: processor,
        rejection_reason: reason,
        completed_at: Time.current
      )

      log_status_change("rejected")
      notify_user_of_rejection
    end

    def cancel!(canceller = nil, reason = nil)
      return false unless can_be_cancelled?

      update!(
        status: "cancelled",
        processed_by: canceller,
        cancellation_reason: reason,
        completed_at: Time.current
      )

      log_status_change("cancelled")
      true
    end

    # The ONLY way a request enters 'processing' (the admin run-now and the
    # worker's status PATCH both call it). Returns false — leaving the row
    # untouched — when #can_start_processing? does not hold. The check is
    # re-run against the freshly locked row, so of any number of concurrent
    # starters exactly one sees 'approved' and wins; the rest see
    # 'processing' and get false (IMP-26adf1c79c7a).
    def start_processing!
      started = with_lock do
        next false unless can_start_processing?

        update!(
          status: "processing",
          processing_started_at: Time.current
        )
        true
      end

      log_status_change("processing") if started
      started
    end

    def complete!(deletion_log:, retention_log: [])
      update!(
        status: "completed",
        completed_at: Time.current,
        deletion_log: deletion_log,
        retention_log: retention_log
      )

      log_status_change("completed")
      notify_user_of_completion
    end

    def fail!(error_message)
      # Don't change status, just log the error for retry
      self.error_message = error_message
      save!

      log_processing_error
    end

    def extend_grace_period!(days = 14)
      return false unless in_grace_period?

      update!(
        grace_period_ends_at: grace_period_ends_at + days.days,
        grace_period_extended: true
      )

      log_grace_period_extended(days)
      true
    end

    def can_be_cancelled?
      %w[pending approved].include?(status)
    end

    # The grace period is the data subject's cancellation window: processing
    # may start only once it has verifiably ended. A blank end date fails
    # CLOSED — an unknown end is not an ended grace period.
    def can_start_processing?
      approved? && grace_period_ends_at.present? && grace_period_ends_at <= Time.current
    end

    def in_grace_period?
      status == "approved" && grace_period_ends_at > Time.current
    end

    def grace_period_remaining
      return nil unless in_grace_period?

      (grace_period_ends_at - Time.current).to_i
    end

    def days_until_deletion
      return nil unless in_grace_period?

      ((grace_period_ends_at - Time.current) / 1.day).ceil
    end

    private

    def data_types_to_delete_are_deletable
      unsupported = Array(data_types_to_delete) - DELETABLE_DATA_TYPES
      return if unsupported.empty?

      errors.add(
        :data_types_to_delete,
        "contains data types this platform cannot erase: #{unsupported.join(', ')}"
      )
    end

    def set_defaults
      self.status ||= "pending"
      self.deletion_type ||= "full"
      self.requested_by ||= user
      self.data_types_to_retain ||= LEGALLY_RETAINED_DATA_TYPES
    end

    def log_deletion_requested
      AuditLog.log_compliance_event(
        action: "data_deletion",
        resource: self,
        user: requested_by || user,
        account: account,
        metadata: {
          event_type: "deletion_requested",
          deletion_type: deletion_type,
          reason: reason
        }
      )
    end

    def log_status_change(new_status)
      AuditLog.log_compliance_event(
        action: "data_deletion",
        resource: self,
        user: processed_by || user,
        account: account,
        metadata: {
          event_type: "deletion_#{new_status}",
          deletion_type: deletion_type
        }
      )
    end

    def log_processing_error
      AuditLog.log_compliance_event(
        action: "data_deletion",
        resource: self,
        user: user,
        account: account,
        severity: "high",
        metadata: {
          event_type: "deletion_error",
          error: error_message
        }
      )
    end

    def log_grace_period_extended(days)
      AuditLog.log_compliance_event(
        action: "data_deletion",
        resource: self,
        user: user,
        account: account,
        metadata: {
          event_type: "grace_period_extended",
          extension_days: days,
          new_end_date: grace_period_ends_at
        }
      )
    end

    def notify_user_of_approval
      return unless user

      # Create in-app notification
      Notification.create(
        user: user,
        account: account,
        message: "Your data deletion request has been approved. Your data will be deleted after the grace period ends on #{grace_period_ends_at.strftime('%B %d, %Y')}.",
        notification_type: "data_deletion",
        metadata: {
          deletion_request_id: id,
          event: "deletion_approved",
          grace_period_ends_at: grace_period_ends_at.iso8601
        }
      )

      # Queue GDPR-compliant email notification
      NotificationService.send_email(
        template: "data_deletion_approved",
        user_id: user.id,
        data: {
          deletion_request_id: id,
          deletion_type: deletion_type,
          grace_period_ends_at: grace_period_ends_at.iso8601,
          days_until_deletion: GRACE_PERIOD_DAYS,
          approved_at: approved_at&.iso8601
        }
      )
    end

    def notify_user_of_rejection
      return unless user

      # Create in-app notification
      Notification.create(
        user: user,
        account: account,
        message: "Your data deletion request has been rejected. Reason: #{rejection_reason}",
        notification_type: "data_deletion",
        metadata: {
          deletion_request_id: id,
          event: "deletion_rejected",
          rejection_reason: rejection_reason
        }
      )

      # Queue email notification
      NotificationService.send_email(
        template: "data_deletion_rejected",
        user_id: user.id,
        data: {
          deletion_request_id: id,
          deletion_type: deletion_type,
          rejection_reason: rejection_reason,
          rejected_at: completed_at&.iso8601
        }
      )
    end

    def notify_user_of_completion
      return unless user

      # User's primary account data may be deleted, but we should still
      # attempt to send the completion notification
      user_email = user.email

      # Create in-app notification if user record still exists and is accessible
      begin
        Notification.create(
          user: user,
          account: account,
          message: "Your data deletion request has been completed. The requested data has been permanently removed.",
          notification_type: "data_deletion",
          metadata: {
            deletion_request_id: id,
            event: "deletion_complete",
            completed_at: completed_at&.iso8601
          }
        )
      rescue StandardError => e
        Rails.logger.warn "Could not create in-app notification for deletion completion: #{e.message}"
      end

      # Queue GDPR-compliant completion email
      NotificationService.send_email(
        template: "data_deletion_complete",
        email: user_email,
        data: {
          deletion_request_id: id,
          deletion_type: deletion_type,
          completed_at: completed_at&.iso8601,
          deletion_log: deletion_log,
          retention_log: retention_log
        }
      )
    end
  end
end
