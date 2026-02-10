# frozen_string_literal: true

class ChurnPrediction < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :subscription, optional: true

  # Validations
  validates :churn_probability, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :risk_tier, presence: true, inclusion: { in: %w[critical high medium low minimal] }
  validates :model_version, presence: true
  validates :prediction_type, inclusion: { in: %w[weekly monthly quarterly] }
  validates :predicted_at, presence: true

  # Scopes
  scope :recent, -> { order(predicted_at: :desc) }
  scope :latest, -> { order(predicted_at: :desc).first }
  scope :high_risk, -> { where(risk_tier: %w[critical high]) }
  scope :for_period, ->(start_date, end_date) { where(predicted_at: start_date..end_date) }
  scope :needs_intervention, -> { high_risk.where(intervention_triggered: false) }

  # Risk tier thresholds
  RISK_TIERS = {
    critical: 0.80,
    high: 0.60,
    medium: 0.40,
    low: 0.20,
    minimal: 0.0
  }.freeze

  # Instance methods
  def critical_risk?
    risk_tier == "critical"
  end

  def high_risk?
    risk_tier.in?(%w[critical high])
  end

  def needs_intervention?
    high_risk? && !intervention_triggered
  end

  def trigger_intervention!
    update!(
      intervention_triggered: true,
      intervention_at: Time.current
    )
  end

  def probability_percentage
    (churn_probability * 100).round(1)
  end

  def top_contributing_factors(limit = 5)
    return [] if contributing_factors.blank?

    contributing_factors
      .sort_by { |f| -f["weight"].to_f }
      .first(limit)
  end

  def summary
    {
      id: id,
      account_id: account_id,
      churn_probability: churn_probability,
      probability_percentage: probability_percentage,
      risk_tier: risk_tier,
      predicted_churn_date: predicted_churn_date,
      days_until_churn: days_until_churn,
      primary_risk_factor: primary_risk_factor,
      confidence_score: confidence_score,
      recommended_actions: recommended_actions,
      intervention_triggered: intervention_triggered,
      predicted_at: predicted_at
    }
  end

  # Class methods
  class << self
    def determine_risk_tier(probability)
      RISK_TIERS.each do |tier, threshold|
        return tier.to_s if probability >= threshold
      end
      "minimal"
    end

    def calculate_days_until_churn(probability)
      # Simple estimation based on probability
      # Higher probability = shorter timeframe
      return nil if probability < 0.2

      base_days = 90
      days = (base_days * (1 - probability)).round
      [ days, 7 ].max # Minimum 7 days
    end
  end
end
