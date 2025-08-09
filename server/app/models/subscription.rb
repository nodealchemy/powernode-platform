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
end
