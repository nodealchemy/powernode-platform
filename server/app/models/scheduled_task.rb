# frozen_string_literal: true

class ScheduledTask < ApplicationRecord
  # Associations
  has_many :task_executions, dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :task_type, presence: true, inclusion: {
    in: %w[data_cleanup report_generation custom_command]
  }
  validates :cron_expression, presence: true
  validates :is_active, inclusion: { in: [ true, false ] }

  # Scopes
  scope :enabled, -> { where(is_active: true) }
  scope :disabled, -> { where(is_active: false) }
  scope :by_type, ->(type) { where(task_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  after_create :log_task_creation
  after_update :log_task_update, if: :saved_changes?
  after_destroy :log_task_deletion

  def enabled?
    is_active
  end

  def disabled?
    !is_active
  end

  def last_execution
    task_executions.order(:created_at).last
  end

  def last_successful_execution
    task_executions.where(status: "completed").order(:created_at).last
  end

  def success_rate
    return 0 if task_executions.empty?

    successful = task_executions.where(status: "completed").count
    total = task_executions.count

    (successful.to_f / total * 100).round(2)
  end

  def next_run_time
    # This would use a cron parser gem to calculate the next run time
    # For now, return a placeholder
    1.day.from_now
  end

  def can_execute?
    enabled? && !currently_running?
  end

  def currently_running?
    task_executions.where(status: "running").exists?
  end

  private

  def log_task_creation
    Rails.logger.info "Scheduled task created: #{name} (#{task_type})"
  rescue StandardError => e
    Rails.logger.error "Failed to log task creation: #{e.message}"
  end

  def log_task_update
    Rails.logger.info "Scheduled task updated: #{name} (changes: #{saved_changes.except('updated_at').keys.join(', ')})"
  rescue StandardError => e
    Rails.logger.error "Failed to log task update: #{e.message}"
  end

  def log_task_deletion
    Rails.logger.info "Scheduled task deleted: #{name} (#{task_type})"
  rescue StandardError => e
    Rails.logger.error "Failed to log task deletion: #{e.message}"
  end
end
