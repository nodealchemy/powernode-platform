# frozen_string_literal: true

class WebhookDeliveryStat < ApplicationRecord
  # Associations
  belongs_to :webhook_endpoint

  # Validations
  validates :stat_date, presence: true, uniqueness: { scope: :webhook_endpoint_id }
  validates :total_deliveries, numericality: { greater_than_or_equal_to: 0 }
  validates :successful_deliveries, numericality: { greater_than_or_equal_to: 0 }
  validates :failed_deliveries, numericality: { greater_than_or_equal_to: 0 }
  validates :retried_deliveries, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :for_period, ->(start_date, end_date) { where(stat_date: start_date..end_date) }
  scope :recent, ->(days = 30) { where("stat_date >= ?", days.days.ago.to_date) }

  # Class methods
  class << self
    def record_delivery(endpoint:, success:, latency_ms:, error_code: nil)
      stat = find_or_initialize_by(
        webhook_endpoint: endpoint,
        stat_date: Date.current
      )

      stat.total_deliveries += 1

      if success
        stat.successful_deliveries += 1
      else
        stat.failed_deliveries += 1
        if error_code
          stat.error_counts[error_code] = (stat.error_counts[error_code] || 0) + 1
        end
      end

      # Update latency stats
      update_latency_stats(stat, latency_ms)

      stat.save!
      stat
    end

    def record_retry(endpoint:)
      stat = find_or_initialize_by(
        webhook_endpoint: endpoint,
        stat_date: Date.current
      )

      stat.retried_deliveries += 1
      stat.save!
      stat
    end

    def aggregate_for_endpoint(endpoint, days: 30)
      stats = endpoint.delivery_stats.recent(days)

      {
        total_deliveries: stats.sum(:total_deliveries),
        successful_deliveries: stats.sum(:successful_deliveries),
        failed_deliveries: stats.sum(:failed_deliveries),
        retried_deliveries: stats.sum(:retried_deliveries),
        success_rate: calculate_success_rate(stats),
        avg_latency_ms: stats.average(:avg_latency_ms)&.round,
        p95_latency_ms: stats.maximum(:p95_latency_ms),
        error_breakdown: aggregate_errors(stats),
        daily_stats: stats.order(stat_date: :asc).map(&:summary)
      }
    end

    private

    def update_latency_stats(stat, latency_ms)
      return unless latency_ms

      # Update min/max
      stat.min_latency_ms = [stat.min_latency_ms, latency_ms].compact.min
      stat.max_latency_ms = [stat.max_latency_ms, latency_ms].compact.max

      # Update average (simple running average)
      if stat.avg_latency_ms
        total_before = stat.avg_latency_ms * (stat.total_deliveries - 1)
        stat.avg_latency_ms = ((total_before + latency_ms) / stat.total_deliveries).round
      else
        stat.avg_latency_ms = latency_ms
      end

      # Update p95 (simplified - just track if higher than current)
      stat.p95_latency_ms = [stat.p95_latency_ms, latency_ms].compact.max
    end

    def calculate_success_rate(stats)
      total = stats.sum(:total_deliveries)
      return 0 if total.zero?

      ((stats.sum(:successful_deliveries).to_f / total) * 100).round(2)
    end

    def aggregate_errors(stats)
      stats.each_with_object({}) do |stat, result|
        stat.error_counts.each do |code, count|
          result[code] = (result[code] || 0) + count
        end
      end
    end
  end

  # Instance methods
  def success_rate
    return 0 if total_deliveries.zero?

    ((successful_deliveries.to_f / total_deliveries) * 100).round(2)
  end

  def failure_rate
    100 - success_rate
  end

  def summary
    {
      stat_date: stat_date,
      total_deliveries: total_deliveries,
      successful_deliveries: successful_deliveries,
      failed_deliveries: failed_deliveries,
      retried_deliveries: retried_deliveries,
      success_rate: success_rate,
      avg_latency_ms: avg_latency_ms,
      min_latency_ms: min_latency_ms,
      max_latency_ms: max_latency_ms,
      p95_latency_ms: p95_latency_ms,
      error_counts: error_counts
    }
  end
end
