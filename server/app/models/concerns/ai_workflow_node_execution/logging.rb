# frozen_string_literal: true

module AiWorkflowNodeExecution::Logging
  extend ActiveSupport::Concern

  # Logging methods that delegate to workflow run but include node context
  def log_info(event_type, message, context = {})
    ai_workflow_run.log(
      "info",
      event_type,
      message,
      context.merge("node_id" => node_id, "execution_id" => execution_id),
      self
    )
  end

  def log_error(event_type, message, context = {})
    ai_workflow_run.log(
      "error",
      event_type,
      message,
      context.merge("node_id" => node_id, "execution_id" => execution_id),
      self
    )
  end

  def log_warning(event_type, message, context = {})
    ai_workflow_run.log(
      "warn",
      event_type,
      message,
      context.merge("node_id" => node_id, "execution_id" => execution_id),
      self
    )
  end
end
