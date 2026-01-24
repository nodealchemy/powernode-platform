# frozen_string_literal: true

# Manages account closure with grace period workflow
class Account::Termination < ApplicationRecord
    self.table_name = "account_terminations"

    # Default grace period before permanent deletion
    DEFAULT_GRACE_PERIOD_DAYS = 30

    # Associations
    belongs_to :account
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :cancelled_by, class_name: "User", optional: true
    belongs_to :processed_by, class_name: "User", optional: true
    belongs_to :data_export_request, class_name: "DataManagement::ExportRequest", optional: true

    # Validations
    validates :status, presence: true, inclusion: {
      in: %w[pending grace_period processing completed cancelled]
    }
    validates :requested_at, presence: true
    validates :grace_period_ends_at, presence: true

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :in_grace_period, -> { where(status: "grace_period") }
    scope :processing, -> { where(status: "processing") }
    scope :completed, -> { where(status: "completed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :active, -> { where(status: %w[pending grace_period processing]) }
    scope :grace_period_expired, -> { where("grace_period_ends_at < ?", Time.current) }
    scope :ready_for_processing, -> { in_grace_period.grace_period_expired }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :set_defaults, on: :create
    after_create :log_termination_requested
    after_create :notify_account_users
    after_update :handle_status_change

    # Class methods
    def self.initiate(account:, requested_by:, reason: nil, request_data_export: false)
      # Check for existing active termination
      existing = active.find_by(account: account)
      return existing if existing

      termination = create!(
        account: account,
        requested_by: requested_by,
        reason: reason,
        data_export_requested: request_data_export
      )

      # Create data export if requested
      if request_data_export && account.owner
        export_request = DataManagement::ExportRequest.create!(
          user: account.owner,
          account: account,
          requested_by: requested_by,
          export_type: "full"
        )
        termination.update!(data_export_request: export_request)
      end

      termination
    end

    # Instance methods
    def confirm!
      return false unless status == "pending"

      update!(
        status: "grace_period",
        termination_log: termination_log + [{ event: "confirmed", at: Time.current.iso8601 }]
      )

      log_status_change("confirmed")
      schedule_reminders
      true
    end

    def cancel!(user, reason = nil)
      return false unless can_be_cancelled?

      update!(
        status: "cancelled",
        cancelled_by: user,
        cancelled_at: Time.current,
        cancellation_reason: reason,
        termination_log: termination_log + [{ event: "cancelled", by: user.id, reason: reason, at: Time.current.iso8601 }]
      )

      # Reactivate account
      account.update!(status: "active") if account.status == "terminating"

      log_status_change("cancelled")
      notify_cancellation
      true
    end

    def start_processing!
      return false unless can_start_processing?

      update!(
        status: "processing",
        processing_started_at: Time.current,
        termination_log: termination_log + [{ event: "processing_started", at: Time.current.iso8601 }]
      )

      log_status_change("processing")
      true
    end

    def complete!(processor = nil)
      update!(
        status: "completed",
        processed_by: processor,
        completed_at: Time.current,
        termination_log: termination_log + [{ event: "completed", by: processor&.id, at: Time.current.iso8601 }]
      )

      # Mark account as terminated
      account.update!(status: "terminated", terminated_at: Time.current)

      log_status_change("completed")
      notify_completion
      true
    end

    def submit_feedback!(feedback_text)
      update!(
        feedback_submitted: true,
        feedback: feedback_text,
        termination_log: termination_log + [{ event: "feedback_submitted", at: Time.current.iso8601 }]
      )
    end

    def can_be_cancelled?
      %w[pending grace_period].include?(status)
    end

    def can_start_processing?
      status == "grace_period" && grace_period_ends_at <= Time.current
    end

    def in_grace_period?
      status == "grace_period" && grace_period_ends_at > Time.current
    end

    def days_remaining
      return nil unless in_grace_period?

      ((grace_period_ends_at - Time.current) / 1.day).ceil
    end

    def grace_period_percentage
      return 100 unless in_grace_period?

      total_period = grace_period_ends_at - requested_at
      elapsed = Time.current - requested_at
      ((elapsed / total_period) * 100).round(1)
    end

    private

    def set_defaults
      self.status ||= "pending"
      self.requested_at ||= Time.current
      self.grace_period_ends_at ||= DEFAULT_GRACE_PERIOD_DAYS.days.from_now
      self.termination_log ||= [{ event: "requested", at: Time.current.iso8601 }]
    end

    def log_termination_requested
      AuditLog.log_compliance_event(
        action: "gdpr_request",
        resource: self,
        user: requested_by,
        account: account,
        severity: "high",
        metadata: {
          event_type: "account_termination_requested",
          reason: reason,
          grace_period_ends_at: grace_period_ends_at
        }
      )
    end

    def log_status_change(event)
      AuditLog.log_compliance_event(
        action: "gdpr_request",
        resource: self,
        user: processed_by || cancelled_by || requested_by,
        account: account,
        metadata: {
          event_type: "account_termination_#{event}",
          status: status
        }
      )
    end

    def handle_status_change
      return unless saved_change_to_status?

      case status
      when "grace_period"
        account.update!(status: "terminating")
      when "cancelled"
        account.update!(status: "active")
      end
    end

    def notify_account_users
      return unless account

      # Create in-app notifications for all account users
      account.users.active.find_each do |user|
        Notification.create(
          user: user,
          account: account,
          message: "Account termination has been requested. The account will be permanently deleted on #{grace_period_ends_at.strftime('%B %d, %Y')}.",
          notification_type: "account_termination",
          metadata: {
            termination_id: id,
            event: "termination_requested",
            grace_period_ends_at: grace_period_ends_at.iso8601
          }
        )
      end

      # Queue email notifications
      NotificationService.send_email(
        template: "account_termination_requested",
        account_id: account.id,
        data: {
          termination_id: id,
          grace_period_ends_at: grace_period_ends_at.iso8601,
          days_remaining: DEFAULT_GRACE_PERIOD_DAYS,
          reason: reason,
          requested_by: requested_by&.name || "Account owner"
        }
      )
    end

    def notify_cancellation
      return unless account

      # Create in-app notifications for all account users
      account.users.active.find_each do |user|
        Notification.create(
          user: user,
          account: account,
          message: "Account termination has been cancelled. Your account is now active.",
          notification_type: "account_termination",
          metadata: {
            termination_id: id,
            event: "termination_cancelled"
          }
        )
      end

      # Queue email notification
      NotificationService.send_email(
        template: "account_termination_cancelled",
        account_id: account.id,
        data: {
          termination_id: id,
          cancelled_at: cancelled_at&.iso8601,
          cancelled_by: cancelled_by&.name || "Administrator",
          cancellation_reason: cancellation_reason
        }
      )
    end

    def notify_completion
      return unless account

      # Final completion email - account data has been deleted
      # Note: We send to the owner's original email captured before termination
      owner_email = account.owner&.email
      return unless owner_email

      NotificationService.send_email(
        template: "account_termination_complete",
        email: owner_email,
        data: {
          termination_id: id,
          completed_at: completed_at&.iso8601,
          account_name: account.name
        }
      )
    end

    def schedule_reminders
      return unless grace_period_ends_at

      # Schedule reminders at 7, 3, and 1 days before termination
      [7, 3, 1].each do |days_before|
        reminder_time = grace_period_ends_at - days_before.days

        # Only schedule if the reminder time is in the future
        next unless reminder_time > Time.current

        # Store reminder schedule in termination log for tracking
        # The AccountTerminationJob will check these and send reminders
        update_column(:termination_log,
          termination_log + [{
            event: "reminder_scheduled",
            days_before: days_before,
            scheduled_for: reminder_time.iso8601,
            at: Time.current.iso8601
          }]
        )
      end
    end
end
