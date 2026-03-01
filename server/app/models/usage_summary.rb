# frozen_string_literal: true

class UsageSummary < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :usage_meter
  belongs_to :subscription, class_name: "Billing::Subscription", optional: true
  belongs_to :invoice, class_name: "Billing::Invoice", optional: true

  # Validations
  validates :period_start, presence: true
  validates :period_end, presence: true
  validates :total_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :billable_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :event_count, numericality: { greater_than_or_equal_to: 0 }
  validates :calculated_amount, numericality: { greater_than_or_equal_to: 0 }
  validate :period_end_after_start

  # Scopes
  scope :unbilled, -> { where(is_billed: false) }
  scope :billed, -> { where(is_billed: true) }
  scope :for_period, ->(start_date, end_date) { where(period_start: start_date..end_date) }
  scope :quota_exceeded, -> { where(quota_exceeded: true) }
  scope :recent, -> { order(period_start: :desc) }

  # Class methods
  class << self
    def aggregate_for_period(account:, meter:, period_start:, period_end:)
      existing = find_by(
        account: account,
        usage_meter: meter,
        period_start: period_start
      )

      return existing if existing&.is_billed?

      events = account.usage_events
                      .for_meter(meter)
                      .for_period(period_start, period_end)

      total_quantity = meter.aggregate_events(events)
      event_count = events.count
      calculated_amount = meter.calculate_cost(total_quantity)

      # Check quota
      quota = account.usage_quotas.find_by(usage_meter: meter)
      quota_limit = quota&.soft_limit || quota&.hard_limit
      quota_exceeded = quota_limit && total_quantity > quota_limit

      attributes = {
        account: account,
        usage_meter: meter,
        subscription: account.subscription,
        period_start: period_start,
        period_end: period_end,
        total_quantity: total_quantity,
        billable_quantity: total_quantity,
        event_count: event_count,
        quota_limit: quota_limit,
        quota_used: total_quantity,
        quota_exceeded: quota_exceeded,
        calculated_amount: calculated_amount
      }

      if existing
        existing.update!(attributes.except(:account, :usage_meter, :period_start))
        existing
      else
        create!(attributes)
      end
    end

    def aggregate_all_for_period(account:, period_start:, period_end:)
      UsageMeter.active.billable.find_each do |meter|
        aggregate_for_period(
          account: account,
          meter: meter,
          period_start: period_start,
          period_end: period_end
        )
      end
    end
  end

  # Instance methods
  def billed?
    is_billed
  end

  def mark_billed!(invoice_record)
    update!(is_billed: true, invoice: invoice_record)
  end

  def overage_quantity
    return 0 unless quota_limit && quota_used > quota_limit

    quota_used - quota_limit
  end

  def quota_usage_percent
    return 0 unless quota_limit && quota_limit > 0

    [ (quota_used / quota_limit * 100).round(1), 100 ].min
  end

  def included_quantity
    return total_quantity unless quota_limit

    [ total_quantity, quota_limit ].min
  end

  def summary
    {
      id: id,
      meter_name: usage_meter.name,
      meter_slug: usage_meter.slug,
      period_start: period_start,
      period_end: period_end,
      total_quantity: total_quantity,
      billable_quantity: billable_quantity,
      event_count: event_count,
      quota_limit: quota_limit,
      quota_used: quota_used,
      quota_exceeded: quota_exceeded,
      quota_usage_percent: quota_usage_percent,
      overage_quantity: overage_quantity,
      calculated_amount: calculated_amount,
      is_billed: is_billed,
      unit_name: usage_meter.unit_name
    }
  end

  private

  def period_end_after_start
    return unless period_start && period_end

    if period_end < period_start
      errors.add(:period_end, "must be after period start")
    end
  end
end
