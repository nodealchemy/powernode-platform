# frozen_string_literal: true

module Devops
  # Job to expire stale approval tokens and fail their associated step executions
  # Runs on a schedule (hourly) to clean up pending approvals that have timed out
  class ApprovalExpiryJob < BaseJob
    sidekiq_options queue: 'default', retry: 3

    def execute
      logger.info "Running DevOps approval token expiry check"

      # Call backend API to expire stale tokens
      response = api_client.post('/api/v1/internal/devops/approval_tokens/expire_stale')

      if response[:success]
        expired_count = response.dig(:data, 'expired_count') || 0
        failed_steps_count = response.dig(:data, 'failed_steps_count') || 0

        logger.info "Approval expiry completed: #{expired_count} tokens expired, #{failed_steps_count} step executions failed"

        {
          success: true,
          expired_count: expired_count,
          failed_steps_count: failed_steps_count
        }
      else
        logger.error "Failed to expire approval tokens: #{response[:error]}"
        {
          success: false,
          error: response[:error]
        }
      end
    rescue BackendApiClient::ApiError => e
      logger.error "API error during approval expiry: #{e.message}"
      {
        success: false,
        error: e.message
      }
    end
  end
end
