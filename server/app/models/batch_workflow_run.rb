# frozen_string_literal: true

# Model for tracking batch workflow runs with multiple workflow executions
class BatchWorkflowRun < ApplicationRecord
  # ==========================================
  # Authentication & Authorization
  # ==========================================
  belongs_to :account
  belongs_to :user, optional: true

  # ==========================================
  # Associations
  # ==========================================
  # Link to individual workflow runs if needed
  has_many :ai_workflow_runs,
           foreign_key: :batch_id,
           primary_key: :batch_id,
           dependent: :nullify,
           class_name: 'AiWorkflowRun'

  # ==========================================
  # Validations
  # ==========================================
  validates :batch_id, presence: true, uniqueness: true
  validates :status, inclusion: {
    in: %w[pending processing completed failed cancelled],
    message: 'must be a valid batch status'
  }
  validates :total_workflows, numericality: { greater_than: 0 }
  validates :completed_workflows, numericality: { greater_than_or_equal_to: 0 }
  validates :successful_workflows, numericality: { greater_than_or_equal_to: 0 }
  validates :failed_workflows, numericality: { greater_than_or_equal_to: 0 }

  validate :validate_workflow_counts
  validate :validate_completion_time

  # ==========================================
  # Scopes
  # ==========================================
  scope :processing, -> { where(status: 'processing') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :with_failures, -> { where('failed_workflows > 0') }
  scope :successful, -> { where(status: 'completed', failed_workflows: 0) }

  # ==========================================
  # Callbacks
  # ==========================================
  before_validation :generate_batch_id, on: :create
  before_validation :set_default_values, on: :create
  after_update :calculate_statistics, if: :saved_change_to_completed_workflows?
  after_update :check_completion, if: :saved_change_to_completed_workflows?
  after_update :broadcast_progress, if: -> { processing? && saved_change_to_completed_workflows? }

  # ==========================================
  # Public Methods
  # ==========================================

  # Status check methods
  def pending?
    status == 'pending'
  end

  def processing?
    status == 'processing'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def cancelled?
    status == 'cancelled'
  end

  # Progress calculation
  def progress_percentage
    return 0 if total_workflows.zero?
    (completed_workflows.to_f / total_workflows * 100).round(2)
  end

  def success_rate
    return 0 if completed_workflows.zero?
    (successful_workflows.to_f / completed_workflows * 100).round(2)
  end

  def failure_rate
    return 0 if completed_workflows.zero?
    (failed_workflows.to_f / completed_workflows * 100).round(2)
  end

  # Batch operations
  def start_processing!
    update!(
      status: 'processing',
      started_at: Time.current
    )
  end

  def mark_completed!
    update!(
      status: completed_workflows == successful_workflows ? 'completed' : 'failed',
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def cancel!
    update!(
      status: 'cancelled',
      completed_at: Time.current,
      error_details: error_details.merge('reason' => 'User cancelled')
    )
  end

  def record_workflow_completion(success: true)
    # Use a single update to avoid constraint violations
    if success
      update!(
        successful_workflows: successful_workflows + 1,
        completed_workflows: completed_workflows + 1
      )
    else
      update!(
        failed_workflows: failed_workflows + 1,
        completed_workflows: completed_workflows + 1
      )
    end
  end

  def add_result(workflow_id, result_data)
    results << result_data.merge(
      'workflow_id' => workflow_id,
      'completed_at' => Time.current.iso8601
    )
    save!
  end

  # ==========================================
  # Private Methods
  # ==========================================
  private

  def generate_batch_id
    self.batch_id ||= SecureRandom.uuid
  end

  def set_default_values
    self.total_workflows ||= 0
    self.completed_workflows ||= 0
    self.successful_workflows ||= 0
    self.failed_workflows ||= 0
    self.configuration ||= {}
    self.results ||= []
    self.statistics ||= {}
    self.error_details ||= {}
  end

  def validate_workflow_counts
    if completed_workflows > total_workflows
      errors.add(:completed_workflows, "can't be greater than total workflows")
    end

    if (successful_workflows + failed_workflows) > completed_workflows
      errors.add(:base, "Sum of successful and failed workflows can't exceed completed workflows")
    end
  end

  def validate_completion_time
    if completed_at.present? && started_at.present? && completed_at < started_at
      errors.add(:completed_at, "can't be before started time")
    end
  end

  def calculate_duration
    return nil unless started_at.present? && completed_at.present?
    ((completed_at - started_at) * 1000).to_i
  end

  def calculate_statistics
    self.statistics = {
      'total_workflows' => total_workflows,
      'successful' => successful_workflows,
      'failed' => failed_workflows,
      'success_rate' => success_rate,
      'failure_rate' => failure_rate,
      'average_duration' => calculate_average_duration,
      'updated_at' => Time.current.iso8601
    }
  end

  def calculate_average_duration
    return 0 if results.empty?

    durations = results.filter_map do |r|
      r['duration_ms']
    end

    return 0 if durations.empty?
    (durations.sum / durations.size.to_f).round(2)
  end

  def check_completion
    if completed_workflows >= total_workflows && processing?
      mark_completed!
    end
  end

  def broadcast_progress
    ActionCable.server.broadcast(
      "batch_processing_#{batch_id}",
      {
        type: 'batch_progress',
        batch_id: batch_id,
        progress: {
          total: total_workflows,
          completed: completed_workflows,
          successful: successful_workflows,
          failed: failed_workflows,
          percentage: progress_percentage
        },
        timestamp: Time.current.iso8601
      }
    )
  end
end