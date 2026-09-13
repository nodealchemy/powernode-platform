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
          include Api::V1::Internal::WorkerTenancy

          # POST /api/v1/internal/ai/evaluations/run
          #
          # D4 review F2 — both lookups are anchored on the CALLING worker's
          # account (WorkerTenancy#account_scope), never on the posted id alone.
          # An account id that is not the worker's own, an execution that was
          # never recorded, and another account's execution all answer the SAME
          # 404, so the door discloses nothing about rows it will not serve and
          # nothing is judged or written. AgentEvaluationJob treats that 404 as
          # terminal, so none of the three is retried.
          def run
            account = account_scope.find(params[:account_id])
            execution = ::Ai::AgentExecution.where(account_id: account.id).find(params[:execution_id])

            result = ::Ai::Learning::EvaluationService
              .new(account: account)
              .evaluate_execution(execution: execution, task_id: params[:task_id].presence)

            render_success(result)
          rescue ActiveRecord::RecordNotFound
            render_error("Execution not found", status: :not_found)
          end
        end
      end
    end
  end
end
