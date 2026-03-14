# frozen_string_literal: true

class InvoiceLineItem < ApplicationRecord
  # Associations
  belongs_to :invoice

  # Validations
  validates :description, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_amount_cents, :total_amount_cents, presence: true
  validates :line_type, presence: true, inclusion: { in: %w[subscription usage discount tax adjustment] }
  validate :validate_pricing

  # Note: metadata is a native JSON column - no serialization needed in Rails 8

  # Money attributes
  monetize :unit_amount_cents, :total_amount_cents

  # Money methods that use invoice currency
  def unit_price
    return Money.new(unit_amount_cents, "USD") unless invoice
    Money.new(unit_amount_cents, invoice.currency)
  end

  def total
    return Money.new(total_amount_cents, "USD") unless invoice
    Money.new(total_amount_cents, invoice.currency)
  end

  # Scopes
  scope :subscription_items, -> { where(line_type: "subscription") }
  scope :usage_items, -> { where(line_type: "usage") }
  scope :discounts, -> { where(line_type: "discount") }
  scope :taxes, -> { where(line_type: "tax") }
  scope :adjustments, -> { where(line_type: "adjustment") }

  # Callbacks
  before_save :calculate_total
  after_initialize :set_defaults

  # Instance methods

  # Alias for compatibility with invoice calculations
  def total_cents
    total_amount_cents
  end

  def period_description
    return nil unless period_start && period_end
    "#{period_start.strftime('%b %d')} - #{period_end.strftime('%b %d, %Y')}"
  end

  def proration_factor
    return 1.0 unless period_start && period_end

    total_days = (period_end.to_date - period_start.to_date).to_i
    return 1.0 if total_days <= 0

    # Safely get billing cycle
    billing_cycle = invoice&.subscription&.plan&.billing_cycle
    return 1.0 unless billing_cycle

    # Calculate actual days in the billing period using calendar-aware logic
    period_days = calculate_billing_period_days(billing_cycle, period_start.to_date)
    return 1.0 if period_days <= 0

    total_days.to_f / period_days
  end

  def is_prorated?
    proration_factor < 1.0
  end

  private

  # Calculate actual calendar days in a billing period
  def calculate_billing_period_days(billing_cycle, start_date)
    case billing_cycle
    when "monthly"
      # Use actual days in the month
      ((start_date >> 1) - start_date).to_i
    when "quarterly"
      # Use actual days in 3 months
      ((start_date >> 3) - start_date).to_i
    when "yearly"
      # Use actual days in the year (handles leap years)
      ((start_date >> 12) - start_date).to_i
    else
      # Fallback to standard 30 days
      30
    end
  end

  def calculate_total
    self.total_amount_cents = quantity * unit_amount_cents
  end

  def set_defaults
    self.metadata ||= {}
  end

  def validate_pricing
    # Discounts and adjustments can have negative amounts
    if %w[discount adjustment].include?(line_type)
      # Allow negative amounts for discounts and adjustments
      true
    else
      # Other line types must have non-negative amounts
      errors.add(:unit_amount_cents, "must be greater than or equal to 0") if unit_amount_cents && unit_amount_cents < 0
      errors.add(:total_amount_cents, "must be greater than or equal to 0") if total_amount_cents && total_amount_cents < 0
    end
  end
end
