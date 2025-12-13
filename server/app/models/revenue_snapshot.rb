# frozen_string_literal: true

class RevenueSnapshot < ApplicationRecord
  belongs_to :account, optional: true

  validates :snapshot_date, presence: true
  validates :mrr_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :arr_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Ensure uniqueness of snapshot per account/date
  validates :snapshot_date, uniqueness: { scope: [ :account_id ] }

  # Alias for backwards compatibility
  alias_attribute :date, :snapshot_date

  # Money handling
  monetize :mrr_cents
  monetize :arr_cents

  # Note: metadata is a native JSON column - no serialization needed in Rails 8

  # Scopes
  scope :for_account, ->(account) { where(account: account) }
  scope :global, -> { where(account: nil) }
  scope :in_date_range, ->(start_date, end_date) { where(snapshot_date: start_date..end_date) }
  scope :recent, ->(limit = 12) { order(snapshot_date: :desc).limit(limit) }
  scope :monthly, -> { self } # All snapshots are considered monthly for now
  scope :yearly, -> { self } # All snapshots are considered yearly for now

  # Callbacks
  after_initialize :set_defaults
  before_save :calculate_derived_metrics

  # Class methods
  def self.latest_for_account(account, period_type = "monthly")
    for_account(account).order(snapshot_date: :desc).first
  end

  def self.latest_global(period_type = "monthly")
    global.order(snapshot_date: :desc).first
  end

  def self.growth_between_periods(account, period_type, start_date, end_date)
    snapshots = for_account(account).in_date_range(start_date, end_date).order(:snapshot_date)
    return 0.0 if snapshots.count < 2

    first_snapshot = snapshots.first
    last_snapshot = snapshots.last

    return 0.0 if first_snapshot.mrr_cents == 0

    ((last_snapshot.mrr_cents - first_snapshot.mrr_cents) / first_snapshot.mrr_cents.to_f) * 100
  end

  # Instance methods
  def global?
    account_id.nil?
  end

  def account_specific?
    !global?
  end

  def mrr
    Money.new(mrr_cents, "USD")
  end

  def arr
    Money.new(arr_cents, "USD")
  end

  def arpu
    Money.new(arpu_cents, "USD")
  end

  def ltv
    Money.new(ltv_cents, "USD")
  end

  def ltv_cents
    arpu_cents * 24 # Simple LTV calculation: 2 years of ARPU
  end

  def growth_rate_percentage
    get_metadata("growth_rate") || 0.0
  end

  def customer_churn_rate_percentage
    get_metadata("customer_churn_rate") || 0.0
  end

  def revenue_churn_rate_percentage
    get_metadata("revenue_churn_rate") || 0.0
  end

  def net_new_subscriptions
    new_subscriptions - churned_subscriptions
  end

  def arpu_cents
    return 0 if active_subscriptions == 0
    mrr_cents / active_subscriptions
  end

  def total_customers_count
    get_metadata("total_customers_count") || active_subscriptions # Simplified - assuming 1 customer per subscription
  end

  def new_subscriptions_count
    new_subscriptions
  end

  def churned_subscriptions_count
    churned_subscriptions
  end

  def active_subscriptions_count
    active_subscriptions
  end

  def churned_customers_count
    get_metadata("churned_customers_count") || churned_subscriptions # Simplified - assuming 1 customer per subscription
  end

  def new_customers_count
    get_metadata("new_customers_count") || new_subscriptions # Simplified - assuming 1 customer per subscription
  end

  def add_metadata(key, value)
    current_metadata = metadata || {}
    current_metadata[key.to_s] = value
    self.metadata = current_metadata
  end

  def get_metadata(key)
    (metadata || {})[key.to_s]
  end

  private

  def set_defaults
    self.metadata ||= {}
    self.snapshot_date ||= Date.current if new_record?
  end

  def calculate_derived_metrics
    # Calculate ARR from MRR
    self.arr_cents = mrr_cents * 12
  end
end
