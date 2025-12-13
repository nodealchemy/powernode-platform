# frozen_string_literal: true

module AiWorkflowRun::StateManagement
  extend ActiveSupport::Concern

  # Status check methods
  def initializing?
    status == "initializing"
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def cancelled?
    status == "cancelled"
  end

  def waiting_for_approval?
    status == "waiting_approval"
  end

  def active?
    %w[initializing running waiting_approval].include?(status)
  end

  def finished?
    %w[completed failed cancelled].include?(status)
  end

  def successful?
    completed? && failed_nodes == 0
  end

  # Execution control methods
  def start_execution!
    return false unless initializing?

    update!(
      status: "running",
      started_at: Time.current,
      metadata: metadata.merge("execution_started_at" => Time.current.iso8601)
    )
  end

  def complete_execution!(output_vars = {})
    return false unless running?

    # Merge runtime_context variables into output_variables for workflow output display
    runtime_variables = runtime_context["variables"] || {}
    final_output_vars = output_variables.merge(runtime_variables).merge(output_vars)

    update!(
      status: "completed",
      completed_at: Time.current,
      output_variables: final_output_vars,
      metadata: metadata.merge("execution_completed_at" => Time.current.iso8601)
    )
  end

  def fail_execution!(error_message, error_details_hash = {})
    current_time = Time.current

    # Prepare update attributes
    update_attrs = {
      status: "failed",
      completed_at: current_time,
      error_details: error_details.merge({
        "error_message" => error_message,
        "failed_at" => current_time.iso8601
      }.merge(error_details_hash)),
      metadata: metadata.merge("execution_failed_at" => current_time.iso8601)
    }

    # Ensure started_at is set to satisfy validation (completed_at must be after started_at)
    if started_at.nil?
      # Set started_at to 1 second before completed_at
      update_attrs[:started_at] = current_time - 1.second
      Rails.logger.warn "[AI_WORKFLOW_RUN] Workflow run #{run_id} failed before starting - setting started_at retroactively"
    end

    update!(update_attrs)
  end

  def cancel_execution!(reason = "User cancelled")
    return false if finished?

    transaction do
      # Cancel any pending/running node executions
      ai_workflow_node_executions
        .where(status: %w[pending running waiting_approval])
        .update_all(
          status: "cancelled",
          cancelled_at: Time.current,
          error_details: { "cancellation_reason" => reason }.to_json
        )

      update!(
        status: "cancelled",
        cancelled_at: Time.current,
        completed_at: Time.current,
        error_details: error_details.merge({
          "cancellation_reason" => reason,
          "cancelled_at" => Time.current.iso8601
        }),
        metadata: metadata.merge("execution_cancelled_at" => Time.current.iso8601)
      )
    end

    true
  end

  # Alias for controller compatibility
  def cancel!(reason: "User cancelled", cancelled_by: nil)
    cancel_execution!(reason)
  end

  def pause_for_approval!(approval_node_id, approval_message)
    return false unless running?

    update!(
      status: "waiting_approval",
      metadata: metadata.merge({
        "approval_node_id" => approval_node_id,
        "approval_message" => approval_message,
        "approval_requested_at" => Time.current.iso8601
      })
    )
  end

  def resume_after_approval!(approved_by_user_id, approval_decision)
    return false unless waiting_for_approval?

    update!(
      status: "running",
      metadata: metadata.merge({
        "approval_decision" => approval_decision,
        "approved_by" => approved_by_user_id,
        "approval_completed_at" => Time.current.iso8601
      })
    )
  end

  # Retry and recovery
  def can_retry?
    failed? && ai_workflow.can_execute?
  end

  def can_cancel?
    active?
  end

  def can_pause?
    running?
  end

  def can_resume?
    status == "paused"
  end

  def retry_execution!(user = nil)
    return false unless can_retry?

    new_run = ai_workflow.execute(
      input_variables,
      user: user || triggered_by_user,
      trigger: ai_workflow_trigger,
      trigger_type: "manual"
    )

    # Link to original run
    new_run.update!(
      metadata: new_run.metadata.merge({
        "retried_from" => run_id,
        "original_run_id" => run_id,
        "retry_attempt" => (metadata["retry_attempt"] || 0) + 1
      })
    )

    new_run
  end

  # Alias for controller compatibility
  def retry!(retry_options: {}, triggered_by: nil)
    retry_execution!(triggered_by)
  end
end
