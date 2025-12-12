# frozen_string_literal: true

class TaskExecution < ApplicationRecord
  # Associations
  belongs_to :scheduled_task
  belongs_to :user, optional: true # null for scheduled executions

  # Validations
  validates :status, presence: true, inclusion: { in: %w[pending running completed failed] }
  validates :triggered_by, presence: true, inclusion: { in: %w[scheduled manual] }

  # Scopes
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :running, -> { where(status: "running") }
  scope :pending, -> { where(status: "pending") }
  scope :manual, -> { where(triggered_by: "manual") }
  scope :scheduled, -> { where(triggered_by: "scheduled") }
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

  def pending?
    status == "pending"
  end

  def manual?
    triggered_by == "manual"
  end

  def scheduled?
    triggered_by == "scheduled"
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
    audit_user = user || scheduled_task.user

    AuditLog.create!(
      user: audit_user,
      account: audit_user.account,
      action: "task_execution_created",
      resource_type: "TaskExecution",
      resource_id: id,
      details: {
        task_name: scheduled_task.name,
        task_type: scheduled_task.task_type,
        triggered_by: triggered_by,
        triggered_by_user: user&.email
      }
    )
  rescue => e
    Rails.logger.error "Failed to log execution creation: #{e.message}"
  end

  def log_execution_status_change
    audit_user = user || scheduled_task.user

    AuditLog.create!(
      user: audit_user,
      account: audit_user.account,
      action: "task_execution_status_changed",
      resource_type: "TaskExecution",
      resource_id: id,
      details: {
        task_name: scheduled_task.name,
        previous_status: status_before_last_save,
        new_status: status,
        duration_seconds: (duration&.to_i),
        error_message: error_message,
        output_preview: output&.truncate(200)
      }
    )
  rescue => e
    Rails.logger.error "Failed to log execution status change: #{e.message}"
  end
end
