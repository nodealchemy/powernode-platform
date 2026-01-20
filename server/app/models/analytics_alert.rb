# frozen_string_literal: true

class AnalyticsAlert < ApplicationRecord
  # Associations
  belongs_to :account, optional: true
  has_many :alert_events, class_name: "AnalyticsAlertEvent", dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :alert_type, presence: true, inclusion: { in: %w[threshold anomaly trend comparison] }
  validates :metric_name, presence: true
  validates :condition, presence: true, inclusion: { in: %w[greater_than less_than equals change_percent anomaly_detected] }
  validates :threshold_value, presence: true
  validates :status, presence: true, inclusion: { in: %w[enabled disabled triggered resolved] }

  # Scopes
  scope :enabled, -> { where(status: "enabled") }
  scope :triggered, -> { where(status: "triggered") }
  scope :platform_wide, -> { where(account_id: nil) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :by_metric, ->(metric) { where(metric_name: metric) }
  scope :due_for_check, -> { enabled.where("last_checked_at IS NULL OR last_checked_at < ?", 5.minutes.ago) }
  scope :not_in_cooldown, -> { where("cooldown_until IS NULL OR cooldown_until < ?", Time.current) }

  # Available metrics
  AVAILABLE_METRICS = %w[
    mrr arr churn_rate customer_count active_subscriptions
    new_customers churned_customers revenue_growth payment_failures
    arpu ltv trial_conversion
  ].freeze

  # Instance methods
  def enabled?
    status == "enabled"
  end

  def triggered?
    status == "triggered"
  end

  def in_cooldown?
    cooldown_until.present? && cooldown_until > Time.current
  end

  def can_trigger?
    enabled? && !in_cooldown?
  end

  def evaluate!(value)
    return false unless can_trigger?

    update!(current_value: value, last_checked_at: Time.current)

    should_trigger = case condition
                     when "greater_than" then value > threshold_value
                     when "less_than" then value < threshold_value
                     when "equals" then value == threshold_value
                     when "change_percent" then calculate_change_exceeded?(value)
                     when "anomaly_detected" then value == 1 # External anomaly flag
                     else false
                     end

    if should_trigger
      trigger!(value)
      true
    elsif triggered? && auto_resolve
      resolve!
      false
    else
      false
    end
  end

  def trigger!(triggered_value = nil)
    transaction do
      update!(
        status: "triggered",
        last_triggered_at: Time.current,
        trigger_count: trigger_count + 1,
        cooldown_until: Time.current + cooldown_minutes.minutes
      )

      alert_events.create!(
        account: account,
        event_type: "triggered",
        triggered_value: triggered_value || current_value,
        threshold_value: threshold_value,
        message: generate_trigger_message,
        severity: calculate_severity(triggered_value || current_value)
      )
    end

    send_notifications!
  end

  def resolve!(notes: nil)
    return unless triggered?

    transaction do
      update!(status: "resolved")

      alert_events.create!(
        account: account,
        event_type: "resolved",
        triggered_value: current_value,
        threshold_value: threshold_value,
        message: "Alert resolved: #{name}",
        severity: "info",
        resolved: true,
        resolved_at: Time.current,
        resolution_notes: notes
      )
    end
  end

  def acknowledge!(by: nil)
    return unless triggered?

    last_event = alert_events.where(event_type: "triggered").order(created_at: :desc).first
    last_event&.update!(
      acknowledged: true,
      acknowledged_at: Time.current,
      acknowledged_by: by
    )
  end

  def summary
    {
      id: id,
      name: name,
      alert_type: alert_type,
      metric_name: metric_name,
      condition: condition,
      threshold_value: threshold_value,
      current_value: current_value,
      status: status,
      last_triggered_at: last_triggered_at,
      trigger_count: trigger_count,
      notification_channels: notification_channels,
      in_cooldown: in_cooldown?
    }
  end

  private

  def calculate_change_exceeded?(current_value)
    return false unless current_value.present?

    # Compare with previous period value from metadata
    previous_value = metadata["previous_value"]
    return false unless previous_value && previous_value > 0

    change_percent = ((current_value - previous_value) / previous_value * 100).abs
    change_percent >= threshold_value.abs
  end

  def generate_trigger_message
    case condition
    when "greater_than"
      "#{metric_name} (#{current_value}) exceeded threshold (#{threshold_value})"
    when "less_than"
      "#{metric_name} (#{current_value}) fell below threshold (#{threshold_value})"
    when "change_percent"
      "#{metric_name} changed by more than #{threshold_value}%"
    else
      "Alert triggered: #{name}"
    end
  end

  def calculate_severity(value)
    return "critical" if condition == "greater_than" && value > threshold_value * 1.5
    return "critical" if condition == "less_than" && value < threshold_value * 0.5
    return "high" if condition == "greater_than" && value > threshold_value * 1.2
    return "high" if condition == "less_than" && value < threshold_value * 0.8
    "medium"
  end

  def send_notifications!
    # Integration point for notification delivery
    # Would connect to NotificationService
    Rails.logger.info "Alert triggered: #{name} (#{id})"
  end
end
