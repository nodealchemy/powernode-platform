# frozen_string_literal: true

class RevenueForecast < ApplicationRecord
  # Associations
  belongs_to :account, optional: true # nil = platform-wide forecast

  # Validations
  validates :forecast_date, presence: true
  validates :forecast_type, presence: true, inclusion: { in: %w[mrr arr customers revenue] }
  validates :forecast_period, presence: true, inclusion: { in: %w[weekly monthly quarterly yearly] }
  validates :generated_at, presence: true

  # Scopes
  scope :recent, -> { order(generated_at: :desc) }
  scope :latest, -> { order(generated_at: :desc).first }
  scope :platform_wide, -> { where(account_id: nil) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :by_type, ->(type) { where(forecast_type: type) }
  scope :by_period, ->(period) { where(forecast_period: period) }
  scope :future, -> { where("forecast_date >= ?", Date.current) }
  scope :past, -> { where("forecast_date < ?", Date.current) }

  # Instance methods
  def platform_wide?
    account_id.nil?
  end

  def has_actuals?
    actual_mrr.present?
  end

  def calculate_accuracy!
    return unless has_actuals? && projected_mrr.present? && projected_mrr > 0

    accuracy = 100 - ((actual_mrr - projected_mrr).abs / projected_mrr * 100)
    update!(accuracy_percentage: [accuracy, 0].max.round(2))
  end

  def within_confidence_interval?(actual_value)
    return false unless lower_bound && upper_bound
    actual_value >= lower_bound && actual_value <= upper_bound
  end

  def variance
    return nil unless has_actuals? && projected_mrr
    actual_mrr - projected_mrr
  end

  def variance_percentage
    return nil unless has_actuals? && projected_mrr && projected_mrr > 0
    ((actual_mrr - projected_mrr) / projected_mrr * 100).round(2)
  end

  def net_growth
    return nil unless projected_new_revenue && projected_churned_revenue
    projected_new_revenue + (projected_expansion_revenue || 0) - projected_churned_revenue
  end

  def customer_growth
    return nil unless projected_new_customers && projected_churned_customers
    projected_new_customers - projected_churned_customers
  end

  def summary
    {
      id: id,
      forecast_date: forecast_date,
      forecast_type: forecast_type,
      forecast_period: forecast_period,
      projections: {
        mrr: projected_mrr,
        arr: projected_arr,
        new_revenue: projected_new_revenue,
        expansion_revenue: projected_expansion_revenue,
        churned_revenue: projected_churned_revenue,
        net_revenue: projected_net_revenue
      },
      customers: {
        projected_new: projected_new_customers,
        projected_churned: projected_churned_customers,
        projected_total: projected_total_customers
      },
      confidence: {
        level: confidence_level,
        lower_bound: lower_bound,
        upper_bound: upper_bound
      },
      actuals: has_actuals? ? {
        mrr: actual_mrr,
        accuracy: accuracy_percentage,
        variance: variance,
        variance_percentage: variance_percentage
      } : nil,
      generated_at: generated_at
    }
  end

  # Class methods
  class << self
    def generate_for_period(period, months_ahead: 12)
      forecasts = []
      start_date = Date.current.beginning_of_month

      months_ahead.times do |i|
        forecast_date = start_date + i.months

        forecast = create!(
          forecast_date: forecast_date,
          forecast_type: "mrr",
          forecast_period: period,
          generated_at: Time.current,
          model_version: "1.0"
        )

        forecasts << forecast
      end

      forecasts
    end
  end
end
