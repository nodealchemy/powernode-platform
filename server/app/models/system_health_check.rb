# frozen_string_literal: true

class SystemHealthCheck < ApplicationRecord
  # Validations
  validates :check_type, presence: true, inclusion: { in: %w[basic detailed comprehensive] }
  validates :overall_status, presence: true, inclusion: { in: %w[healthy warning critical] }
  validates :health_data, presence: true
  validates :checked_at, presence: true

  # Scopes
  scope :healthy, -> { where(overall_status: "healthy") }
  scope :warning, -> { where(overall_status: "warning") }
  scope :critical, -> { where(overall_status: "critical") }
  scope :by_type, ->(type) { where(check_type: type) }
  scope :recent, -> { order(checked_at: :desc) }
  scope :last_24_hours, -> { where(checked_at: 24.hours.ago..Time.current) }

  # Callbacks
  after_create :log_health_check
  after_create :alert_if_critical

  def healthy?
    overall_status == "healthy"
  end

  def warning?
    overall_status == "warning"
  end

  def critical?
    overall_status == "critical"
  end

  def basic?
    check_type == "basic"
  end

  def detailed?
    check_type == "detailed"
  end

  def comprehensive?
    check_type == "comprehensive"
  end

  def response_time_human
    return "N/A" unless response_time_ms

    if response_time_ms < 1000
      "#{response_time_ms}ms"
    else
      "#{(response_time_ms / 1000.0).round(2)}s"
    end
  end

  def component_statuses
    return {} unless health_data["components"]

    health_data["components"].transform_values do |component|
      component["status"]
    end
  end

  def failed_components
    component_statuses.select { |_, status| status != "healthy" }
  end

  def critical_components
    component_statuses.select { |_, status| status == "critical" }
  end

  class << self
    def latest_check(type = nil)
      scope = type ? by_type(type) : all
      scope.order(:checked_at).last
    end

    def status_trend(hours = 24)
      checks = where(checked_at: hours.hours.ago..Time.current)
                .order(:checked_at)
                .pluck(:checked_at, :overall_status)

      {
        total_checks: checks.count,
        healthy_count: checks.count { |_, status| status == "healthy" },
        warning_count: checks.count { |_, status| status == "warning" },
        critical_count: checks.count { |_, status| status == "critical" },
        trend_data: checks.map { |time, status| { time: time.iso8601, status: status } }
      }
    end

    def system_availability(hours = 24)
      checks = where(checked_at: hours.hours.ago..Time.current)
      return 100.0 if checks.empty?

      healthy_checks = checks.where(overall_status: "healthy").count
      total_checks = checks.count

      (healthy_checks.to_f / total_checks * 100).round(2)
    end
  end

  private

  def log_health_check
    # Only log if this is a significant status change or critical status
    if critical? || status_changed_since_last_check?
      AuditLog.create!(
        action: "system_health_check",
        resource_type: "SystemHealthCheck",
        resource_id: id,
        details: {
          check_type: check_type,
          overall_status: overall_status,
          response_time_ms: response_time_ms,
          failed_components: failed_components,
          critical_components: critical_components
        }
      )
    end
  rescue StandardError => e
    Rails.logger.error "Failed to log health check: #{e.message}"
  end

  def alert_if_critical
    return unless critical?

    # Send alerts for critical system status
    begin
      # This would integrate with your notification system
      Rails.logger.error "CRITICAL SYSTEM HEALTH: #{failed_components.keys.join(', ')}"

      # Create notification for system administrators
      # NotificationService.send_critical_alert(self)
    rescue StandardError => e
      Rails.logger.error "Failed to send critical health alert: #{e.message}"
    end
  end

  def status_changed_since_last_check?
    last_check = self.class.where(check_type: check_type)
                    .where("checked_at < ?", checked_at)
                    .order(:checked_at)
                    .last

    !last_check || last_check.overall_status != overall_status
  end
end
