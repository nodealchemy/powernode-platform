# frozen_string_literal: true

class UsageMeter < ApplicationRecord
  # Associations
  has_many :usage_events, dependent: :destroy
  has_many :usage_summaries, dependent: :destroy
  has_many :usage_quotas, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }
  validates :unit_name, presence: true
  validates :aggregation_type, presence: true, inclusion: { in: %w[sum max count last average] }
  validates :billing_model, presence: true, inclusion: { in: %w[tiered volume package flat per_unit] }
  validates :reset_period, presence: true, inclusion: { in: %w[never daily weekly monthly yearly billing_period] }

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :billable, -> { where(is_billable: true) }

  # Callbacks
  before_validation :generate_slug, on: :create, if: -> { slug.blank? && name.present? }

  # Instance methods
  def active?
    is_active
  end

  def billable?
    is_billable
  end

  def aggregate_events(events)
    return 0 if events.empty?

    case aggregation_type
    when "sum"
      events.sum(:quantity)
    when "max"
      events.maximum(:quantity) || 0
    when "count"
      events.count
    when "last"
      events.order(timestamp: :desc).first&.quantity || 0
    when "average"
      events.average(:quantity) || 0
    end
  end

  def calculate_cost(quantity)
    return 0.0 unless billable?

    case billing_model
    when "flat"
      calculate_flat_cost(quantity)
    when "per_unit"
      calculate_per_unit_cost(quantity)
    when "tiered"
      calculate_tiered_cost(quantity)
    when "volume"
      calculate_volume_cost(quantity)
    when "package"
      calculate_package_cost(quantity)
    else
      0.0
    end
  end

  def period_dates(reference_date = Date.current)
    case reset_period
    when "never"
      [nil, nil]
    when "daily"
      [reference_date.beginning_of_day, reference_date.end_of_day]
    when "weekly"
      [reference_date.beginning_of_week, reference_date.end_of_week]
    when "monthly"
      [reference_date.beginning_of_month, reference_date.end_of_month]
    when "yearly"
      [reference_date.beginning_of_year, reference_date.end_of_year]
    else
      [nil, nil]
    end
  end

  def summary
    {
      id: id,
      name: name,
      slug: slug,
      unit_name: unit_name,
      aggregation_type: aggregation_type,
      billing_model: billing_model,
      reset_period: reset_period,
      is_active: is_active,
      is_billable: is_billable,
      pricing_tiers: pricing_tiers
    }
  end

  private

  def generate_slug
    self.slug = name.parameterize.underscore
  end

  def calculate_flat_cost(_quantity)
    pricing_tiers.first&.dig("price") || 0.0
  end

  def calculate_per_unit_cost(quantity)
    rate = pricing_tiers.first&.dig("price_per_unit") || 0.0
    quantity * rate
  end

  def calculate_tiered_cost(quantity)
    total_cost = 0.0
    remaining = quantity

    sorted_tiers = pricing_tiers.sort_by { |t| t["from"] || 0 }

    sorted_tiers.each do |tier|
      from = tier["from"] || 0
      to = tier["to"] || Float::INFINITY
      rate = tier["price_per_unit"] || 0.0

      if remaining > 0 && quantity > from
        tier_units = [remaining, to - from].min
        tier_units = [tier_units, 0].max
        total_cost += tier_units * rate
        remaining -= tier_units
      end
    end

    total_cost
  end

  def calculate_volume_cost(quantity)
    # Volume pricing: one rate applies to all units based on total volume
    sorted_tiers = pricing_tiers.sort_by { |t| t["from"] || 0 }.reverse

    applicable_tier = sorted_tiers.find { |t| quantity >= (t["from"] || 0) }
    rate = applicable_tier&.dig("price_per_unit") || 0.0

    quantity * rate
  end

  def calculate_package_cost(quantity)
    # Package pricing: pay for fixed packages (e.g., 100 units at a time)
    package_size = pricing_tiers.first&.dig("package_size") || 1
    package_price = pricing_tiers.first&.dig("price") || 0.0

    packages_needed = (quantity.to_f / package_size).ceil
    packages_needed * package_price
  end
end
