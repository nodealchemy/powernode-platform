# frozen_string_literal: true

module AiWorkflowNodeExecution::RetryManagement
  extend ActiveSupport::Concern

  def can_retry?
    failed? && retry_count < max_retries
  end

  def retry_execution!
    return false unless can_retry?

    transaction do
      increment!(:retry_count)

      update!(
        status: "pending",
        started_at: nil,
        completed_at: nil,
        cancelled_at: nil,
        error_details: {},
        metadata: metadata.merge({
          "retry_attempt" => retry_count + 1,
          "retried_at" => Time.current.iso8601
        })
      )

      log_info("node_retry_scheduled", "Node execution retry scheduled (attempt #{retry_count}/#{max_retries})")
    end

    true
  end

  def exhaust_retries!
    update!(
      retry_count: max_retries,
      metadata: metadata.merge("retries_exhausted_at" => Time.current.iso8601)
    )
  end

  # Retry with strategy service
  def retry_with_strategy!(error_type = nil)
    retry_service = AiWorkflowRetryStrategyService.new(
      node_execution: self,
      error_type: error_type
    )

    if retry_service.retryable?
      retry_service.execute_retry
    else
      Rails.logger.warn "[NodeExecution] Cannot retry #{execution_id}: #{retry_service.retry_stats}"
      false
    end
  end

  # Get retry statistics
  def retry_statistics
    retry_service = AiWorkflowRetryStrategyService.new(node_execution: self)
    retry_service.retry_stats
  end

  # Check if error type is retryable
  def error_retryable?(error_type)
    retry_service = AiWorkflowRetryStrategyService.new(
      node_execution: self,
      error_type: error_type
    )
    retry_service.retryable?
  end
end
