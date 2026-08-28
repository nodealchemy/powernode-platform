# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class RalphLoopsController < InternalBaseController
          # POST /api/v1/internal/ai/ralph_loops/process_scheduled
          def process_scheduled
            heal_stuck_autonomous_loops

            processed = 0
            skipped = 0

            ::Ai::RalphLoop.due_for_execution.includes(:account, :default_agent, :campaign).find_each do |loop|
              begin
                if loop.account&.ai_suspended?
                  skipped += 1
                  next
                end

                # Campaign loops are gated by driver_kind + the single-driver lease so the
                # platform executor and a Claude Code session never drain the same campaign
                # at once. Skip CC-driven campaign loops; for platform-driven ones, take the
                # lease (skip if a different driver — e.g. a CC session — already holds it).
                if platform_drain_blocked?(loop)
                  skipped += 1
                  next
                end

                Powernode::ExtensionRegistry.provider(:ralph_loop_cycle_broadcast)&.call(loop, "overseer_cycle_started")

                service = ::Ai::Ralph::ExecutionService.new(ralph_loop: loop)
                result = service.run_iteration

                if result[:success]
                  loop.increment_daily_iteration_count!
                  loop.schedule_next_iteration!
                else
                  # Still advance next_scheduled_at to avoid tight-loop retries
                  loop.schedule_next_iteration! if loop.scheduling_mode.in?(%w[autonomous continuous])
                end

                Powernode::ExtensionRegistry.provider(:ralph_loop_cycle_broadcast)&.call(loop, "overseer_cycle_completed", result)
                processed += 1
              rescue StandardError => e
                Rails.logger.error "[RalphLoopScheduler] Failed to process loop #{loop.id}: #{e.message}"
                skipped += 1
              end
            end

            render_success(loops_processed: processed, loops_skipped: skipped)
          end

          # POST /api/v1/internal/ai/ralph_loops/gate_canary
          # G11 gate-integrity canary. Feeds a fixed set of known-good and
          # known-bad inputs through the verification gate (the authoritative
          # gate logic) and reports whether every verdict still matches
          # expectation. A silently-broken gate (e.g. real-test verification
          # regressing to always-pass) flips `healthy` to false. The worker's
          # AiGateCanaryJob calls this on a schedule and alerts on `healthy:false`.
          def gate_canary
            result = ::Ai::Ralph::GateCanaryService.new.run

            unless result[:healthy]
              failing = result[:checks].reject { |c| c[:ok] }.map { |c| c[:name] }
              Rails.logger.error(
                "[GateCanary] VERIFICATION GATE BROKEN — verdicts diverged for: #{failing.join(', ')}"
              )
            end

            render_success(healthy: result[:healthy], checks: result[:checks])
          end

          # POST /api/v1/internal/ai/ralph_loops/:id/run_iteration
          def run_iteration
            ralph_loop = ::Ai::RalphLoop.includes(:account, :default_agent).find(params[:id])

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

            Powernode::ExtensionRegistry.provider(:ralph_loop_cycle_broadcast)&.call(ralph_loop, "overseer_cycle_started")

            service = ::Ai::Ralph::ExecutionService.new(ralph_loop: ralph_loop)
            result = service.run_iteration

            Powernode::ExtensionRegistry.provider(:ralph_loop_cycle_broadcast)&.call(ralph_loop, "overseer_cycle_completed", result)

            if result[:success]
              render_success(
                iteration: ralph_loop.current_iteration,
                remaining: ralph_loop.max_iterations - ralph_loop.current_iteration
              )
            else
              render_error(result[:error] || "Iteration failed", status: :unprocessable_content)
            end
          rescue ActiveRecord::RecordNotFound
            render_error("Ralph loop not found", status: :not_found)
          end

          # POST /api/v1/internal/ai/ralph_loops/:id/iterations/:iteration_id/test_results
          # Async callback from AiTestExecutionJob: parse the worker's raw test
          # output, store the structured result on the iteration, and resolve the
          # gated task (the resume half of real test execution).
          def record_test_results
            ralph_loop = ::Ai::RalphLoop.find(params[:id])
            iteration = ralph_loop.ralph_iterations.find(params[:iteration_id])
            tr = params.require(:test_result).permit(:framework, :command, :exit_code, :output, :error).to_h.symbolize_keys

            # G15: scrub worker-originated test output/error at the persistence
            # boundary before it is evaluated, stored, or displayed — the worker
            # posts RAW suite output, which can echo secrets (env dumps, failing
            # request bodies). Done here so every stored copy (check_results) is
            # already redacted, regardless of any worker-side scrubbing.
            tr[:output] = ::DataManagement::Sanitizer.sanitize_output(tr[:output]) if tr[:output].present?
            tr[:error]  = ::DataManagement::Sanitizer.sanitize_output(tr[:error]) if tr[:error].present?

            evaluation = ::Ai::Ralph::TestVerificationService.new.evaluate(
              framework: tr[:framework], output: tr[:output], exit_code: tr[:exit_code], command: tr[:command]
            )
            # A worker-side error (couldn't even run the suite) is a failure; surface it.
            evaluation = evaluation.merge(success: false, error: tr[:error]) if tr[:error].present?

            iteration.update!(
              check_results: (iteration.check_results || {}).merge(
                "test_result" => evaluation.stringify_keys, "awaiting_test_result" => false
              ),
              checks_passed: evaluation[:success]
            )

            resolve_task_after_tests(iteration, evaluation)

            render_success(iteration_id: iteration.id, passed: evaluation[:success], summary: evaluation[:summary])
          rescue ActiveRecord::RecordNotFound
            render_error("Ralph loop or iteration not found", status: :not_found)
          end

          private

          # Resolve the task once real test results arrive. On pass: complete it
          # (resetting repeating tasks). On fail: leave it pending/in_progress so
          # the loop retries with the failure now visible on the iteration (the
          # replan edge — the next iteration can read check_results.test_result).
          def resolve_task_after_tests(iteration, evaluation)
            task = iteration.ralph_task
            return unless task

            if evaluation[:success]
              task.pass!(iteration_number: iteration.iteration_number)
              task.reset! if task.repeating?
            elsif task.status == "blocked"
              task.update_columns(status: "pending", updated_at: Time.current)
            end
          end

          # True when the platform executor must NOT drain this loop right now. Legacy loops
          # (no campaign / nil driver_kind) are never blocked. A flat-rate CLI-driven
          # campaign loop is always skipped (a Claude Code or other CLI session drains it).
          # A platform-driven campaign loop is drained only if this executor can hold the
          # single-driver lease — if a different driver (e.g. a CLI session mid-handoff)
          # holds it, skip until it's released.
          PLATFORM_LEASE_HOLDER = "platform-executor"

          def platform_drain_blocked?(loop)
            # A blank driver_kind is NOT an exemption — it previously returned false here
            # (= platform executor drains it), skipping the lease. An unrouted campaign loop
            # now falls through to the blank?-check below, which blocks.
            return false if loop.campaign_id.blank?

            # Re-read driver_kind: a concurrent #delegate may have flipped this loop to a
            # flat-rate CLI driver since due_for_execution loaded it.
            loop.reload
            return true if loop.driver_kind.blank? || loop.flat_rate_executor?

            campaign = loop.campaign
            return false unless campaign

            !campaign.acquire_driver_lease!(holder: PLATFORM_LEASE_HOLDER)
          end

          def heal_stuck_autonomous_loops
            ::Ai::RalphLoop
              .where(status: "completed", scheduling_mode: %w[autonomous continuous], schedule_paused: false)
              .joins(:ralph_tasks).where(ai_ralph_tasks: { repeating: true }).distinct
              .find_each do |loop|
                Rails.logger.info("[RalphLoopScheduler] Self-healing: reactivating loop #{loop.id} (#{loop.name})")
                loop.update_columns(status: "running", completed_at: nil)
                loop.ralph_tasks.where(status: "failed", repeating: true).find_each(&:reset!)
                loop.schedule_next_iteration!
              end
          rescue StandardError => e
            Rails.logger.error("[RalphLoopScheduler] Self-healing failed: #{e.message}")
          end
        end
      end
    end
  end
end
