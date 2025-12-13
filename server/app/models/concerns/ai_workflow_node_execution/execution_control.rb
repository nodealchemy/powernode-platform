# frozen_string_literal: true

module AiWorkflowNodeExecution::ExecutionControl
  extend ActiveSupport::Concern

  def start_execution!
    return false unless pending?

    # Capture status change manually for callback
    old_status = status
    @pending_status_change = [ old_status, "running" ]

    update!(
      status: "running",
      started_at: Time.current,
      metadata: metadata.merge("execution_started_at" => Time.current.iso8601)
    )

    # Frontend calculates elapsed time locally using started_at timestamp
  end

  def complete_execution!(output_data_hash = {}, execution_cost = 0)
    # Check if already completed
    if status == "completed"
      Rails.logger.warn "Node #{execution_id} (#{ai_workflow_node.name}) already completed, skipping"
      return false
    end

    return false unless running?

    # Use thread-local storage for re-entry protection
    executing_key = "completing_execution_#{execution_id}"

    if Thread.current[executing_key]
      Rails.logger.warn "[NodeExecution] Preventing re-entrant call to complete_execution! for #{execution_id}"
      return false
    end

    Thread.current[executing_key] = true

    begin
      # Capture status change manually for callback
      old_status = status
      @pending_status_change = [ old_status, "completed" ]

      result = update!(
        status: "completed",
        completed_at: Time.current,
        output_data: output_data.merge(output_data_hash),
        cost: cost + execution_cost.to_f,
        metadata: metadata.merge("execution_completed_at" => Time.current.iso8601)
      )

      result
    ensure
      Thread.current[executing_key] = nil
    end
  end

  def fail_execution!(error_message, error_details_hash = {})
    # Use thread-local storage for re-entry protection
    failing_key = "failing_execution_#{execution_id}"

    if Thread.current[failing_key]
      Rails.logger.warn "[NodeExecution] Preventing re-entrant call to fail_execution! for #{execution_id}"
      return false
    end

    Thread.current[failing_key] = true

    begin
      # Capture status change manually for callback
      old_status = status
      @pending_status_change = [ old_status, "failed" ]

      update!(
        status: "failed",
        completed_at: Time.current,
        error_details: error_details.merge({
          "error_message" => error_message,
          "failed_at" => Time.current.iso8601
        }.merge(error_details_hash)),
        metadata: metadata.merge("execution_failed_at" => Time.current.iso8601)
      )
    ensure
      Thread.current[failing_key] = nil
    end
  end

  def cancel_execution!(reason = "Workflow cancelled")
    return false if finished?

    # Capture status change manually for callback
    old_status = status
    @pending_status_change = [ old_status, "cancelled" ]

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

  def skip_execution!(reason = "Condition not met")
    return false unless pending?

    update!(
      status: "skipped",
      completed_at: Time.current,
      metadata: metadata.merge({
        "skip_reason" => reason,
        "skipped_at" => Time.current.iso8601
      })
    )
  end

  def request_approval!(approval_message, approvers = [])
    return false unless running?

    update!(
      status: "waiting_approval",
      metadata: metadata.merge({
        "approval_message" => approval_message,
        "approvers" => approvers,
        "approval_requested_at" => Time.current.iso8601
      })
    )
  end

  def approve_execution!(approved_by_user_id, decision_data = {})
    return false unless waiting_for_approval?

    if decision_data["approved"] == true
      update!(
        status: "running",
        metadata: metadata.merge({
          "approval_decision" => "approved",
          "approved_by" => approved_by_user_id,
          "approval_completed_at" => Time.current.iso8601,
          "approval_data" => decision_data
        })
      )
    else
      fail_execution!("Approval denied", {
        "approval_decision" => "denied",
        "denied_by" => approved_by_user_id,
        "denial_reason" => decision_data["reason"]
      })
    end
  end
end
