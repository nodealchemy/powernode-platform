# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        # D4 — the judge's only production entry point.
        #
        # AgentEvaluationJob (worker) posts here; the evaluation then runs
        # SYNCHRONOUSLY inside this request, which is the worker's own request.
        # That is the whole point of moving it: the previous implementation ran
        # the judge in a bare Thread.new inside a Puma request, unawaited.
        #
        # The worker sends IDS ONLY. The transcript is resolved here from the
        # execution row rather than round-tripping an agent's output through a
        # Sidekiq payload and back.
        class EvaluationsController < InternalBaseController
          # POST /api/v1/internal/ai/evaluations/run
          def run
            account = Account.find(params[:account_id])
            # find_by, not find: a deleted or never-recorded execution is an
            # ordinary not_measured answer from the service, not a 404 that
            # would make the worker retry forever.
            execution = ::Ai::AgentExecution.find_by(id: params[:execution_id])

            result = ::Ai::Learning::EvaluationService
              .new(account: account)
              .evaluate_execution(execution: execution, task_id: params[:task_id].presence)

            render_success(result)
          end
        end
      end
    end
  end
end
