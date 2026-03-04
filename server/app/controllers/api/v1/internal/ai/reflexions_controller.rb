# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class ReflexionsController < InternalBaseController
          # POST /api/v1/internal/ai/reflexions/reflect
          # Called by AiReflexionJob to trigger post-execution reflexion
          def reflect
            execution = ::Ai::AgentExecution.find(params[:execution_id])
            account = execution.account

            service = ::Ai::Learning::ReflexionService.new(account: account)

            unless service.should_reflect?(execution)
              return render_success(reflected: false, reason: "not_eligible")
            end

            learning = service.reflect_on_failure(execution)

            if learning
              render_success(
                reflected: true,
                learning_id: learning.id,
                title: learning.title
              )
            else
              render_success(reflected: false, reason: "no_learning_produced")
            end
          rescue ActiveRecord::RecordNotFound => e
            render_error(e.message, status: :not_found)
          rescue StandardError => e
            Rails.logger.error "[Reflexion] Failed for execution #{params[:execution_id]}: #{e.message}"
            render_error("Reflexion failed: #{e.message}", status: :unprocessable_content)
          end
        end
      end
    end
  end
end
