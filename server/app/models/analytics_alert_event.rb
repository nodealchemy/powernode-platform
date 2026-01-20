# frozen_string_literal: true

class AnalyticsAlertEvent < ApplicationRecord
  # Associations
  belongs_to :analytics_alert
  belongs_to :account, optional: true

  # Validations
  validates :event_type, presence: true, inclusion: { in: %w[triggered resolved acknowledged escalated] }
  validates :severity, inclusion: { in: %w[critical high medium low info] }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :triggered, -> { where(event_type: "triggered") }
  scope :unacknowledged, -> { triggered.where(acknowledged: false) }
  scope :unresolved, -> { where(resolved: false) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :for_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Instance methods
  def triggered?
    event_type == "triggered"
  end

  def resolved?
    resolved
  end

  def acknowledged?
    acknowledged
  end

  def critical?
    severity == "critical"
  end

  def acknowledge!(by:, notes: nil)
    update!(
      acknowledged: true,
      acknowledged_at: Time.current,
      acknowledged_by: by
    )
  end

  def resolve!(notes: nil)
    update!(
      resolved: true,
      resolved_at: Time.current,
      resolution_notes: notes
    )
  end

  def summary
    {
      id: id,
      alert_id: analytics_alert_id,
      event_type: event_type,
      triggered_value: triggered_value,
      threshold_value: threshold_value,
      message: message,
      severity: severity,
      acknowledged: acknowledged,
      resolved: resolved,
      created_at: created_at
    }
  end
end
