class EmailDelivery < ApplicationRecord
  include AASM

  # Associations
  belongs_to :account, optional: true
  belongs_to :user, optional: true

  # Validations
  validates :recipient_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :subject, presence: true
  validates :email_type, presence: true, inclusion: {
    in: %w[
      password_reset
      email_verification
      welcome_email
      subscription_created
      subscription_cancelled
      payment_succeeded
      payment_failed
      invoice_generated
      trial_ending
      dunning_notification
      report_generated
      system_notification
    ]
  }
  validates :status, presence: true, inclusion: {
    in: %w[pending sent failed retry]
  }

  # Serialization
  serialize :template_data, coder: JSON

  # Scopes
  scope :sent, -> { where(status: 'sent') }
  scope :failed, -> { where(status: 'failed') }
  scope :pending, -> { where(status: 'pending') }
  scope :by_email_type, ->(type) { where(email_type: type) }
  scope :by_recipient, ->(email) { where(recipient_email: email) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_create :set_defaults

  # State Machine
  aasm column: :status do
    state :pending, initial: true
    state :sent
    state :failed
    state :retry

    event :mark_sent do
      transitions from: [:pending, :retry], to: :sent
    end

    event :mark_failed do
      transitions from: [:pending, :retry, :sent], to: :failed
    end

    event :mark_retry do
      transitions from: :failed, to: :retry
    end
  end

  # Instance methods
  def parsed_template_data
    template_data || {}
  end

  def can_retry?
    failed? && retry_count < 3
  end

  def increment_retry_count!
    increment!(:retry_count)
  end

  def record_sent!(message_id = nil)
    update!(
      status: 'sent',
      message_id: message_id,
      sent_at: Time.current,
      error_message: nil
    )
  end

  def record_failure!(error_message)
    update!(
      status: 'failed',
      failed_at: Time.current,
      error_message: error_message
    )
  end

  def delivery_time
    return nil unless sent_at && created_at
    
    (sent_at - created_at).round(2)
  end

  # Class methods
  class << self
    def delivery_stats(account: nil, days: 7)
      scope = account ? account.email_deliveries : all
      scope = scope.where('created_at >= ?', days.days.ago)

      {
        total: scope.count,
        sent: scope.sent.count,
        failed: scope.failed.count,
        pending: scope.pending.count,
        success_rate: scope.count > 0 ? (scope.sent.count.to_f / scope.count * 100).round(2) : 0,
        avg_delivery_time: scope.sent.where.not(sent_at: nil)
                               .average("EXTRACT(EPOCH FROM (sent_at - created_at))") || 0
      }
    end

    def cleanup_old_deliveries(days_old = 90)
      where('created_at < ?', days_old.days_ago).delete_all
    end

    def retry_failed_deliveries(max_retries = 3)
      failed.where('retry_count < ?', max_retries).find_each(&:mark_retry!)
    end
  end

  private

  def set_defaults
    self.retry_count ||= 0
    self.template_data ||= {}
  end
end