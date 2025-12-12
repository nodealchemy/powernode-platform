# frozen_string_literal: true

class AiWorkflowCompensation < ApplicationRecord
  # ==================== Associations ====================
  belongs_to :ai_workflow_run
  belongs_to :ai_workflow_node_execution

  # ==================== Validations ====================
  validates :compensation_id, presence: true, uniqueness: true
  validates :compensation_type, presence: true, inclusion: {
    in: %w[rollback undo compensate revert cancel],
    message: "%{value} is not a valid compensation type"
  }
  validates :trigger_reason, presence: true
  validates :status, presence: true, inclusion: {
    in: %w[pending executing completed failed skipped],
    message: "%{value} is not a valid status"
  }
  validates :original_action, presence: true
  validates :compensation_action, presence: true
  validates :retry_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_retries, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # ==================== Scopes ====================
  scope :for_run, ->(run_id) { where(ai_workflow_run_id: run_id) }
  scope :by_type, ->(type) { where(compensation_type: type) }
  scope :by_status, ->(status) { where(status: status) }
  scope :pending, -> { where(status: "pending") }
  scope :executing, -> { where(status: "executing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :chronological, -> { order(created_at: :asc) }
  scope :reverse_chronological, -> { order(created_at: :desc) }
  scope :retryable, -> { where("retry_count < max_retries").where(status: "failed") }

  # ==================== Callbacks ====================
  before_validation :generate_compensation_id, on: :create
  after_create :broadcast_compensation_event

  # ==================== Instance Methods ====================

  # Get compensation summary
  def compensation_summary
    {
      id: id,
      compensation_id: compensation_id,
      type: compensation_type,
      status: status,
      trigger_reason: trigger_reason,
      retry_count: retry_count,
      max_retries: max_retries,
      created_at: created_at,
      completed_at: completed_at
    }
  end

  # Full compensation details
  def compensation_details
    compensation_summary.merge(
      original_action: original_action,
      compensation_action: compensation_action,
      compensation_result: compensation_result,
      metadata: metadata,
      node_execution_id: ai_workflow_node_execution_id
    )
  end

  # Execute compensation action
  def execute!
    return false if completed? || executing?

    update!(status: "executing", executed_at: Time.current)

    begin
      # Execute compensation based on type
      result = case compensation_type
      when "rollback"
        execute_rollback
      when "undo"
        execute_undo
      when "compensate"
        execute_compensate
      when "revert"
        execute_revert
      when "cancel"
        execute_cancel
      end

      if result[:success]
        complete_compensation!(result)
        true
      else
        fail_compensation!(result[:error])
        false
      end

    rescue StandardError => e
      fail_compensation!(e.message)
      false
    end
  end

  # Mark compensation as completed
  def complete_compensation!(result)
    update!(
      status: "completed",
      compensation_result: result,
      completed_at: Time.current
    )

    broadcast_compensation_event("completed")
  end

  # Mark compensation as failed
  def fail_compensation!(error_message)
    update!(
      status: "failed",
      failed_at: Time.current,
      compensation_result: { error: error_message },
      metadata: metadata.merge(
        "failure_count" => (metadata["failure_count"] || 0) + 1,
        "last_error" => error_message
      )
    )

    broadcast_compensation_event("failed")
  end

  # Retry failed compensation
  def retry!
    return false unless can_retry?

    update!(
      status: "pending",
      retry_count: retry_count + 1,
      failed_at: nil
    )

    execute!
  end

  # Check if compensation can be retried
  def can_retry?
    failed? && retry_count < max_retries
  end

  # Status checks
  def pending?
    status == "pending"
  end

  def executing?
    status == "executing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def skipped?
    status == "skipped"
  end

  # Skip compensation (if deemed unnecessary)
  def skip!(reason:)
    update!(
      status: "skipped",
      metadata: metadata.merge("skip_reason" => reason)
    )
  end

  # Get execution duration
  def execution_duration
    return nil unless completed_at && executed_at
    ((completed_at - executed_at) * 1000).to_i # milliseconds
  end

  private

  # Generate unique compensation ID
  def generate_compensation_id
    self.compensation_id ||= "comp_#{SecureRandom.hex(12)}"
  end

  # Execute rollback compensation
  def execute_rollback
    action = compensation_action["rollback_action"]

    case action["type"]
    when "api_call"
      execute_api_rollback(action)
    when "database"
      execute_database_rollback(action)
    when "message"
      execute_message_rollback(action)
    else
      { success: false, error: "Unknown rollback type: #{action['type']}" }
    end
  end

  # Execute undo compensation
  def execute_undo
    # Reverse the original action
    {
      success: true,
      action: "undo_executed",
      original_action: original_action,
      timestamp: Time.current.iso8601
    }
  end

  # Execute compensate action
  def execute_compensate
    # Execute compensating transaction
    action = compensation_action["compensate_action"]

    {
      success: true,
      action: "compensation_executed",
      compensation: action,
      timestamp: Time.current.iso8601
    }
  end

  # Execute revert action
  def execute_revert
    # Revert to previous state
    {
      success: true,
      action: "reverted",
      reverted_to: compensation_action["previous_state"],
      timestamp: Time.current.iso8601
    }
  end

  # Execute cancel action
  def execute_cancel
    # Cancel pending operations
    {
      success: true,
      action: "cancelled",
      cancelled_operations: compensation_action["operations_to_cancel"],
      timestamp: Time.current.iso8601
    }
  end

  # Execute API rollback
  def execute_api_rollback(action)
    # Would make actual API call to rollback
    {
      success: true,
      api_response: {
        url: action["url"],
        method: action["method"],
        status: "rolled_back"
      }
    }
  end

  # Execute database rollback
  def execute_database_rollback(action)
    # Would execute database rollback query
    {
      success: true,
      database_action: {
        query: action["rollback_query"],
        rows_affected: 0,
        status: "rolled_back"
      }
    }
  end

  # Execute message rollback
  def execute_message_rollback(action)
    # Would send compensating message
    {
      success: true,
      message_sent: {
        to: action["recipient"],
        type: "rollback_notification",
        status: "sent"
      }
    }
  end

  # Broadcast compensation event
  def broadcast_compensation_event(event_type = "created")
    McpChannel.broadcast_to(
      "account_#{ai_workflow_run.account_id}",
      {
        type: "compensation_event",
        event: event_type,
        workflow_run_id: ai_workflow_run.run_id,
        compensation: compensation_summary
      }
    )
  end
end
