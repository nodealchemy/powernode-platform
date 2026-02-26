# frozen_string_literal: true

class UsageQuota < ApplicationRecord
  self.table_name = "usage_quotas"

  # Associations
  belongs_to :account
  belongs_to :usage_meter
  belongs_to :plan, class_name: "Billing::Plan", optional: true

  # Validations
  validates :account_id, uniqueness: { scope: :usage_meter_id }
  validates :soft_limit, numericality: { greater_than: 0 }, allow_nil: true
  validates :hard_limit, numericality: { greater_than: 0 }, allow_nil: true
  validates :overage_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :warning_threshold_percent, numericality: { in: 1..100 }, allow_nil: true
  validates :critical_threshold_percent, numericality: { in: 1..100 }, allow_nil: true
  validate :hard_limit_greater_than_soft_limit
  validate :critical_greater_than_warning

  # Scopes
  scope :exceeded, -> { where("current_usage >= COALESCE(soft_limit, hard_limit)") }
  scope :near_limit, -> { where("current_usage >= COALESCE(soft_limit, hard_limit) * 0.8") }

  # Instance methods
  def effective_limit
    soft_limit || hard_limit
  end

  def usage_percent
    return 0 unless effective_limit && effective_limit > 0

    [ (current_usage / effective_limit * 100).round(1), 100 ].min
  end

  def remaining
    return nil unless effective_limit

    [ effective_limit - current_usage, 0 ].max
  end

  def exceeded?
    return false unless effective_limit

    current_usage >= effective_limit
  end

  def hard_exceeded?
    return false unless hard_limit

    current_usage >= hard_limit
  end

  def at_warning_threshold?
    return false unless effective_limit && warning_threshold_percent

    usage_percent >= warning_threshold_percent
  end

  def at_critical_threshold?
    return false unless effective_limit && critical_threshold_percent

    usage_percent >= critical_threshold_percent
  end

  def overage_amount
    return 0 unless exceeded? && allow_overage && overage_rate

    overage_units = current_usage - effective_limit
    overage_units * overage_rate
  end

  def can_use?(additional_quantity)
    return true unless hard_limit && !allow_overage

    (current_usage + additional_quantity) <= hard_limit
  end

  def reset_usage!
    update!(
      current_usage: 0,
      current_period_start: Time.current,
      current_period_end: calculate_period_end
    )
  end

  def summary
    {
      id: id,
      meter_name: usage_meter.name,
      meter_slug: usage_meter.slug,
      soft_limit: soft_limit,
      hard_limit: hard_limit,
      current_usage: current_usage,
      remaining: remaining,
      usage_percent: usage_percent,
      exceeded: exceeded?,
      allow_overage: allow_overage,
      overage_rate: overage_rate,
      overage_amount: overage_amount,
      warning_threshold_percent: warning_threshold_percent,
      critical_threshold_percent: critical_threshold_percent,
      at_warning: at_warning_threshold?,
      at_critical: at_critical_threshold?,
      current_period_start: current_period_start,
      current_period_end: current_period_end,
      unit_name: usage_meter.unit_name
    }
  end

  private

  def hard_limit_greater_than_soft_limit
    return unless soft_limit && hard_limit

    if hard_limit < soft_limit
      errors.add(:hard_limit, "must be greater than or equal to soft limit")
    end
  end

  def critical_greater_than_warning
    return unless warning_threshold_percent && critical_threshold_percent

    if critical_threshold_percent <= warning_threshold_percent
      errors.add(:critical_threshold_percent, "must be greater than warning threshold")
    end
  end

  def calculate_period_end
    case usage_meter.reset_period
    when "daily"
      Time.current.end_of_day
    when "weekly"
      Time.current.end_of_week
    when "monthly"
      Time.current.end_of_month
    when "yearly"
      Time.current.end_of_year
    else
      nil
    end
  end
end
