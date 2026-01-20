# frozen_string_literal: true

class AnalyticsTier < ApplicationRecord
  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 50 }
  validates :slug, presence: true, uniqueness: true, inclusion: { in: %w[free starter pro enterprise] }
  validates :monthly_price, numericality: { greater_than_or_equal_to: 0 }
  validates :retention_days, numericality: { greater_than_or_equal_to: -1 } # -1 means unlimited
  validates :cohort_months, numericality: { greater_than_or_equal_to: -1 } # -1 means unlimited
  validates :api_calls_per_day, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(sort_order: :asc) }

  # Class methods
  class << self
    def free
      find_by(slug: "free")
    end

    def starter
      find_by(slug: "starter")
    end

    def pro
      find_by(slug: "pro")
    end

    def enterprise
      find_by(slug: "enterprise")
    end

    def for_comparison
      active.ordered.map(&:comparison_data)
    end
  end

  # Instance methods
  def free?
    slug == "free"
  end

  def unlimited_retention?
    retention_days == -1
  end

  def unlimited_cohorts?
    cohort_months == -1
  end

  def unlimited_api_calls?
    api_calls_per_day == 0 || api_calls_per_day > 100_000
  end

  def has_feature?(feature_name)
    case feature_name.to_s
    when "csv_export" then csv_export
    when "api_access" then api_access
    when "forecasting" then forecasting
    when "custom_reports" then custom_reports
    else
      features[feature_name.to_s] == true
    end
  end

  def retention_display
    unlimited_retention? ? "Unlimited" : "#{retention_days} days"
  end

  def cohort_display
    return "N/A" if cohort_months == 0
    unlimited_cohorts? ? "Unlimited" : "#{cohort_months} months"
  end

  def api_calls_display
    return "N/A" if api_calls_per_day == 0
    unlimited_api_calls? ? "Unlimited" : "#{api_calls_per_day.to_s(:delimited)}/day"
  end

  def price_display
    monthly_price.zero? ? "Free" : "$#{monthly_price.to_i}/mo"
  end

  def comparison_data
    {
      id: id,
      name: name,
      slug: slug,
      monthly_price: monthly_price,
      price_display: price_display,
      features: {
        retention: retention_display,
        cohort_analysis: cohort_display,
        csv_export: csv_export,
        api_access: api_access,
        api_calls: api_calls_display,
        forecasting: forecasting,
        custom_reports: custom_reports
      },
      is_popular: slug == "pro"
    }
  end

  def summary
    {
      id: id,
      name: name,
      slug: slug,
      description: description,
      monthly_price: monthly_price,
      retention_days: retention_days,
      cohort_months: cohort_months,
      csv_export: csv_export,
      api_access: api_access,
      forecasting: forecasting,
      custom_reports: custom_reports,
      api_calls_per_day: api_calls_per_day,
      features: features
    }
  end
end
