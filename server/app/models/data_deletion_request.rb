# frozen_string_literal: true

# GDPR Article 17 - Right to Erasure Requests
class DataDeletionRequest < ApplicationRecord
  # Default grace period before permanent deletion
  GRACE_PERIOD_DAYS = 30

  # Associations
  belongs_to :user
  belongs_to :account
  belongs_to :requested_by, class_name: 'User', optional: true
  belongs_to :processed_by, class_name: 'User', optional: true

  # Validations
  validates :status, presence: true, inclusion: {
    in: %w[pending approved processing completed rejected cancelled]
  }
  validates :deletion_type, presence: true, inclusion: {
    in: %w[full partial anonymize]
  }

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :processing, -> { where(status: 'processing') }
  scope :completed, -> { where(status: 'completed') }
  scope :active, -> { where(status: %w[pending approved processing]) }
  scope :grace_period_expired, -> { where('grace_period_ends_at < ?', Time.current) }
  scope :ready_for_processing, -> { approved.grace_period_expired }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_create :set_defaults
  after_create :log_deletion_requested

  # Data types that can be deleted
  DELETABLE_DATA_TYPES = %w[
    profile
    activity
    audit_logs
    payments
    files
    settings
    consents
    communications
    analytics
  ].freeze

  # Data types that must be retained for legal reasons
  LEGALLY_RETAINED_DATA_TYPES = %w[
    financial_records
    tax_documents
    legal_agreements
  ].freeze

  # Instance methods
  def approve!(processor)
    update!(
      status: 'approved',
      processed_by: processor,
      approved_at: Time.current,
      grace_period_ends_at: GRACE_PERIOD_DAYS.days.from_now
    )

    log_status_change('approved')
    notify_user_of_approval
  end

  def reject!(processor, reason)
    update!(
      status: 'rejected',
      processed_by: processor,
      rejection_reason: reason,
      completed_at: Time.current
    )

    log_status_change('rejected')
    notify_user_of_rejection
  end

  def cancel!(canceller = nil, reason = nil)
    return false unless can_be_cancelled?

    update!(
      status: 'cancelled',
      processed_by: canceller,
      cancellation_reason: reason,
      completed_at: Time.current
    )

    log_status_change('cancelled')
    true
  end

  def start_processing!
    return false unless can_start_processing?

    update!(
      status: 'processing',
      processing_started_at: Time.current
    )

    log_status_change('processing')
    true
  end

  def complete!(deletion_log:, retention_log: [])
    update!(
      status: 'completed',
      completed_at: Time.current,
      deletion_log: deletion_log,
      retention_log: retention_log
    )

    log_status_change('completed')
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

  def can_start_processing?
    status == 'approved' && grace_period_ends_at <= Time.current
  end

  def in_grace_period?
    status == 'approved' && grace_period_ends_at > Time.current
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

  def set_defaults
    self.status ||= 'pending'
    self.deletion_type ||= 'full'
    self.requested_by ||= user
    self.data_types_to_retain ||= LEGALLY_RETAINED_DATA_TYPES
  end

  def log_deletion_requested
    AuditLog.log_compliance_event(
      action: 'data_deletion',
      resource: self,
      user: requested_by || user,
      account: account,
      metadata: {
        event_type: 'deletion_requested',
        deletion_type: deletion_type,
        reason: reason
      }
    )
  end

  def log_status_change(new_status)
    AuditLog.log_compliance_event(
      action: 'data_deletion',
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
      action: 'data_deletion',
      resource: self,
      user: user,
      account: account,
      severity: 'high',
      metadata: {
        event_type: 'deletion_error',
        error: error_message
      }
    )
  end

  def log_grace_period_extended(days)
    AuditLog.log_compliance_event(
      action: 'data_deletion',
      resource: self,
      user: user,
      account: account,
      metadata: {
        event_type: 'grace_period_extended',
        extension_days: days,
        new_end_date: grace_period_ends_at
      }
    )
  end

  def notify_user_of_approval
    # TODO: Implement notification
  end

  def notify_user_of_rejection
    # TODO: Implement notification
  end

  def notify_user_of_completion
    # TODO: Implement notification
  end
end
