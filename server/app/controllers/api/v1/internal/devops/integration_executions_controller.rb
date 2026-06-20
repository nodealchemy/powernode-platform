# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Devops
        # Internal API for the worker service to run a queued integration execution.
        # The worker (Devops::IntegrationExecutionJob) calls this so the integration
        # runs off the request thread; the server-side executor owns the status
        # lifecycle, so there is no separate status-update endpoint to maintain.
        class IntegrationExecutionsController < InternalBaseController
          before_action :set_execution, only: [ :run ]

          # POST /api/v1/internal/devops/integration_executions/:id/run
          def run
            result = ::Devops::ExecutionService.run_queued(
              execution: @execution,
              context: { request_id: request.request_id }
            )

            if result[:success]
              render_success({ result: result })
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          end

          private

          def set_execution
            @execution = ::Devops::IntegrationExecution.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Integration execution not found", status: :not_found)
          end
        end
      end
    end
  end
end
