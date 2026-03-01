# frozen_string_literal: true

class BackgroundJob < ApplicationRecord
  self.table_name = "background_jobs"

  # Job statuses
  enum :status, {
    pending: "pending",
    processing: "processing",
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
  scope :active, -> { where(status: [ "pending", "processing" ]) }
  scope :finished, -> { where(status: [ "completed", "failed", "cancelled" ]) }

  # Callbacks
  before_validation :set_default_status, on: :create
  before_save :update_timestamps

  def self.create_for_sidekiq_job(sidekiq_jid, job_type, job_params = {})
    create!(
      job_id: sidekiq_jid,
      job_type: job_type,
      arguments: job_params,
      status: :pending,
      started_at: Time.current
    )
  end

  def mark_in_progress!
    update!(
      status: :processing,
      started_at: Time.current
    )
  end
  alias_method :mark_processing!, :mark_in_progress!

  def mark_completed!
    update!(
      status: :completed,
      finished_at: Time.current
    )
  end

  def mark_failed!(error_msg, error_trace = nil)
    update!(
      status: :failed,
      error_message: error_msg,
      backtrace: error_trace,
      failed_at: Time.current,
      finished_at: Time.current
    )
  end

  def duration
    return nil unless finished_at && started_at
    finished_at - started_at
  end

  def progress_percentage
    case status
    when "completed" then 100
    when "failed", "cancelled" then 0
    when "processing" then 50
    when "pending" then 0
    else 0
    end
  end

  # Alias accessors for controller compatibility
  def parameters
    arguments
  end

  def result
    nil
  end

  def error_details
    backtrace
  end

  def completed_at
    finished_at
  end

  private

  def set_default_status
    self.status ||= :pending
  end

  def update_timestamps
    if status_changed?
      case status
      when "processing"
        self.started_at ||= Time.current
      when "completed", "cancelled"
        self.finished_at ||= Time.current
      when "failed"
        self.failed_at ||= Time.current
        self.finished_at ||= Time.current
      end
    end
  end
end
