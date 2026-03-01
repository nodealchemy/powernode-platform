# frozen_string_literal: true

class TaskExecution < ApplicationRecord
  # Associations
  belongs_to :scheduled_task

  # Validations
  validates :status, presence: true, inclusion: { in: %w[running completed failed timeout] }

  # Scopes
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :running, -> { where(status: "running") }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  after_create :log_execution_creation
  after_update :log_execution_status_change, if: :saved_change_to_status?

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def running?
    status == "running"
  end

  def timeout?
    status == "timeout"
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

  private

  def log_execution_creation
    Rails.logger.info "Task execution created for: #{scheduled_task.name}"
  rescue StandardError => e
    Rails.logger.error "Failed to log execution creation: #{e.message}"
  end

  def log_execution_status_change
    Rails.logger.info "Task execution status changed for: #{scheduled_task.name} (#{status_before_last_save} -> #{status})"
  rescue StandardError => e
    Rails.logger.error "Failed to log execution status change: #{e.message}"
  end
end
