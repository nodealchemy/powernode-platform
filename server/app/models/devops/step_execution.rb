# frozen_string_literal: true

module Devops
  # Execution record for an individual pipeline step
  # Tracks status, outputs, logs, and errors
  class StepExecution < ApplicationRecord
    include ExecutionTrackable

    STATUSES = %w[pending running waiting_approval success failure skipped].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :pipeline_run, class_name: "Devops::PipelineRun", foreign_key: :ci_cd_pipeline_run_id
    belongs_to :pipeline_step, class_name: "Devops::PipelineStep", foreign_key: :ci_cd_pipeline_step_id

    has_many :approval_tokens, class_name: "Devops::StepApprovalToken", foreign_key: :step_execution_id, dependent: :destroy

    # ============================================
    # Validations
    # ============================================
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :ci_cd_pipeline_step_id, uniqueness: { scope: :ci_cd_pipeline_run_id }

    # ============================================
    # Scopes
    # ============================================
    # Note: pending_executions, running_executions, etc. inherited from ExecutionTrackable
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :waiting_approval, -> { where(status: "waiting_approval") }
    scope :completed, -> { where(status: %w[success failure skipped]) }
    scope :successful, -> { where(status: "success") }
    scope :failed, -> { where(status: "failure") }
    scope :ordered, -> { joins(:pipeline_step).order("devops_pipeline_steps.position ASC") }

    # ============================================
    # Callbacks
    # ============================================
    after_update :notify_pipeline_run, if: :status_changed?

    # ============================================
    # Instance Methods
    # ============================================

    # Override start! to use concern method
    def start!
      start_execution!
    end

    # Override complete! to use concern method
    def complete!(result_status, outputs: {}, error_message: nil)
      complete_execution!(result_status, outputs: outputs, error_message: error_message)
    end

    # Override skip! to use concern method
    def skip!(reason = nil)
      skip_execution!(reason)
    end

    def append_log(message)
      new_logs = "#{logs}\n[#{Time.current.iso8601}] #{message}"
      update!(logs: new_logs.strip)
    end

    def output_value(key)
      outputs.dig(key.to_s)
    end

    def step_name
      pipeline_step.name
    end

    def step_type
      pipeline_step.step_type
    end

    def enqueue_execution
      WorkerJobService.enqueue_devops_step_execution(id)
    end

    # ============================================
    # Approval Workflow Methods
    # ============================================

    # Check if this step requires approval before execution
    def requires_approval?
      pipeline_step.requires_approval?
    end

    # Transition to waiting_approval status and trigger notifications
    def request_approval!
      return false unless pending?

      update!(status: "waiting_approval", started_at: Time.current)
      append_log("Step requires approval - waiting for user response")

      # Trigger approval notification job
      trigger_approval_notifications

      # Broadcast status update via WebSocket
      broadcast_approval_required

      true
    end

    # Handle response from approval token
    def handle_approval_response!(approved:, comment: nil, by_user: nil)
      return false unless waiting_approval?

      if approved
        append_log("Step approved#{by_user ? " by #{by_user.email}" : ''}#{comment ? ": #{comment}" : ''}")
        # Continue with actual execution
        enqueue_execution
      else
        append_log("Step rejected#{by_user ? " by #{by_user.email}" : ''}#{comment ? ": #{comment}" : ''}")
        complete!("failure", error_message: "Step rejected: #{comment || 'No reason provided'}")
      end

      # Broadcast status update
      broadcast_approval_response(approved: approved, by_user: by_user)

      true
    end

    def waiting_approval?
      status == "waiting_approval"
    end

    private

    def trigger_approval_notifications
      # Get recipients from step or pipeline settings
      recipients = pipeline_step.approval_recipients

      return if recipients.empty?

      # Enqueue notification job via backend API (worker will create tokens and send emails)
      WorkerJobService.enqueue_job(
        job_class: "Devops::ApprovalNotificationJob",
        args: [id, recipients],
        queue: "email"
      )
    rescue StandardError => e
      Rails.logger.error("Failed to trigger approval notifications for step execution #{id}: #{e.message}")
    end

    def broadcast_approval_required
      DevopsPipelineChannel.broadcast_step_update(
        pipeline_run.pipeline,
        self,
        event: "approval_required"
      )
    end

    def broadcast_approval_response(approved:, by_user:)
      DevopsPipelineChannel.broadcast_step_update(
        pipeline_run.pipeline,
        self,
        event: approved ? "approval_granted" : "approval_rejected",
        responded_by: by_user&.email
      )
    end

    # Override failure status for CI/CD convention
    def failure_status
      "failure"
    end

    def notify_pipeline_run
      return unless completed?

      # Check if all steps are completed
      all_executions = pipeline_run.step_executions.reload
      return unless all_executions.all?(&:completed?)

      # Determine pipeline run result
      if all_executions.any?(&:failed?)
        pipeline_run.complete!("failure")
      else
        pipeline_run.complete!("success")
      end
    end
  end
end
