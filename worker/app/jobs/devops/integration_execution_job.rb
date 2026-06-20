# frozen_string_literal: true

module Devops
  # Async runner for integration executions.
  #
  # Enqueued by the server's Devops::ExecutionService.execute_async as
  # "Devops::IntegrationExecutionJob" with a single payload hash
  # { execution_id:, input:, context: } (the server has already created the
  # "queued" execution record). This job simply triggers the server to run that
  # execution off the request thread; the server-side executor owns the
  # running -> completed/failed status lifecycle, so there is no status to PATCH
  # back from here.
  class IntegrationExecutionJob < BaseJob
    sidekiq_options queue: 'integrations',
                    retry: 3,
                    dead: true

    def execute(payload = {})
      payload = {} unless payload.is_a?(Hash)
      execution_id = payload['execution_id'] || payload[:execution_id]
      context = payload['context'] || payload[:context] || {}

      unless execution_id
        log_error('Integration execution missing execution_id', payload: payload)
        return { success: false, error: 'Missing execution_id' }
      end

      log_info('Running integration execution', execution_id: execution_id)

      response = api_client.post(
        "/api/v1/internal/devops/integration_executions/#{execution_id}/run",
        { context: context }
      )

      if response[:success]
        log_info('Integration execution completed', execution_id: execution_id)
        increment_counter('integration_execution_success')
      else
        log_error('Integration execution failed', execution_id: execution_id, error: response[:error])
        increment_counter('integration_execution_failure')
      end

      response
    rescue StandardError => e
      log_error('Integration execution error', exception: e, execution_id: execution_id)
      raise
    end
  end
end
