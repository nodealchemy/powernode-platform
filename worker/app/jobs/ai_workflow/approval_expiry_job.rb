# frozen_string_literal: true

module AiWorkflow
  # Job to expire stale AI workflow approval tokens and fail their associated node executions
  # Runs on a schedule (hourly) to clean up pending approvals that have timed out
  class ApprovalExpiryJob < BaseJob
    sidekiq_options queue: 'default', retry: 3

    def execute
      logger.info "Running AI workflow approval token expiry check"

      # Call backend API to expire stale tokens
      response = api_client.post('/api/v1/internal/ai_workflow_approvals/expire_stale')

      if response[:success]
        expired_count = response.dig(:data, 'expired_count') || 0
        failed_executions_count = response.dig(:data, 'failed_executions_count') || 0

        logger.info "AI workflow approval expiry completed: #{expired_count} tokens expired, #{failed_executions_count} node executions failed"

        {
          success: true,
          expired_count: expired_count,
          failed_executions_count: failed_executions_count
        }
      else
        logger.error "Failed to expire AI workflow approval tokens: #{response[:error]}"
        {
          success: false,
          error: response[:error]
        }
      end
    rescue BackendApiClient::ApiError => e
      logger.error "API error during AI workflow approval expiry: #{e.message}"
      {
        success: false,
        error: e.message
      }
    end
  end
end
