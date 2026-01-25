# frozen_string_literal: true

class SystemOperation < ApplicationRecord
  # Associations
  belongs_to :user

  # Validations
  validates :operation_type, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending in_progress completed failed] }

  # Scopes
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :running, -> { where(status: "in_progress") }
  scope :pending, -> { where(status: "pending") }
  scope :by_type, ->(type) { where(operation_type: type) }
  scope :recent, -> { order(started_at: :desc) }
  scope :last_24_hours, -> { where(started_at: 24.hours.ago..Time.current) }

  # Callbacks
  after_create :log_operation_creation
  after_update :log_operation_status_change, if: :saved_change_to_status?

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def running?
    status == "in_progress"
  end

  def pending?
    status == "pending"
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def duration_human
    return "N/A" unless duration

    if duration < 60
      "#{duration.to_i}s"
    elsif duration < 3600
      "#{(duration / 60).to_i}m #{(duration % 60).to_i}s"
    else
      hours = (duration / 3600).to_i
      minutes = ((duration % 3600) / 60).to_i
      "#{hours}h #{minutes}m"
    end
  end

  def success?
    completed?
  end

  def operation_description
    case operation_type
    when "restart_service"
      "Restart #{parameters&.dig('services')&.join(', ') || 'services'}"
    when "database_optimize"
      "Database optimization"
    when "database_reindex"
      "Database reindexing"
    when "clear_cache"
      "Clear application cache"
    when "clear_logs"
      "Clear system logs"
    when "reload_configuration"
      "Reload system configuration"
    else
      operation_type.humanize
    end
  end

  class << self
    def operation_statistics(days = 7)
      operations = where(started_at: days.days.ago..Time.current)

      {
        total_operations: operations.count,
        completed: operations.completed.count,
        failed: operations.failed.count,
        success_rate: calculate_success_rate(operations),
        by_type: operations.group(:operation_type).count,
        average_duration: calculate_average_duration(operations.completed)
      }
    end

    def recent_failures(limit = 10)
      failed.recent.limit(limit).includes(:user).map do |operation|
        {
          id: operation.id,
          operation_type: operation.operation_type,
          description: operation.operation_description,
          error_message: operation.error_message,
          started_at: operation.started_at.iso8601,
          user_email: operation.user.email
        }
      end
    end

    private

    def calculate_success_rate(operations)
      return 0 if operations.empty?

      successful = operations.completed.count
      total = operations.count

      (successful.to_f / total * 100).round(2)
    end

    def calculate_average_duration(completed_operations)
      durations = completed_operations.where.not(completed_at: nil)
                                    .pluck(:started_at, :completed_at)
                                    .map { |start, finish| finish - start }

      return 0 if durations.empty?

      (durations.sum / durations.count).round(2)
    end
  end

  private

  def log_operation_creation
    AuditLog.create!(
      user: user,
      account: user.account,
      action: "system_operation_created",
      resource_type: "SystemOperation",
      resource_id: id,
      details: {
        operation_type: operation_type,
        description: operation_description,
        parameters: parameters
      }
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log operation creation: #{e.message}"
  end

  def log_operation_status_change
    AuditLog.create!(
      user: user,
      account: user.account,
      action: "system_operation_status_changed",
      resource_type: "SystemOperation",
      resource_id: id,
      details: {
        operation_type: operation_type,
        previous_status: status_before_last_save,
        new_status: status,
        duration_seconds: duration&.to_i,
        error_message: error_message,
        result_summary: result&.dig("message") || result&.dig("success")
      }
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log operation status change: #{e.message}"
  end
end
