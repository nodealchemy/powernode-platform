# frozen_string_literal: true

class UsageEvent < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :usage_meter
  belongs_to :user, optional: true

  # Validations
  validates :event_id, presence: true, uniqueness: { scope: :account_id }
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :timestamp, presence: true
  validates :source, inclusion: { in: %w[api webhook system import internal] }, allow_nil: true

  # Scopes
  scope :unprocessed, -> { where(is_processed: false) }
  scope :processed, -> { where(is_processed: true) }
  scope :for_period, ->(start_time, end_time) { where(timestamp: start_time..end_time) }
  scope :for_meter, ->(meter) { where(usage_meter: meter) }
  scope :recent, -> { order(timestamp: :desc) }

  # Callbacks
  before_validation :set_defaults, on: :create

  # Instance methods
  def processed?
    is_processed
  end

  def mark_processed!
    update!(is_processed: true, processed_at: Time.current)
  end

  def summary
    {
      id: id,
      event_id: event_id,
      meter_slug: usage_meter.slug,
      quantity: quantity,
      timestamp: timestamp,
      source: source,
      is_processed: is_processed,
      properties: properties
    }
  end

  # Class methods for batch ingestion
  class << self
    def ingest_batch(account:, events:)
      results = { success: 0, failed: 0, errors: [] }

      events.each do |event_data|
        result = ingest_single(account: account, event_data: event_data)
        if result[:success]
          results[:success] += 1
        else
          results[:failed] += 1
          results[:errors] << { event_id: event_data[:event_id], error: result[:error] }
        end
      end

      results
    end

    def ingest_single(account:, event_data:)
      meter = UsageMeter.find_by(slug: event_data[:meter_slug])
      return { success: false, error: "Unknown meter: #{event_data[:meter_slug]}" } unless meter
      return { success: false, error: "Meter is inactive" } unless meter.active?

      # Check for duplicate (idempotency)
      existing = account.usage_events.find_by(event_id: event_data[:event_id])
      return { success: true, event: existing, duplicate: true } if existing

      event = account.usage_events.create!(
        usage_meter: meter,
        event_id: event_data[:event_id],
        quantity: event_data[:quantity] || 1,
        timestamp: event_data[:timestamp] || Time.current,
        source: event_data[:source] || "api",
        user_id: event_data[:user_id],
        properties: event_data[:properties] || {},
        metadata: event_data[:metadata] || {}
      )

      # Update quota tracking
      update_quota_usage(account, meter, event.quantity)

      { success: true, event: event, duplicate: false }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    end

    def update_quota_usage(account, meter, quantity)
      quota = account.usage_quotas.find_by(usage_meter: meter)
      return unless quota

      quota.increment!(:current_usage, quantity)

      # Check thresholds and send notifications if needed
      check_quota_thresholds(quota) if quota.current_usage > 0
    end

    def check_quota_thresholds(quota)
      return unless quota.soft_limit || quota.hard_limit

      usage_percent = if quota.soft_limit
                        (quota.current_usage / quota.soft_limit * 100).to_i
                      elsif quota.hard_limit
                        (quota.current_usage / quota.hard_limit * 100).to_i
                      end

      return unless usage_percent

      if usage_percent >= quota.critical_threshold_percent && quota.notify_on_exceeded
        # Queue notification job (implementation depends on notification system)
        Rails.logger.info "Usage quota critical: Account #{quota.account_id}, Meter #{quota.usage_meter_id}, #{usage_percent}%"
      elsif usage_percent >= quota.warning_threshold_percent && quota.notify_on_warning
        Rails.logger.info "Usage quota warning: Account #{quota.account_id}, Meter #{quota.usage_meter_id}, #{usage_percent}%"
      end
    end
  end

  private

  def set_defaults
    self.timestamp ||= Time.current
    self.event_id ||= SecureRandom.uuid
  end
end
