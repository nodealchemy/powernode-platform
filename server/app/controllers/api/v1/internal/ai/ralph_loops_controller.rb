# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class RalphLoopsController < InternalBaseController
          # POST /api/v1/internal/ai/ralph_loops/process_scheduled
          def process_scheduled
            processed = 0
            skipped = 0

            ::Ai::RalphLoop.due_for_execution.includes(:account).find_each do |loop|
              begin
                if loop.account&.ai_suspended?
                  skipped += 1
                  next
                end

                service = ::Ai::Ralph::ExecutionService.new(ralph_loop: loop)
                service.run_iteration
                processed += 1
              rescue StandardError => e
                Rails.logger.error "[RalphLoopScheduler] Failed to process loop #{loop.id}: #{e.message}"
                skipped += 1
              end
            end

            render_success(loops_processed: processed, loops_skipped: skipped)
          end

          # POST /api/v1/internal/ai/ralph_loops/:id/run_iteration
          def run_iteration
            ralph_loop = ::Ai::RalphLoop.includes(:account).find(params[:id])

            # Kill switch check
            if ralph_loop.account&.ai_suspended?
              return render_success(cancelled: true, message: "AI activity suspended for this account")
            end

            # Check if loop is still active
            unless ralph_loop.run_all_active?
              return render_success(cancelled: true, message: "Loop execution cancelled")
            end

            # Check if all iterations are done
            if ralph_loop.current_iteration >= ralph_loop.max_iterations
              return render_success(completed: true, message: "All iterations completed")
            end

            service = ::Ai::Ralph::ExecutionService.new(ralph_loop: ralph_loop)
            result = service.run_iteration

            if result[:success]
              render_success(
                iteration: ralph_loop.current_iteration,
                remaining: ralph_loop.max_iterations - ralph_loop.current_iteration
              )
            else
              render_error(result[:error] || "Iteration failed", status: :unprocessable_entity)
            end
          rescue ActiveRecord::RecordNotFound
            render_error("Ralph loop not found", status: :not_found)
          end
        end
      end
    end
  end
end
