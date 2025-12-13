# frozen_string_literal: true

module AiWorkflowNodeExecution::Timing
  extend ActiveSupport::Concern

  def execution_duration
    return nil unless started_at

    end_time = completed_at || cancelled_at || Time.current
    end_time - started_at
  end

  def execution_duration_seconds
    execution_duration&.to_i
  end

  def execution_time_ms
    return duration_ms if duration_ms.present?
    return nil unless execution_duration

    (execution_duration * 1000).to_i
  end

  # Alias method for backward compatibility
  alias_method :execution_duration_ms, :execution_time_ms

  def timeout_duration
    ai_workflow_node.timeout_seconds || 300
  end

  def timed_out?
    return false unless running? && started_at

    Time.current - started_at > timeout_duration
  end

  def time_remaining
    return nil unless running? && started_at

    elapsed = Time.current - started_at
    [ timeout_duration - elapsed.to_i, 0 ].max
  end
end
