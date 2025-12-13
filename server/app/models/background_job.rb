# frozen_string_literal: true

class BackgroundJob < ApplicationRecord
  self.table_name = "background_jobs"

  # Job statuses
  enum :status, {
    pending: "pending",
    in_progress: "in_progress",
    completed: "completed",
    failed: "failed",
    cancelled: "cancelled"
  }

  # Validations
  validates :job_id, presence: true, uniqueness: true
  validates :job_type, presence: true
  validates :status, inclusion: { in: statuses.keys }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: [ "pending", "in_progress" ]) }
  scope :finished, -> { where(status: [ "completed", "failed", "cancelled" ]) }

  # Callbacks
  before_create :set_default_status
  before_save :update_timestamps

  def self.create_for_sidekiq_job(sidekiq_jid, job_type, job_params = {})
    create!(
      job_id: sidekiq_jid,
      job_type: job_type,
      parameters: job_params,
      status: :pending,
      started_at: Time.current
    )
  end

  def mark_in_progress!
    update!(
      status: :in_progress,
      started_at: Time.current
    )
  end

  def mark_completed!(result = {})
    update!(
      status: :completed,
      result: result,
      completed_at: Time.current
    )
  end

  def mark_failed!(error_message, error_details = {})
    update!(
      status: :failed,
      error_message: error_message,
      error_details: error_details,
      completed_at: Time.current
    )
  end

  def duration
    return nil unless completed_at && started_at
    completed_at - started_at
  end

  def progress_percentage
    case status
    when "pending" then 0
    when "in_progress" then (result&.dig("progress") || 50).to_i
    when "completed" then 100
    when "failed", "cancelled" then 100
    else 0
    end
  end

  private

  def set_default_status
    self.status ||= :pending
  end

  def update_timestamps
    if status_changed?
      case status
      when "in_progress"
        self.started_at ||= Time.current
      when "completed", "failed", "cancelled"
        self.completed_at ||= Time.current
      end
    end
  end
end
