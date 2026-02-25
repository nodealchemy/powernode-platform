# frozen_string_literal: true

module Devops
  # Execution record for a pipeline run
  # Tracks status, timing, outputs, and artifacts
  class PipelineRun < ApplicationRecord
    self.table_name = "devops_pipeline_runs"

    include ExecutionTrackable

    STATUSES = %w[pending queued running success failure cancelled].freeze
    TRIGGER_TYPES = %w[manual pull_request issue issue_comment push release schedule webhook workflow_dispatch].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :pipeline, class_name: "Devops::Pipeline", foreign_key: :devops_pipeline_id
    belongs_to :triggered_by, class_name: "User", optional: true

    has_many :step_executions, class_name: "Devops::StepExecution", foreign_key: :devops_pipeline_run_id, dependent: :destroy

    # ============================================
    # Validations
    # ============================================
    validates :run_number, presence: true, uniqueness: { scope: :devops_pipeline_id }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :trigger_type, presence: true, inclusion: { in: TRIGGER_TYPES }

    # ============================================
    # Scopes
    # ============================================
    scope :recent, -> { order(created_at: :desc) }
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: %w[success failure cancelled]) }
    scope :successful, -> { where(status: "success") }
    scope :failed, -> { where(status: "failure") }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_run_number, on: :create
    after_create_commit :broadcast_created
    after_update_commit :broadcast_updated
    after_update :calculate_duration, if: :completed_at_changed?

    # ============================================
    # Instance Methods
    # ============================================

    def start!
      start_execution!
    end

    def complete!(result_status, outputs: {}, error_message: nil)
      complete_execution!(result_status, outputs: outputs, error_message: error_message)
    end

    def cancel!
      cancel_execution!
    end

    # Override failure_status for PipelineRun convention
    def failure_status
      "failure"
    end

    def can_cancel?
      %w[pending queued running].include?(status)
    end

    def can_retry?
      %w[failure cancelled].include?(status)
    end

    def current_step
      step_executions.running.first || step_executions.pending.order(:created_at).first
    end

    def progress_percentage
      return 0 if pipeline.pipeline_steps.empty?

      completed_steps = step_executions.where(status: %w[success failure skipped]).count
      total_steps = pipeline.pipeline_steps.active.count
      ((completed_steps.to_f / total_steps) * 100).round
    end

    def ordered_step_executions
      step_executions.joins(:pipeline_step).order("devops_pipeline_steps.position ASC")
    end

    def trigger_context_value(key)
      trigger_context.dig(key.to_s)
    end

    def pr_number
      trigger_context_value("pr_number")
    end

    def commit_sha
      trigger_context_value("commit_sha")
    end

    def branch
      trigger_context_value("branch")
    end

    def enqueue_execution
      Devops::PipelineExecutionJob.perform_async(id)
    end

    private

    def generate_run_number
      return if run_number.present?

      # Extract numeric suffixes from existing run numbers and find max
      existing_numbers = pipeline.runs.pluck(:run_number).filter_map do |rn|
        rn.to_s.scan(/\d+$/).first&.to_i
      end
      next_number = (existing_numbers.max || 0) + 1
      self.run_number = next_number.to_s
    end

    def calculate_duration
      return unless started_at.present? && completed_at.present?

      update_column(:duration_seconds, (completed_at - started_at).to_i)
    end

    def broadcast_created
      DevopsPipelineChannel.broadcast_run_created(self)
    end

    def broadcast_updated
      if completed?
        DevopsPipelineChannel.broadcast_run_completed(self)
      else
        DevopsPipelineChannel.broadcast_run_updated(self)
      end
    end
  end
end
