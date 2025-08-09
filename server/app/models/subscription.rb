class Subscription < ApplicationRecord
  include AASM

  # Associations
  belongs_to :account
  belongs_to :plan
  has_many :invoices, dependent: :destroy
  has_many :payments, through: :invoices

  # Validations
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :account, presence: true, uniqueness: { message: "can only have one subscription" }
  validates :stripe_subscription_id, uniqueness: { allow_nil: true }
  validates :paypal_subscription_id, uniqueness: { allow_nil: true }

  # Serialization
  serialize :metadata, coder: JSON

  # Scopes
  scope :active, -> { where(status: [ "trialing", "active" ]) }
  scope :inactive, -> { where(status: [ "canceled", "unpaid", "incomplete_expired" ]) }
  scope :past_due, -> { where(status: "past_due") }
  scope :trialing, -> { where(status: "trialing") }
  scope :expiring_soon, -> { where(current_period_end: Time.current..7.days.from_now) }
  scope :trial_ending_soon, -> { where(trial_end: Time.current..3.days.from_now) }

  # Callbacks
  before_create :set_trial_period
  after_initialize :set_defaults
  after_create :schedule_lifecycle_events
  after_update :handle_status_changes, if: :saved_change_to_status?

  # State Machine
  aasm column: :status do
    state :trialing, initial: true
    state :active
    state :past_due
    state :canceled
    state :unpaid
    state :incomplete
    state :incomplete_expired
    state :paused

    event :activate do
      transitions from: [ :trialing, :past_due, :unpaid, :paused ], to: :active
      after do
        update_period_dates
      end
    end

    event :mark_past_due do
      transitions from: [ :active, :trialing ], to: :past_due
    end

    event :cancel do
      transitions from: [ :trialing, :active, :past_due, :unpaid, :paused ], to: :canceled
      after do
        self.canceled_at = Time.current
        self.ended_at = Time.current unless ended_at.present?
      end
    end

    event :mark_unpaid do
      transitions from: [ :active, :past_due ], to: :unpaid
    end

    event :pause do
      transitions from: [ :active, :trialing ], to: :paused
    end

    event :resume do
      transitions from: :paused, to: :active
    end

    event :expire do
      transitions from: [ :incomplete, :past_due, :unpaid ], to: :incomplete_expired
      after do
        self.ended_at = Time.current
      end
    end
  end

  # Instance methods
  def active?
    %w[trialing active].include?(status)
  end

  def on_trial?
    status == "trialing" && trial_end.present? && trial_end > Time.current
  end

  def trial_ended?
    trial_end.present? && trial_end <= Time.current
  end

  def days_until_trial_ends
    return 0 unless on_trial?
    ((trial_end - Time.current) / 1.day).ceil
  end

  def days_until_period_ends
    return 0 unless current_period_end
    ((current_period_end - Time.current) / 1.day).ceil
  end

  def total_price
    plan.price_cents * quantity
  end

  def next_billing_date
    return trial_end if on_trial?
    current_period_end
  end

  def can_be_canceled?
    !%w[canceled incomplete_expired].include?(status)
  end

  def using_stripe?
    stripe_subscription_id.present?
  end

  def using_paypal?
    paypal_subscription_id.present?
  end

  def payment_provider
    return "stripe" if using_stripe?
    return "paypal" if using_paypal?
    "none"
  end

  def needs_payment_retry?
    past_due? || unpaid?
  end

  def in_grace_period?
    return false unless past_due?
    grace_end = metadata['payment_method_grace_period_end']
    grace_end.present? && Time.parse(grace_end) > Time.current
  end

  def overdue_days
    return 0 unless current_period_end && current_period_end < Time.current
    ((Time.current - current_period_end) / 1.day).ceil
  end

  def schedule_billing_automation(delay: 0)
    return if canceled? || incomplete_expired?
    BillingAutomationJob.set(wait: delay.seconds).perform_later(id)
  end

  private

  def set_trial_period
    if plan.trial_days > 0 && trial_end.blank?
      self.trial_end = plan.trial_days.days.from_now
      self.current_period_start = Time.current
      self.current_period_end = trial_end
    end
  end

  def set_defaults
    self.metadata ||= {}
  end

  def update_period_dates
    now = Time.current
    self.current_period_start = now

    case plan.billing_cycle
    when "monthly"
      self.current_period_end = now + 1.month
    when "quarterly"
      self.current_period_end = now + 3.months
    when "yearly"
      self.current_period_end = now + 1.year
    end
  end

  def schedule_lifecycle_events
    return unless persisted?
    
    # Schedule trial ending reminders if on trial
    if trialing? && trial_end.present?
      schedule_trial_reminders
    end
    
    # Schedule renewal reminders if active
    if active? && current_period_end.present?
      schedule_renewal_reminders
    end
  end

  def handle_status_changes
    case status
    when 'active'
      handle_activation
    when 'past_due'
      handle_past_due
    when 'unpaid'
      handle_unpaid_status
    when 'canceled'
      handle_cancellation
    end
  end

  def schedule_trial_reminders
    return unless trial_end.present? && trial_end > Time.current

    # Schedule reminders for 7, 3, and 1 days before trial ends
    [7, 3, 1].each do |days_before|
      reminder_time = trial_end - days_before.days
      next if reminder_time <= Time.current

      SubscriptionLifecycleJob.set(wait_until: reminder_time)
                             .perform_later('trial_ending_reminder', id)
    end

    # Schedule trial conversion
    SubscriptionLifecycleJob.set(wait_until: trial_end)
                           .perform_later('trial_ended', id)
  end

  def schedule_renewal_reminders
    return unless current_period_end.present? && current_period_end > Time.current

    # Schedule reminders for 7, 3, and 1 days before renewal
    [7, 3, 1].each do |days_before|
      reminder_time = current_period_end - days_before.days
      next if reminder_time <= Time.current

      SubscriptionLifecycleJob.set(wait_until: reminder_time)
                             .perform_later('renewal_reminder', id)
    end

    # Schedule billing automation
    BillingAutomationJob.set(wait_until: current_period_end)
                       .perform_later(id)
  end

  def handle_activation
    Rails.logger.info "Subscription #{id} activated"
    
    # Schedule renewal reminders
    schedule_renewal_reminders if current_period_end.present?
    
    # Clear any dunning metadata
    if metadata['dunning_level'].present?
      self.update_columns(
        metadata: metadata.except('dunning_level', 'last_dunning_attempt')
      )
    end
  end

  def handle_past_due
    Rails.logger.info "Subscription #{id} marked as past due"
    
    # Update metadata with dunning information
    self.update_columns(
      metadata: metadata.merge(
        'dunning_level' => 'soft_dunning',
        'past_due_since' => Time.current.iso8601
      )
    )
  end

  def handle_unpaid_status
    Rails.logger.info "Subscription #{id} marked as unpaid"
    
    # Update metadata
    self.update_columns(
      metadata: metadata.merge(
        'dunning_level' => 'final_dunning',
        'unpaid_since' => Time.current.iso8601
      )
    )
  end

  def handle_cancellation
    Rails.logger.info "Subscription #{id} canceled"
    
    # Clear any scheduled jobs related to this subscription
    # Note: In a real implementation, you'd want to cancel specific scheduled jobs
    # This is a simplified approach
  end
end
