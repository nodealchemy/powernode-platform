# frozen_string_literal: true

module Ai
  module Ralph
    class ExecutionService
      module IterationExecution
        extend ActiveSupport::Concern

        # Run a single iteration of the loop
        def run_iteration
          return error_result("Loop is not running") unless ralph_loop.status == "running"
          return complete_loop_result if ralph_loop.all_tasks_completed?
          return max_iterations_result if ralph_loop.max_iterations_reached?
          # G5: runtime resource caps — wall-clock for any loop, token/$ for
          # metered loops only (flat-rate claude_code loops stay uncapped by design).
          if (cap = ralph_loop.runtime_cap_reason)
            return cap_exceeded_result(cap)
          end

          task = select_next_task
          return no_task_result unless task

          iteration = if task.in_progress?
                        resume_task_iteration(task)
                      else
                        start_fresh_iteration(task)
                      end

          success_result(
            iteration: iteration.iteration_summary,
            loop: ralph_loop.reload.loop_summary,
            next_action: determine_next_action
          )
        rescue StandardError => e
          Rails.logger.error("Ralph iteration failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
          error_result("Iteration failed: #{e.message}")
        end

        # Select the next task to work on
        def select_next_task
          # First, resume any in-progress task (after crash/restart) — but skip a
          # task parked awaiting async test results, or the loop would re-run it
          # before the test-results callback resolves it. The await flag is set
          # whenever real_test_execution gates a commit — which, since G1, is the
          # default path (opt-out), not just an opt-in one.
          in_progress = ralph_loop.ralph_tasks.in_progress.find { |t| !awaiting_test_result?(t) }
          return in_progress if in_progress

          # Update blocked status for all tasks
          update_blocked_tasks

          # Get next pending task by priority. execution_type "human" is excluded —
          # those surface for operators only, never for the autonomous executor
          # (mirrors DevLoopTool#claimable_task).
          ralph_loop.ralph_tasks
                    .pending
                    .where.not(execution_type: "human")
                    .by_priority
                    .find { |t| t.dependencies_satisfied? }
        end

        # True when the task's latest iteration is awaiting an async test result.
        def awaiting_test_result?(task)
          latest = task.ralph_iterations.order(iteration_number: :desc).first
          latest&.check_results&.dig("awaiting_test_result") == true
        end

        # Update the progress text for the loop
        def update_progress(text)
          ralph_loop.update!(progress_text: text)
          success_result(progress_text: text)
        end

        private

        # Start a brand-new iteration for a pending task.
        def start_fresh_iteration(task)
          task.start!
          run_task_iteration(task)
        end

        # Resume an in-progress task that was interrupted (crash, timeout, restart).
        # Cleans up any orphaned running iterations before retrying.
        def resume_task_iteration(task)
          task.resume!
          fail_orphaned_iterations!(task)
          update_progress("Resuming task #{task.task_key} (attempt #{task.execution_attempts})")
          run_task_iteration(task)
        end

        # Shared execution logic for both fresh and resumed tasks.
        def run_task_iteration(task)
          iteration = ralph_loop.create_iteration(task: task)
          iteration.start!

          prompt = build_task_prompt(task)
          iteration.update!(ai_prompt: prompt)

          executor = Ai::Ralph::TaskExecutor.new(task: task, ralph_loop: ralph_loop, user: user)
          result = executor.execute

          if result[:success]
            process_successful_iteration(iteration, task, result)
          else
            process_failed_iteration(iteration, task, result)
          end

          iteration
        end

        # Fail any iterations left in "running" state from a previous crash.
        # Without this, orphaned iterations accumulate and skew metrics.
        def fail_orphaned_iterations!(task)
          task.ralph_iterations.running.find_each do |orphan|
            orphan.fail!(
              error_message: "Orphaned iteration — task resumed after interruption",
              error_code: "ORPHANED"
            )
          end
        end

        def build_task_prompt(task)
          context = {
            task_key: task.task_key,
            description: task.description,
            acceptance_criteria: task.acceptance_criteria,
            repository: ralph_loop.repository_url,
            branch: ralph_loop.branch,
            previous_learnings: ralph_loop.recent_learnings(limit: 5),
            iteration: ralph_loop.current_iteration + 1
          }

          # Inject shared learnings from global pool
          shared_learnings_text = inject_shared_learnings(task)

          # Build structured prompt
          <<~PROMPT
            ## Task: #{task.task_key}

            #{task.description}

            ### Acceptance Criteria
            #{task.acceptance_criteria || "No specific criteria defined"}

            ### Context
            - Repository: #{context[:repository] || "Not specified"}
            - Branch: #{context[:branch]}
            - Iteration: #{context[:iteration]}

            ### Previous Learnings
            #{format_learnings(context[:previous_learnings])}

            #{shared_learnings_text}

            ### Instructions
            Complete this task according to the acceptance criteria.
            Provide clear output showing what was done.
            Mark discoveries with `Discovery:`, patterns with `Pattern:`, warnings with `Anti-pattern:`, and best practices with `Best practice:`.
          PROMPT
        end

        def format_learnings(learnings)
          return "No previous learnings" if learnings.blank?

          learnings.map { |l| "- #{l['text']}" }.join("\n")
        end

        def process_successful_iteration(iteration, task, result)
          # G15: scrub secrets/credentials out of loop output BEFORE it is persisted
          # or fed into the learning store — the autonomous executor's output is
          # otherwise stored raw.
          scrubbed_output = ::DataManagement::Sanitizer.sanitize_output(result[:output])

          # IMP-aa8a2f58e01e: result[:checks_passed] is the executor's SELF-REPORT.
          # Adjudicate it against the run's own transcript with the same tally
          # vocabulary as the dev-loop bridge before anything records or acts on
          # it: a green tally verifies, a failing tally contradicts (the task is
          # NOT passed below), and prose-only evidence records as attested
          # (checks_passed false) while still passing. When the G1 sandboxed-test
          # gate dispatches, its async callback later overwrites this with
          # stronger evidence.
          evidence_verdict =
            if result[:checks_passed]
              ::Ai::Ralph::TestVerificationService
                .adjudicate_check_results("output" => scrubbed_output.to_s)[:verdict]
            end

          iteration.complete!(
            output: scrubbed_output,
            checks_passed: result[:checks_passed] && evidence_verdict == :verified,
            commit_sha: result[:commit_sha],
            learning: extract_learning(scrubbed_output)
          )

          # LOUD served-by attribution: when the maker's call refused and fell back
          # (e.g. Fable→Opus), record which model actually served on the iteration
          # so it's visible AND the maker/checker gate below can honor the served
          # model. No-op on the normal (no-fallback) path.
          if result[:served_by].present?
            category = result.dig(:refusal_recovery, "category") || "unknown"
            iteration.update!(ai_response_metadata: (iteration.ai_response_metadata || {}).merge(
              "served_by" => result[:served_by],
              "refusal_category" => result.dig(:refusal_recovery, "category"),
              "served_by_note" => "served by #{result[:served_by]} — Fable refused: #{category}"
            ))
            Rails.logger.warn(
              "[IterationExecution] iteration #{iteration.id} served by #{result[:served_by]} " \
              "(Fable refused: #{category})"
            )
          end

          # Set git_branch when commits were made
          if result[:commit_sha].present?
            iteration.update_columns(git_branch: ralph_loop.branch)
          end

          iteration.record_token_usage(
            input: result.dig(:tokens, :input) || 0,
            output: result.dig(:tokens, :output) || 0,
            cost: result[:cost]
          )

          # G10: scope guardrail (platform executor path). A commit touching a
          # protected path (payments/auth/crypto/secrets) or a critical-tier file is
          # NOT auto-passed — it is BLOCKED for human review, mirroring the dev-loop
          # pull path. Short-circuits FIRST (before G3 maker/checker, the G1 test
          # gate, and any pass): no matter how good the change is, the autonomous loop
          # must not auto-advance a protected-path change.
          if (guardrail = scope_guardrail_block(result))
            block_for_scope_guardrail!(iteration, task, guardrail)
          # G3: semantic maker/checker gate (opt-in via configuration["maker_checker"]).
          # A separately-modeled checker (self-review ban) judges the output; a
          # reject/revise verdict keeps the task for retry. It COMPOSES WITH — never
          # replaces — the G1 sandboxed-test gate below: a semantic failure
          # short-circuits BEFORE we trust checks_passed or dispatch a test run.
          elsif maker_checker_gate_failed?(iteration, task, scrubbed_output, result)
            verdict = iteration.check_results["evaluator_verdict"]
            update_progress("Task #{task.task_key}: checker verdict '#{verdict}' — will retry")
          elsif ralph_loop.real_test_execution? && result[:commit_sha].present?
            # Don't trust the executor's self-reported checks_passed — run the
            # suite in a sandbox and let the async callback resolve the task.
            dispatch_real_test_verification(iteration, task)
          elsif result[:checks_passed] && evidence_verdict == :contradicted
            # The transcript carries a failing tally despite the claimed pass —
            # treat it as failed checks, never as a pass.
            update_progress("Task #{task.task_key}: transcript contradicts claimed pass — will retry")
          elsif result[:checks_passed]
            task.pass!(iteration_number: iteration.iteration_number)
            task.reset! if task.repeating?
          else
            # Checks failed, task needs retry
            update_progress("Task #{task.task_key}: Checks failed, will retry")
          end

          ralph_loop.increment_iteration!

          # Extract and store shared learnings (from the scrubbed output)
          store_iteration_learnings(scrubbed_output)

          # inc6: feed the executor-run outcome back onto the governed routing
          # decision (benefit measurement). A successful iteration means the model
          # produced a usable result for its tier selection.
          record_routing_decision_outcome(result, iteration, succeeded: true)

          # Broadcast real-time updates
          broadcast_iteration_completed(iteration)
          broadcast_task_status_changed(task)
          broadcast_progress
        end

        # Park the task awaiting async test results and dispatch the sandboxed run.
        # The task is NOT passed here; AiTestExecutionJob posts back to the
        # test_results callback, which resolves it. select_next_task skips the
        # task while the await flag is set so it isn't re-run in the meantime.
        def dispatch_real_test_verification(iteration, task)
          iteration.update!(check_results: (iteration.check_results || {}).merge("awaiting_test_result" => true))

          ::WorkerJobService.enqueue_ai_test_execution(
            ralph_loop_id: ralph_loop.id,
            ralph_iteration_id: iteration.id,
            repository: ralph_loop.repository_full_name,
            branch: ralph_loop.branch,
            command: ralph_loop.test_command,
            framework: ralph_loop.configuration&.dig("test_framework")
          )
          update_progress("Task #{task.task_key}: running tests in sandbox")
        rescue StandardError => e
          Rails.logger.error("[IterationExecution] test dispatch failed for iteration #{iteration.id}: #{e.message}")
          # Don't strand the task: clear the flag so the next tick can retry it.
          iteration.update!(check_results: (iteration.check_results || {}).merge("awaiting_test_result" => false))
        end

        # G10: evaluate the iteration's committed change against the loop scope
        # guardrail. Only fires when a commit was made (a change that would land);
        # returns the violation result hash, or nil when clean / no file list.
        # Reuses the shared ScopeGuardrail.violation_for seam (loop risk_contract +
        # configuration["scope_guardrail"]). If the executor reports a commit but no
        # file list, evaluate() sees no paths and returns clean — a known limitation,
        # the same one noted on the dev-loop path.
        def scope_guardrail_block(result)
          return nil if result[:commit_sha].blank?

          ::Ai::CodeFactory::ScopeGuardrail.violation_for(
            changed_files_from_result(result), loop_record: ralph_loop
          )
        end

        # Record the guardrail verdict on the iteration and BLOCK the task for human
        # review (never pass). Parks an operator question on the loop's campaign when
        # present (best-effort — a park failure must not wedge the loop). Violations
        # carry only file PATHS + reasons (never secret values), so they are safe to
        # persist/display.
        def block_for_scope_guardrail!(iteration, task, guardrail)
          iteration.update!(check_results: (iteration.check_results || {}).merge(
            "scope_guardrail" => {
              "blocked"      => true,
              "violations"   => Array(guardrail[:violations]).map { |v| v.transform_keys(&:to_s) },
              "highest_tier" => guardrail[:highest_tier],
              "summary"      => guardrail[:summary]
            }
          ))

          reason = "[scope-guardrail] #{guardrail[:summary]} — parked for human review"
          task.block!(reason: reason, blocked_for: "review") if task.can_block?

          begin
            ralph_loop.campaign&.park_question!(
              question: "Scope guardrail blocked an autonomous change: #{guardrail[:summary]}",
              context: "scope-guardrail"
            )
          rescue StandardError => e
            Rails.logger.warn("[IterationExecution] scope-guardrail park failed for loop #{ralph_loop.id}: #{e.message}")
          end

          update_progress("Task #{task.task_key}: scope guardrail blocked — parked for human review")
        end

        # Normalize the executor-reported changed files (strings or {path:} hashes)
        # into a flat path list. Shared by the guardrail check and the maker/checker
        # output summary.
        def changed_files_from_result(result)
          Array(result[:file_changes]).map do |c|
            c.is_a?(Hash) ? (c[:path] || c["path"]) : c
          end.compact
        end

        # G3: run the independently-modeled semantic checker when maker/checker is
        # enabled for this loop. Records the verdict/scores/feedback on the
        # iteration's check_results and returns true when the verdict is NOT "pass"
        # (reject/revise ⇒ keep the task for retry). Returns false (pass-through)
        # when disabled, when the self-review ban can't be satisfied (no checker
        # model distinct from the maker/executor), or on a wiring error — a checker
        # outage must never wedge the loop, and the G1 test gate still runs.
        def maker_checker_gate_failed?(iteration, task, output, result)
          # Compare the self-review ban against the model that ACTUALLY served the
          # maker (served_by, when it fell back), not the configured model — so a
          # Fable→Opus maker fallback can't silently collide with an Opus checker.
          served_maker = result[:served_by].presence ||
                         iteration.ai_response_metadata&.dig("served_by")
          policy = Ai::Ralph::MakerCheckerPolicy.new(ralph_loop, served_maker_model: served_maker)
          return false unless policy.enabled?

          unless policy.distinct_checker?
            Rails.logger.warn(
              "[IterationExecution] maker/checker skipped for loop #{ralph_loop.id}: " \
              "no checker model distinct from maker '#{policy.maker_model}' (self-review ban)"
            )
            return false
          end

          verdict = Ai::Reasoning::OutputEvaluatorService
                    .new(account: ralph_loop.account)
                    .evaluate(
                      task: checker_task_text(task),
                      output: checker_output_text(output, result),
                      criteria: policy.criteria,
                      llm_client: ::WorkerLlmClient.new(agent_id: policy.checker_agent_id),
                      model: policy.checker_model
                    )

          iteration.update!(check_results: (iteration.check_results || {}).merge(
            "evaluator_verdict"  => verdict[:verdict],
            "evaluator_scores"   => verdict[:scores],
            "evaluator_feedback" => verdict[:feedback],
            "checker_model"      => policy.checker_model
          ))

          verdict[:verdict] != "pass"
        rescue StandardError => e
          Rails.logger.error("[IterationExecution] maker/checker gate failed for iteration #{iteration.id}: #{e.message}")
          false
        end

        # The checker evaluates against the task's intent + acceptance criteria.
        def checker_task_text(task)
          [
            task.description,
            ("Acceptance criteria: #{task.acceptance_criteria}" if task.acceptance_criteria.present?)
          ].compact.join("\n\n")
        end

        # Compose the checker's review input. PREFERS the REAL unified diff of the
        # iteration's commit (result[:diff], captured best-effort by the git-tool
        # executor and already size-capped) so the checker reviews the actual patch.
        # The diff is run through DataManagement::Sanitizer.sanitize_output first —
        # consistent with G15 — so a secret planted in the change never reaches the
        # evaluator LLM. FALLS BACK to the output text + commit SHA + changed-files
        # summary when no diff is available (non-git executors, no commit, or a
        # diff-fetch failure) — the pre-follow-up behaviour, unchanged.
        def checker_output_text(output, result)
          parts = [output.to_s]
          parts << "Commit: #{result[:commit_sha]}" if result[:commit_sha].present?

          if (diff = result[:diff].presence)
            parts << "Unified diff:\n#{::DataManagement::Sanitizer.sanitize_output(diff)}"
          else
            changed = changed_files_from_result(result)
            parts << "Changed files: #{changed.join(', ')}" if changed.any?
          end

          parts.join("\n\n")
        end

        def process_failed_iteration(iteration, task, result)
          # G15: an executor error message can carry a leaked secret too — scrub it.
          error_message = ::DataManagement::Sanitizer.sanitize_output(result[:error])

          iteration.fail!(
            error_message: error_message,
            error_code: result[:error_code],
            error_details: result[:error_details] || {}
          )

          task.fail!(
            error_message: error_message,
            error_code: result[:error_code]
          )

          ralph_loop.increment_iteration!
          task.reset! if task.repeating?

          # inc6: record the failed executor-run outcome on the governed routing
          # decision (benefit measurement).
          record_routing_decision_outcome(result, iteration, succeeded: false)

          # Broadcast real-time updates
          broadcast_iteration_completed(iteration)
          broadcast_task_status_changed(task)
          broadcast_progress
        end

        # inc6: best-effort outcome feedback for the Ralph seam. The decision id
        # rides on the executor result (Ai::Ralph::TaskExecutor stashes it after
        # persisting the governance record); when present and not yet recorded, feed
        # success/cost/latency/tokens onto it via the existing record_outcome!. A
        # failure here must never wedge the iteration.
        def record_routing_decision_outcome(result, iteration, succeeded:)
          decision_id = result[:routing_decision_id]
          return if decision_id.blank?

          decision = ::Ai::RoutingDecision.find_by(id: decision_id)
          return unless decision && decision.outcome.blank?

          tokens = result.dig(:tokens, :input).to_i + result.dig(:tokens, :output).to_i
          decision.record_outcome!(
            outcome: succeeded ? "succeeded" : "failed",
            cost_usd: result[:cost],
            latency_ms: iteration.duration_ms,
            latency_seam: "ralph_iteration",
            tokens_used: tokens.positive? ? tokens : nil
          )
        rescue StandardError => e
          Rails.logger.error("[IterationExecution] routing outcome record failed for decision #{decision_id}: #{e.message}")
        end

        def extract_learning(output)
          return nil if output.blank?

          # Look for explicit learning markers
          if output.include?("Learning:") || output.include?("Learned:")
            output.scan(/(?:Learning|Learned):\s*(.+?)(?:\n|$)/i).flatten.first
          end
        end

        def update_blocked_tasks
          ralph_loop.ralph_tasks.blocked.find_each do |task|
            # A task parked for operator review (scope-guardrail, human review)
            # must never be silently un-parked just because its dependencies
            # happen to be satisfied — that's orthogonal to why it was blocked.
            next if task.review_parked?

            task.update!(status: "pending") if task.dependencies_satisfied?
          end

          ralph_loop.ralph_tasks.pending.find_each do |task|
            next if task.dependencies_satisfied?

            task.block!(
              reason: "Waiting for: #{task.blocking_dependencies.join(', ')}",
              blocked_for: "dependency"
            )
          end
        end
      end
    end
  end
end
