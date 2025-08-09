class RevenueSnapshot < ApplicationRecord
  belongs_to :account, optional: true

  validates :date, presence: true
  validates :period_type, presence: true, inclusion: { in: %w[daily weekly monthly quarterly yearly] }
  validates :mrr_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :arr_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :customer_churn_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :revenue_churn_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  # Ensure uniqueness of snapshot per account/date/period
  validates :date, uniqueness: { scope: [ :account_id, :period_type ] }

  # Money handling
  monetize :mrr_cents
  monetize :arr_cents
  monetize :arpu_cents
  monetize :ltv_cents

  # Serialization
  serialize :metadata, coder: JSON

  # Scopes
  scope :for_account, ->(account) { where(account: account) }
  scope :global, -> { where(account: nil) }
  scope :for_period, ->(period_type) { where(period_type: period_type) }
  scope :in_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :recent, ->(limit = 12) { order(date: :desc).limit(limit) }
  scope :daily, -> { where(period_type: "daily") }
  scope :monthly, -> { where(period_type: "monthly") }
  scope :yearly, -> { where(period_type: "yearly") }

  # Callbacks
  after_initialize :set_defaults
  before_save :calculate_derived_metrics

  # Class methods
  def self.latest_for_account(account, period_type = "monthly")
    for_account(account).for_period(period_type).order(date: :desc).first
  end

  def self.latest_global(period_type = "monthly")
    global.for_period(period_type).order(date: :desc).first
  end

  def self.growth_between_periods(account, period_type, start_date, end_date)
    snapshots = for_account(account).for_period(period_type).in_date_range(start_date, end_date).order(:date)
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

  def growth_rate_percentage
    (growth_rate * 100).round(2)
  end

  def customer_churn_rate_percentage
    (customer_churn_rate * 100).round(2)
  end

  def revenue_churn_rate_percentage
    (revenue_churn_rate * 100).round(2)
  end

  def net_new_subscriptions
    new_subscriptions_count - churned_subscriptions_count
  end

  def net_new_customers
    new_customers_count - churned_customers_count
  end

  def subscription_retention_rate
    return 0.0 if active_subscriptions_count == 0
    1.0 - customer_churn_rate
  end

  def revenue_retention_rate
    return 0.0 if mrr_cents == 0
    1.0 - revenue_churn_rate
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
    self.date ||= Date.current if new_record?
  end

  def calculate_derived_metrics
    # Calculate ARR from MRR
    self.arr_cents = mrr_cents * 12

    # Calculate ARPU (Average Revenue Per User)
    if total_customers_count > 0
      self.arpu_cents = mrr_cents / total_customers_count
    else
      self.arpu_cents = 0
    end

    # Estimate LTV (simple calculation: ARPU / churn_rate, capped at reasonable maximum)
    if customer_churn_rate > 0
      monthly_churn = customer_churn_rate
      estimated_lifetime_months = 1.0 / monthly_churn
      estimated_lifetime_months = [ estimated_lifetime_months, 60 ].min # Cap at 5 years
      self.ltv_cents = (arpu_cents * estimated_lifetime_months).to_i
    else
      # If no churn, estimate based on industry average or set high value
      self.ltv_cents = arpu_cents * 24 # 2 years default
    end
  end
end
