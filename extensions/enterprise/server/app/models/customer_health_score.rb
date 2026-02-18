# frozen_string_literal: true

class CustomerHealthScore < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :subscription, optional: true

  # Validations
  validates :overall_score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :health_status, presence: true, inclusion: { in: %w[critical at_risk needs_attention healthy thriving] }
  validates :risk_level, inclusion: { in: %w[critical high medium low none] }
  validates :trend_direction, inclusion: { in: %w[improving stable declining critical_decline] }
  validates :calculated_at, presence: true

  # Scopes
  scope :recent, -> { order(calculated_at: :desc) }
  scope :ordered, -> { order(calculated_at: :desc) }

  def self.latest
    ordered.first
  end
  scope :at_risk, -> { where(at_risk: true) }
  scope :healthy, -> { where(health_status: %w[healthy thriving]) }
  scope :needs_attention, -> { where(health_status: %w[critical at_risk needs_attention]) }
  scope :for_period, ->(start_date, end_date) { where(calculated_at: start_date..end_date) }

  # Health status thresholds
  HEALTH_THRESHOLDS = {
    thriving: 85,
    healthy: 70,
    needs_attention: 50,
    at_risk: 30,
    critical: 0
  }.freeze

  # Risk level thresholds
  RISK_THRESHOLDS = {
    none: 85,
    low: 70,
    medium: 50,
    high: 30,
    critical: 0
  }.freeze

  # Instance methods
  def critical?
    health_status == "critical"
  end

  def at_risk?
    at_risk
  end

  def healthy?
    health_status.in?(%w[healthy thriving])
  end

  def improving?
    trend_direction == "improving"
  end

  def declining?
    trend_direction.in?(%w[declining critical_decline])
  end

  def primary_risk_factor
    return nil if risk_factors.blank?
    risk_factors.first
  end

  def calculate_weighted_score(weights = nil)
    weights ||= {
      engagement: 0.25,
      payment: 0.30,
      usage: 0.20,
      support: 0.15,
      tenure: 0.10
    }

    score = 0
    score += (engagement_score || 0) * weights[:engagement]
    score += (payment_score || 0) * weights[:payment]
    score += (usage_score || 0) * weights[:usage]
    score += (support_score || 0) * weights[:support]
    score += (tenure_score || 0) * weights[:tenure]

    score.round(2)
  end

  def summary
    {
      id: id,
      account_id: account_id,
      overall_score: overall_score,
      health_status: health_status,
      at_risk: at_risk,
      risk_level: risk_level,
      risk_factors: risk_factors,
      trend_direction: trend_direction,
      score_change_30d: score_change_30d,
      components: {
        engagement: engagement_score,
        payment: payment_score,
        usage: usage_score,
        support: support_score,
        tenure: tenure_score
      },
      calculated_at: calculated_at
    }
  end

  # Class methods
  class << self
    def determine_health_status(score)
      HEALTH_THRESHOLDS.each do |status, threshold|
        return status.to_s if score >= threshold
      end
      "critical"
    end

    def determine_risk_level(score)
      RISK_THRESHOLDS.each do |level, threshold|
        return level.to_s if score >= threshold
      end
      "critical"
    end

    def determine_trend(current_score, previous_score)
      return "stable" unless previous_score

      change = current_score - previous_score
      if change > 10
        "improving"
      elsif change > 0
        "stable"
      elsif change > -10
        "declining"
      else
        "critical_decline"
      end
    end
  end
end
