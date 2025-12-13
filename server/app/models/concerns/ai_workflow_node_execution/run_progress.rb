# frozen_string_literal: true

module AiWorkflowNodeExecution::RunProgress
  extend ActiveSupport::Concern

  # These methods are called explicitly by the orchestrator after node completion
  # They were intentionally converted from callbacks to explicit calls to prevent stack overflow

  def update_run_progress
    # Use thread-local storage for re-entry protection
    progress_key = "updating_run_progress_#{ai_workflow_run_id}"

    return if Thread.current[progress_key]

    Thread.current[progress_key] = true

    begin
      # Call the workflow run's update_progress! method
      ai_workflow_run.update_progress!
    ensure
      Thread.current[progress_key] = nil
    end
  end

  # Add cost to run - called explicitly by orchestrator after node completion
  def add_cost_to_run_explicit(cost_amount)
    return unless cost_amount.present? && cost_amount > 0

    # Use thread-local storage for re-entry protection
    cost_key = "adding_cost_to_run_#{ai_workflow_run_id}"

    return if Thread.current[cost_key]

    Thread.current[cost_key] = true

    begin
      ai_workflow_run.add_cost(cost_amount, "node_#{node_id}")
    ensure
      Thread.current[cost_key] = nil
    end
  end
end
