# frozen_string_literal: true

class ReconciliationReport < ApplicationRecord
  validates :reconciliation_date, presence: true
  validates :reconciliation_type, presence: true, inclusion: { in: %w[daily weekly monthly custom] }
  validates :date_range_start, :date_range_end, presence: true
  validates :discrepancies_count, :high_severity_count, :medium_severity_count,
            presence: true, numericality: { greater_than_or_equal_to: 0 }

  # JSON columns for storing summary data
  # summary: { local_payments: int, stripe_payments: int, paypal_payments: int, total_amount_variance: int }
  serialize :summary, coder: JSON

  scope :recent, -> { order(created_at: :desc) }
  scope :with_discrepancies, -> { where("discrepancies_count > 0") }
  scope :high_priority, -> { where("high_severity_count > 0") }

  def has_discrepancies?
    discrepancies_count > 0
  end

  def high_priority?
    high_severity_count > 0
  end

  def date_range
    date_range_start..date_range_end
  end

  def total_payments
    summary&.dig("local_payments") || 0
  end

  def amount_variance
    summary&.dig("total_amount_variance") || 0
  end
end
