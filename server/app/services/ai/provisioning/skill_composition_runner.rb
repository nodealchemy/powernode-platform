# frozen_string_literal: true

module Ai
  module Provisioning
    # Executes a provisioning plan (typically an Ai::GoalPlan whose steps were
    # rewritten by PlanComposerService into step_type: "provisioning_skill") as
    # a DAG of skill invocations.
    #
    # The runner is server-side and orchestrates by parallel-safe layers:
    #   1. execute! — kick off the run by enqueueing every step in the first
    #      ready layer through WorkerJobService.enqueue_job("AiProvisioningStepJob", …).
    #      Returns immediately with the runner_id, started_at, and step_count
    #      so the caller (worker job → internal API) can record provenance.
    #   2. execute_step!(step) — the per-step entrypoint. The step worker job
    #      calls back into this method via the internal API; here we resolve
    #      the skill executor, run it with the step's inputs, mark progress,
    #      and dispatch any newly-unblocked successors. On step failure with
    #      execution_config[:on_failure] == "rollback", we compensate the
    #      FAILED STEP'S OWN recorded resources — and nothing else. Rollback
    #      previously walked completed predecessors and, live (dryrun
    #      20260809b, IMP 019fe5d7-1089), terminated a sibling step's healthy
    #      instance 20s after its successful provision, triggered by a step
    #      that had failed on input validation and created nothing. Whether
    #      healthy siblings should survive a partial plan failure is a
    #      disposition question that belongs to the verify phase and the
    #      operator gates, not to an automatic unwind.
    #   3. rollback_step!(step) — invokes the executor's descriptor[:rollback]
    #      method (if any) with the step's previously-recorded outputs, then
    #      marks the step as rolled back / failed. A hook that REPORTS failure
    #      ({ success: false, errors: }) is surfaced as rollback_failed, not
    #      swallowed — live, a VM that survived its own rollback was invisible.
    #
    # Each transition emits two side effects (best-effort, logged on failure):
    #   - mission.conversation.add_system_message — chat surface activity
    #   - MissionChannel.broadcast_mission_event — live UI streaming
    #
    # Plan / step contract (consumed, produced by PlanComposerService):
    #   plan.steps.in_order  → Enumerable<Step> (ordered by step_number)
    #   step.id              → String (passed to step worker job)
    #   step.step_number     → Integer (used as dependency token)
    #   step.dependencies    → Array<Integer> (predecessor step_numbers)
    #   step.execution_config → { "skill" => String, "inputs" => Hash,
    #                             "on_failure" => "rollback"|"continue" }
    class SkillCompositionRunner
      ACTIVITY_TYPE = "provisioning_step_progress"
      EVENT_TYPE    = "provisioning_step_changed"
      RUN_START_EVENT = "provisioning_run_started"

      # Step statuses that mean "this step is past the pending gate" — used
      # by the execute! and execute_step! idempotency guards to detect a
      # concurrent or completed run.
      IN_FLIGHT_STATUSES = %w[executing completed failed].freeze

      attr_reader :account, :mission, :plan, :runner_id, :started_at

      def initialize(account:, mission:, plan:)
        @account = account
        @mission = mission
        @plan = plan
        @runner_id = nil
        @started_at = nil
      end

      # Kick off the DAG run. Computes parallel-safe layers from
      # step.dependencies, dispatches the first layer of step jobs, and
      # records run-start side effects.
      #
      # Idempotent: if any step in the plan is already past `pending`, a
      # previous run is in flight (or completed) — return that run's signal
      # without re-dispatching. Two callers race for `execute!` whenever the
      # approve flow's worker job and the Concierge LLM's tool both fire on
      # the same approval (the LLM was historically over-eager); without
      # this guard we'd double-provision every infrastructure step.
      #
      # @return [Hash] { runner_id:, started_at:, step_count: }
      def execute!
        ordered_steps = steps_in_order
        step_count = ordered_steps.size

        if (in_flight = ordered_steps.find { |s| IN_FLIGHT_STATUSES.include?(step_status(s)) })
          Rails.logger.info(
            "[SkillCompositionRunner] execute! no-op — plan #{plan.id[0..7]} " \
            "already has step in '#{step_status(in_flight)}'; returning existing runner state."
          )
          @runner_id ||= ::UUID7.generate
          @started_at ||= Time.current
          return { runner_id: @runner_id, started_at: @started_at, step_count: step_count, already_running: true }
        end

        @runner_id = ::UUID7.generate
        @started_at = Time.current

        layers = topological_layers(ordered_steps)

        broadcast_run_started(step_count: step_count, layer_count: layers.size)
        post_system_message(
          "Provisioning run started — #{step_count} step(s) across #{layers.size} layer(s).",
          status: "started",
          metadata: { runner_id: @runner_id, step_count: step_count, layer_count: layers.size }
        )

        # Dispatch the first ready layer; subsequent layers are dispatched
        # by execute_step! as predecessors complete.
        first_layer = layers.first || []
        first_layer.each { |step| dispatch_step_job(step) }

        { runner_id: @runner_id, started_at: @started_at, step_count: step_count }
      end

      # Dispatch a specific set of newly-APPENDED pending steps on this plan
      # (IMP-8c37b9e5ccd5). Used by Ai::Provisioning::AdaptationDispatchService
      # when an `adaptation_diff` is grafted onto a live mission's plan.
      #
      # #execute! cannot serve this. Its idempotency guard refuses to dispatch
      # when ANY step on the plan is past `pending` — the guard that stops a
      # double-provision when two callers race an approval — and a live plan's
      # original steps are all `completed`. Calling #execute! on an adapted plan
      # would therefore no-op every adaptation while reporting a runner_id.
      # Here both the guard and the topological layering are scoped to the
      # appended subset; the completed originals are neither re-run nor
      # consulted.
      #
      # The appended steps are layered against the plan's COMPLETED steps (see
      # #topological_layers), so a subset whose dependencies all finished
      # outside it lands in layer 1 rather than tripping the cycle backstop.
      #
      # @param steps [Array<#step_number, #dependencies, …>] the appended steps
      # @return [Hash] { runner_id:, started_at:, step_count:, dispatched:,
      #   dispatched_step_numbers: }
      def execute_appended!(steps:)
        appended = Array(steps).sort_by { |s| s.step_number.to_i }
        if appended.empty?
          return { runner_id: nil, started_at: nil, step_count: 0, dispatched: 0,
                   dispatched_step_numbers: [] }
        end

        if (in_flight = appended.find { |s| IN_FLIGHT_STATUSES.include?(step_status(s)) })
          Rails.logger.info(
            "[SkillCompositionRunner] execute_appended! no-op — appended step " \
            "#{step_id(in_flight)[0..7]} already in '#{step_status(in_flight)}'."
          )
          @runner_id ||= ::UUID7.generate
          @started_at ||= Time.current
          return { runner_id: @runner_id, started_at: @started_at,
                   step_count: appended.size, dispatched: 0,
                   dispatched_step_numbers: [], already_running: true }
        end

        @runner_id = ::UUID7.generate
        @started_at = Time.current

        layers = topological_layers(appended)

        broadcast_run_started(step_count: appended.size, layer_count: layers.size)
        post_system_message(
          "Adaptation run started — #{appended.size} appended step(s) across #{layers.size} layer(s).",
          status: "started",
          metadata: { runner_id: @runner_id, step_count: appended.size, layer_count: layers.size }
        )

        first_layer = layers.first || []
        first_layer.each { |step| dispatch_step_job(step) }

        # WHICH steps were enqueued, not merely how many. The caller reports
        # this to an operator, and only layer 1 goes to a worker now — inferring
        # it from the collection handed over would name steps nothing has run.
        { runner_id: @runner_id, started_at: @started_at,
          step_count: appended.size, dispatched: first_layer.size,
          dispatched_step_numbers: first_layer.map { |s| s.step_number.to_i }.sort }
      end

      # Run a single step through its skill executor. Called by the step
      # worker job via the internal API once it has been picked up.
      #
      # Idempotent: if the step is already past `pending` (executing /
      # completed / failed) when this fires, a previous run already moved
      # it forward — bail without re-invoking the skill executor. This
      # closes the race where two `execute!` calls each enqueue per-step
      # jobs against the same step_id.
      #
      # @param step [#id, #step_number, #execution_config, …]
      # @return [Hash] { success:, outputs:, error: }
      def execute_step!(step)
        current = step_status(step)
        if IN_FLIGHT_STATUSES.include?(current)
          Rails.logger.info(
            "[SkillCompositionRunner] execute_step! no-op — step #{step_id(step)[0..7]} " \
            "already in '#{current}'; refusing duplicate invocation."
          )
          return { success: current == "completed", outputs: {}, error: nil, already_running: true }
        end

        config = step_config(step)
        skill_name = config["skill"] || config[:skill]
        inputs = merge_depends_on_outputs(step, config, config["inputs"] || config[:inputs] || {})
        on_failure = config["on_failure"] || config[:on_failure] || "continue"

        begin
          executor_class = resolve_executor(skill_name)
          raise "skill not found: #{skill_name}" unless executor_class

          mark_executing(step)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = invoke_executor(executor_class, inputs)

          if result_success?(result)
            outputs = result_outputs(result)
            mark_completed(step, outputs)
            record_skill_usage(step, skill_name, "success", started_at)
            announce_step(step, status: "completed", outputs: outputs)
            dispatch_unblocked_successors(step)
            settle_adaptation_for_step!(step)
            advance_mission_if_dag_complete!
            { success: true, outputs: outputs, error: nil }
          else
            error_message = result_error(result) || "skill returned non-success"
            record_skill_usage(step, skill_name, "failure", started_at)
            handle_failure(step, error_message, on_failure)
            { success: false, outputs: {}, error: error_message }
          end
        rescue StandardError => e
          Rails.logger.error("[SkillCompositionRunner] step #{step_id(step)} raised: #{e.class}: #{e.message}")
          record_skill_usage(step, skill_name, "failure", started_at)
          handle_failure(step, e.message, on_failure)
          { success: false, outputs: {}, error: e.message }
        end
      end

      # Lazily-built orchestrator that owns the canonical
      # `provisioning_step_changed` emission path. We instantiate one per
      # runner so all step events for a single run flow through the same
      # OrchestratorService surface — keeping a single source of truth for
      # MissionChannel broadcasts (M1 + M2 consolidation).
      def orchestrator
        @orchestrator ||= ::Ai::Missions::OrchestratorService.new(mission: mission)
      end

      # Compensating action for a previously-completed step. Looks up the
      # executor's descriptor[:rollback] hook; if present, calls it with the
      # outputs we recorded when the step originally completed.
      #
      # @param step [#id, #execution_config, …]
      # @return [Hash] { success: }
      def rollback_step!(step)
        config = step_config(step)
        skill_name = config["skill"] || config[:skill]

        executor_class = resolve_executor(skill_name)
        descriptor = executor_class&.respond_to?(:descriptor) ? executor_class.descriptor : nil
        rollback_hook = descriptor.is_a?(Hash) ? (descriptor[:rollback] || descriptor["rollback"]) : nil

        if rollback_hook && executor_class
          outputs = recorded_outputs_for(step)
          executor = build_executor(executor_class)
          if executor.respond_to?(rollback_hook)
            hook_result = executor.public_send(rollback_hook, **rollback_kwargs(outputs))
            # A hook that REPORTS failure must not be swallowed (dryrun
            # 20260809b: one instance survived its own rollback and nothing
            # recorded why). Fail the rollback loudly instead of stamping
            # rolled_back over resources that are still alive.
            if hook_result.is_a?(Hash) &&
               (hook_result[:success] == false || hook_result["success"] == false)
              errors = hook_result[:errors] || hook_result["errors"]
              Rails.logger.error(
                "[SkillCompositionRunner] rollback for step #{step_id(step)} reported failure: " \
                  "#{errors.inspect[0, 300]}"
              )
              announce_step(step, status: "rollback_failed",
                            outputs: { errors: errors }, error: "rollback reported failure")
              return { success: false, errors: errors }
            end
          end
        end

        mark_rolled_back(step)
        announce_step(step, status: "rolled_back", outputs: {})
        { success: true }
      rescue StandardError => e
        Rails.logger.error("[SkillCompositionRunner] rollback for step #{step_id(step)} raised: #{e.class}: #{e.message}")
        announce_step(step, status: "rollback_failed", outputs: { error: e.message }, error: e.message)
        { success: false }
      end

      # Slug → executor class. Public and class-level because it is the
      # canonical skill-resolution seam: a composer needs it to check that a
      # step it is about to persist can actually BIND, and duplicating the
      # lookup elsewhere would both drift and force another file to name an
      # extension constant. The instance method below delegates here.
      def self.resolve_executor(skill_name)
        return nil if skill_name.nil? || skill_name.to_s.empty?

        const_name = "#{skill_name.to_s.camelize}Executor"
        if Object.const_defined?("System::Ai::Skills::#{const_name}")
          "System::Ai::Skills::#{const_name}".constantize
        elsif Object.const_defined?("Ai::Skills::#{const_name}")
          "Ai::Skills::#{const_name}".constantize
        end
      end

      # Names of the descriptor inputs a skill declares `required: true`,
      # resolved through the seam above so a caller never has to reference an
      # executor by name.
      #
      # Returns nil — NOT [] — when the skill or its descriptor cannot be
      # resolved. "I cannot tell what this needs" and "this needs nothing"
      # must not share a return value: collapsing them would let a caller
      # treat an unresolvable skill as unconditionally valid.
      def self.required_inputs_for(skill_name)
        klass = resolve_executor(skill_name)
        return nil unless klass.respond_to?(:descriptor)

        declared = klass.descriptor[:inputs]
        return nil unless declared.is_a?(Hash)

        declared.select { |_k, spec| spec.is_a?(Hash) && spec[:required] }.keys.map(&:to_s)
      rescue StandardError => e
        Rails.logger.warn("[SkillCompositionRunner] required-input lookup failed for #{skill_name}: #{e.message}")
        nil
      end

      private

      # ===== Step traversal & topological sort =====

      def steps_in_order
        if plan.respond_to?(:steps)
          relation = plan.steps
          relation.respond_to?(:in_order) ? relation.in_order.to_a : relation.to_a.sort_by { |s| s.step_number.to_i }
        else
          Array(plan).sort_by { |s| s.step_number.to_i }
        end
      end

      # Step numbers on the plan that are already COMPLETED, and so satisfy a
      # dependency without appearing in the collection being layered.
      def completed_step_numbers
        steps_in_order.select { |s| step_status(s) == "completed" }
                      .map { |s| s.step_number.to_i }
                      .to_set
      end

      # Kahn-style layering: each layer holds steps whose dependencies are
      # entirely satisfied by steps in earlier layers, OR by `satisfied` — step
      # numbers already known to be complete OUTSIDE `steps`.
      #
      # That seed is what makes layering a SUBSET correct. #execute_appended!
      # is handed only the appended (or, on a resume, only the still-unenqueued)
      # steps, and by construction a resumable step depends on rows that are NOT
      # in that collection: the completed steps that made it resumable. Without
      # the seed the first pass yields an empty layer, the genuine-cycle
      # backstop below fires on a perfectly ordered chain, and it logs a warning
      # that is a lie — which costs the diagnostic its meaning. A subset that
      # fans out fares worse than that: it takes the best-effort branch, which
      # emits everything as ONE layer and so dispatches a step before its
      # predecessor has run.
      #
      # Deliberately NOT `deps & steps`. A dependency that is merely ABSENT
      # stays unsatisfied, so a subset whose own steps are not ready yet is
      # still held back layer by layer; only explicitly-completed numbers
      # satisfy from outside.
      def topological_layers(steps, satisfied: completed_step_numbers)
        remaining = steps.dup
        placed = satisfied.each_with_object({}) { |n, h| h[n.to_i] = true }
        layers = []

        while remaining.any?
          layer = remaining.select do |s|
            Array(s.dependencies).map(&:to_i).all? { |dep| placed[dep] }
          end

          if layer.empty?
            # Cycle or unresolvable dependency; emit remaining as a final
            # best-effort layer so they at least surface as failures.
            Rails.logger.warn("[SkillCompositionRunner] dependency cycle or unresolved deps for plan #{plan_id}")
            layers << remaining
            break
          end

          layer.each { |s| placed[s.step_number.to_i] = true }
          layers << layer
          remaining -= layer
        end

        layers
      end

      def dispatch_step_job(step)
        ::WorkerJobService.enqueue_job(
          "AiProvisioningStepJob",
          args: {
            mission_id: mission.id,
            step_id: step.id,
            account_id: account.id,
            runner_id: @runner_id
          },
          queue: "ai_execution"
        )
        stamp_dispatched!(step)
      end

      # Record, PER STEP and immediately after its own enqueue, that this step
      # was handed to a worker. AdaptationDispatchService reads it back to decide
      # what a re-entry should re-dispatch.
      #
      # Per step, not per call, because a layer is enqueued one job at a time: a
      # raise partway through leaves earlier steps queued, and an all-or-nothing
      # stamp written after the loop would record nothing — so the retry would
      # re-enqueue an already-queued step. Two jobs against one step row is not
      # merely wasteful: `execute_step!`'s in-flight guard is an unlocked
      # read-then-write, so two workers can both read `pending` and both invoke
      # the executor. (Not reachable through today's composers —
      # `persist_diff_plan!` chains every diff, so a layer is always one step —
      # but the shape is a trap for the first composer that fans out.)
      #
      # Best-effort: losing a stamp costs a redundant enqueue on re-entry, never
      # a lost dispatch.
      #
      # ATOMIC KEY MERGE, not a whole-hash write. The stamp lands AFTER the
      # enqueue, so a worker can pick the job up and finish the step first —
      # `mark_completed` has then already persisted `metadata["last_outputs"]`.
      # Rewriting the whole hash from the snapshot this method read before the
      # enqueue silently dropped those outputs, and three separate readers go
      # blind when it does:
      #   - VerificationService counts `outputs.node_instance_ids` against the
      #     step's declared count, so a scale-out that worked reads
      #     "provisioned 0/2" and the adaptation is failed with NO outcome —
      #     the fingerprint-clear -> effective arc never fires for it.
      #   - `rollback_kwargs` loses the ids, so a compensating rollback no-ops
      #     and live infrastructure survives it (the failure this runner's own
      #     rollback comments record from dryrun 20260809b).
      #   - `merge_depends_on_outputs` starves a chained successor of the values
      #     it was supposed to inherit.
      # A re-read-then-write would only narrow the window, not close it; the
      # `||` merge is resolved by Postgres inside the UPDATE, so both writers
      # survive whatever the interleaving.
      def stamp_dispatched!(step)
        return unless step.respond_to?(:id) && step.class.respond_to?(:where)

        stamp = {
          ::Ai::Provisioning::AdaptationDispatchService::DISPATCH_STAMP_KEY => {
            "runner_id" => @runner_id, "at" => Time.current.iso8601
          }
        }.to_json

        step.class.where(id: step.id).update_all(
          [ "metadata = COALESCE(metadata, '{}'::jsonb) || ?::jsonb, updated_at = ?",
            stamp, Time.current ]
        )
      rescue StandardError => e
        Rails.logger.warn("[SkillCompositionRunner] dispatch stamp failed for step #{step_id(step)}: #{e.message}")
      end

      # After a step completes, any successor whose remaining dependencies
      # are now all "completed" is ready to run.
      def dispatch_unblocked_successors(completed_step)
        remaining = steps_in_order
        completed_numbers = remaining
          .select { |s| step_status(s) == "completed" }
          .map { |s| s.step_number.to_i }
          .to_set

        remaining.each do |s|
          next if step_status(s) != "pending"
          deps = Array(s.dependencies).map(&:to_i)
          next if deps.empty?
          dispatch_step_job(s) if deps.all? { |d| completed_numbers.include?(d) }
        end
      end

      # ===== Skill resolution =====

      # Default convention: skill name `provision_full_stack` →
      # `System::Ai::Skills::ProvisionFullStackExecutor`. Stubbable in tests.
      def resolve_executor(skill_name)
        self.class.resolve_executor(skill_name)
      end

      def build_executor(executor_class)
        if executor_class.instance_method(:initialize).parameters.any? { |type, _| %i[key keyreq].include?(type) }
          executor_class.new(account: account)
        else
          executor_class.new
        end
      rescue ArgumentError
        executor_class.new
      end

      def invoke_executor(executor_class, inputs)
        executor = build_executor(executor_class)
        executor.execute(**symbolize(inputs))
      end

      # ===== Result coercion =====

      def result_success?(result)
        return false if result.nil?
        return result if result == true || result == false
        return result[:success] == true || result["success"] == true if result.respond_to?(:[])
        false
      end

      def result_outputs(result)
        return {} unless result.respond_to?(:[])
        result[:data] || result["data"] || result[:outputs] || result["outputs"] || result.to_h
      rescue StandardError
        {}
      end

      def result_error(result)
        return result.message if result.is_a?(Exception)
        return nil unless result.respond_to?(:[])
        result[:error] || result["error"] || result[:message] || result["message"]
      end

      # ===== Step state transitions =====
      #
      # We try to use the Ai::GoalPlanStep AASM-style helpers (start!,
      # complete!, fail!) when present; otherwise fall back to plain
      # update! so tests can pass duck-typed doubles.

      def mark_executing(step)
        if step.respond_to?(:start!)
          step.start!
        elsif step.respond_to?(:update!)
          step.update!(status: "executing", started_at: Time.current)
        end
      end

      def mark_completed(step, outputs)
        record_outputs(step, outputs)
        if step.respond_to?(:complete!)
          step.complete!(result: outputs)
        elsif step.respond_to?(:update!)
          step.update!(status: "completed", completed_at: Time.current, result_summary: outputs)
        end
      end

      def mark_failed(step, reason)
        if step.respond_to?(:fail!)
          step.fail!(reason: reason)
        elsif step.respond_to?(:update!)
          step.update!(status: "failed", completed_at: Time.current, result_summary: reason)
        end
      end

      def mark_rolled_back(step)
        if step.respond_to?(:update!)
          # GoalPlanStep doesn't have a "rolled_back" status — encode it as
          # failed with a result_summary marker so audit history is preserved.
          step.update!(status: "failed", result_summary: { rolled_back: true, at: Time.current })
        end
      end

      def step_status(step)
        step.respond_to?(:status) ? step.status.to_s : "pending"
      end

      # F5 (IMP 019fe4c5-19a8): protocol §3's skill-utilization oracle reads
      # ai_skill_usage_records, which only Ai::McpAgentExecutor wrote — the
      # mission path bypassed it and every dry-run graded skills NO ORACLE
      # despite executing provisioning skills. The runner is the mission
      # path's execution seam; record here. Best-effort: the oracle must
      # never break the step it measures, and an account/skill mismatch
      # (unseeded skill, unit-test doubles) is a silent skip.
      def record_skill_usage(step, skill_name, outcome, started_at)
        return if skill_name.blank?

        account_id = @account.respond_to?(:id) ? @account.id : nil
        return if account_id.blank?

        skill = resolve_skill_for_usage(account_id, skill_name)
        return unless skill

        duration_ms = if started_at
                        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
                      end
        # Route through Ai::Skill#record_usage! (not a bare create!) so the
        # skill's usage_count / effectiveness counters move — otherwise F5
        # rows accumulate while F4's single-usage effectiveness gate never
        # fires on the mission path (adversarial review of IMP-019fe817).
        # account: is the USING account (the skill may be global).
        skill.record_usage!(
          outcome: outcome,
          duration_ms: duration_ms,
          execution_id: step_id(step),
          execution_type: "provisioning_step",
          account: @account,
          metadata: {
            "mission_id" => (mission.respond_to?(:id) ? mission.id : nil),
            "step_number" => step.step_number.to_i,
            "skill" => skill_name
          }.compact
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[SkillCompositionRunner] skill-usage recording failed for #{skill_name.inspect}: " \
            "#{e.class}: #{e.message[0, 150]}"
        )
      end

      # Resolve config["skill"] (the snake_case executor id, e.g.
      # "provision_full_stack") to its Ai::Skill row (IMP 019fe817). Skills
      # are seeded with a SLUG, not the snake id: SkillBindings derives it as
      # "system-<class.dasherize>", so provision_full_stack → the
      # "system-provision-full-stack" slug while the display NAME is
      # "Provision Full Stack". The original find_by(name:) missed every real
      # skill (live oracle read 0). Try, account-override-first: the bare id
      # as a slug, its dasherized form, and the system-prefixed form; then a
      # display-name fallback for any skill registered off-convention.
      def resolve_skill_for_usage(account_id, skill_name)
        dashed = skill_name.tr("_", "-")
        # system-prefixed first, matching resolve_executor's System:: > Ai::
        # namespace precedence (adversarial review): the executor that ran is
        # system-registered, so its slug wins over a bare/dashed collision.
        candidate_slugs = [ "system-#{dashed}", dashed, skill_name ].uniq
        candidate_slugs.each do |slug|
          skill = ::Ai::Skill.resolve_for(account_id, slug: slug)
          return skill if skill
        end
        ::Ai::Skill.resolve_for(account_id, name: skill_name)
      end

      # F6 (IMP 019fe4c5-03a4): execute previously completed its last step and
      # sat until an operator advanced by hand. The runner is the only
      # component that knows when the DAG is done — advance the mission out of
      # execute itself. Best-effort: an advance failure must not fail the
      # step that just legitimately completed.
      def advance_mission_if_dag_complete!
        steps = steps_in_order
        return if steps.empty?
        return unless steps.all? { |s| step_status(s) == "completed" }

        orchestrator.advance!(expected_phase: "execute")
      rescue StandardError => e
        Rails.logger.error(
          "[SkillCompositionRunner] DAG complete but mission advance failed: #{e.class}: #{e.message}"
        )
      end

      # Statuses from which an appended adaptation step will not move again.
      ADAPTATION_TERMINAL_STATUSES = %w[completed failed].freeze

      # Walk an adaptation's own dependency chain and fail every step still
      # `pending` behind a failed one, to closure (a 3-step chain must fail
      # steps 2 AND 3 when step 1 dies). Scoped to the adaptation's siblings so
      # this cannot change what a provisioning run does with its own steps.
      def fail_unreachable_adaptation_successors!(siblings)
        failed = siblings.select { |s| step_status(s) == "failed" }
                         .map { |s| s.step_number.to_i }.to_set
        return if failed.empty?

        # BOUNDED by the sibling count. Termination otherwise depends on
        # mark_failed actually changing the status, and mark_failed is
        # deliberately defensive — it no-ops for a duck-typed step responding to
        # neither `fail!` nor `update!`, which this runner explicitly accepts —
        # while step_status returns "pending" for anything without `status`.
        # That pair spins a worker instead of raising.
        #
        # `handled` is what keeps the bound from merely converting the hang into
        # repeated WORK: for exactly that unmovable step the selection below is
        # otherwise identical on every pass, so it was re-failed and — worse —
        # re-announced up to `siblings.size` times, duplicating the broadcast
        # and the system message. Closure is unaffected: a step is handled once
        # and its number joins `failed`, which is what carries the walk down the
        # chain.
        handled = Set.new
        siblings.size.times do
          newly = siblings.select do |s|
            !handled.include?(s.step_number.to_i) &&
              step_status(s) == "pending" &&
              Array(s.dependencies).map(&:to_i).any? { |d| failed.include?(d) }
          end
          break if newly.empty?

          newly.each do |s|
            reason = "predecessor adaptation step failed — never dispatched"
            mark_failed(s, reason)
            # ANNOUNCE, like every other status transition here. Flipping these
            # silently left a console subscribed to MissionChannel rendering
            # them `pending` indefinitely while the rows said otherwise.
            announce_step(s, status: "failed", outputs: { error: reason }, error: reason)
            handled << s.step_number.to_i
            failed << s.step_number.to_i
          end
        end
      end

      # IMP-8c37b9e5ccd5 — hand a finished adaptation back to its dispatcher for
      # the post-adapt verification + outcome record.
      #
      # Keyed on THIS ADAPTATION'S OWN steps, not on the whole plan being
      # complete. Two reasons, both of which bit an earlier shape of this hook:
      #
      #   1. A FAILED appended step is terminal for the adaptation but never
      #      satisfies "every step completed", so the settle never fired: the
      #      diff plan sat in `executing` forever with no outcome and no failure
      #      record — and because the live plan then permanently held a
      #      non-completed step, no LATER adaptation on that mission could
      #      settle either.
      #   2. Suppressing the execute-phase advance whenever the plan carried any
      #      adaptation provenance stranded a mission adapted while still in
      #      `execute`: the appended steps keep their provenance forever, so the
      #      advance was suppressed permanently and the mission never reached
      #      verify. The advance is guarded by `expected_phase:` already, so it
      #      is a logged no-op for a mission in `adapting` — there was nothing
      #      to suppress.
      def settle_adaptation_for_step!(step)
        plan_id = step_config(step)[::Ai::Provisioning::AdaptationDispatchService::PROVENANCE_KEY].presence
        return if plan_id.blank?

        siblings = steps_in_order.select do |s|
          step_config(s)[::Ai::Provisioning::AdaptationDispatchService::PROVENANCE_KEY].to_s == plan_id.to_s
        end

        # A failed step's successors will never run: successors are dispatched
        # only from the SUCCESS arm. Left `pending` they are never terminal, so
        # a chained diff whose first step failed would wait forever — the same
        # permanent stall the failure path was added to remove, one level down.
        # Mark them, so the rows say what is true and the adaptation can settle.
        fail_unreachable_adaptation_successors!(siblings)

        return unless siblings.all? { |s| ADAPTATION_TERMINAL_STATUSES.include?(step_status(s)) }

        ::Ai::Provisioning::AdaptationDispatchService
          .new(account: account, mission: mission)
          .settle!(adaptation_plan_ids: [ plan_id ])
      rescue StandardError => e
        Rails.logger.error(
          "[SkillCompositionRunner] post-adapt settle failed for adaptation #{plan_id}: " \
          "#{e.class}: #{e.message}"
        )
      end

      def record_outputs(step, outputs)
        return unless step.respond_to?(:metadata) && step.respond_to?(:metadata=)
        meta = step.metadata.is_a?(Hash) ? step.metadata.dup : {}
        meta["last_outputs"] = outputs
        step.metadata = meta
      end

      def recorded_outputs_for(step)
        return {} unless step.respond_to?(:metadata)
        meta = step.metadata.is_a?(Hash) ? step.metadata : {}
        meta["last_outputs"] || meta[:last_outputs] || {}
      end

      # ===== Cross-step data flow =====
      #
      # A step may declare `execution_config["depends_on_outputs"]` to pull
      # values produced by predecessor steps into its own inputs at runtime —
      # the mechanism that lets `provision_full_stack` hand its
      # `node_instance_ids` to a downstream `deploy_app_code` step that could
      # not know them at compose time. Shape:
      #
      #   "depends_on_outputs" => {
      #     "<input_key>" => {
      #       "from_step" => <Integer predecessor step_number>,
      #       "path"      => "<dot.path into that step's recorded outputs>", # default: input_key
      #       "select"    => "first" | "last" | "all" | <Integer index>      # default: "all"
      #     }
      #   }
      #
      # Resolved values overwrite any compose-time placeholder for the same
      # key. A missing/blank upstream value is skipped (never clobbers an
      # existing input with nil). Lookups tolerate both string and symbol keys
      # so values survive the JSON round-trip the per-step worker dispatch
      # forces (predecessor outputs are persisted to step metadata between jobs).
      def merge_depends_on_outputs(step, config, inputs)
        mapping = config["depends_on_outputs"] || config[:depends_on_outputs]
        return inputs unless mapping.is_a?(Hash) && mapping.any?

        upstream = upstream_outputs_for(step)
        resolved = inputs.dup

        mapping.each do |input_key, spec|
          spec = spec.is_a?(Hash) ? spec : {}
          from = (spec["from_step"] || spec[:from_step]).to_i
          source = upstream[from]
          next unless source.is_a?(Hash)

          path = (spec["path"] || spec[:path] || input_key).to_s
          value = select_output(dig_path(source, path), spec["select"] || spec[:select])
          next if value.nil?

          key = input_key.to_s
          resolved.delete(key)
          resolved.delete(key.to_sym)
          resolved[key] = value
        end

        resolved
      end

      # Build { predecessor_step_number => recorded_outputs_hash } for the
      # steps this step depends on. Reads each predecessor's persisted
      # metadata["last_outputs"] via recorded_outputs_for.
      def upstream_outputs_for(step)
        deps = Array(step.respond_to?(:dependencies) ? step.dependencies : []).map(&:to_i)
        return {} if deps.empty?

        deps_set = deps.to_set
        steps_in_order.each_with_object({}) do |s, acc|
          num = s.step_number.to_i
          acc[num] = recorded_outputs_for(s) if deps_set.include?(num)
        end
      end

      # Walk a dot-delimited path into a (possibly nested) hash, tolerating
      # both string and symbol keys at each level.
      def dig_path(hash, path)
        path.to_s.split(".").reduce(hash) do |acc, key|
          break nil unless acc.is_a?(Hash)
          acc.key?(key) ? acc[key] : acc[key.to_sym]
        end
      end

      # Apply an array selector to a resolved value. Non-arrays pass through
      # for "first"/"last"; "all" (and nil) returns the value untouched.
      def select_output(value, selector)
        case selector
        when nil, "all"  then value
        when "first"     then value.is_a?(Array) ? value.first : value
        when "last"      then value.is_a?(Array) ? value.last : value
        when Integer     then Array(value)[selector]
        when /\A-?\d+\z/  then Array(value)[selector.to_i]
        else value
        end
      end

      # Build the kwargs handed to a rollback hook from a step's recorded
      # outputs. Executors on the nested-outputs convention store ids under a
      # top-level "outputs" sub-hash (e.g. provision_full_stack →
      # { outputs: { node_instance_ids: [...] } }), but their rollback hooks
      # declare those ids as flat kwargs (rollback_provision_full_stack(
      # node_instance_ids:, ...)). symbolize is shallow, so without flattening
      # the ids never reach the hook and rollback silently no-ops. Merge the
      # nested sub-hash up one level so flat- AND nested-convention executors
      # both receive their ids; the hook's **_extras swallows the rest.
      def rollback_kwargs(outputs)
        return {} unless outputs.is_a?(Hash)
        nested = outputs["outputs"] || outputs[:outputs]
        merged = nested.is_a?(Hash) ? outputs.merge(nested) : outputs
        symbolize(merged)
      end

      # ===== Failure handling =====

      def handle_failure(step, error_message, on_failure)
        mark_failed(step, error_message)
        announce_step(step, status: "failed", outputs: { error: error_message }, error: error_message)

        # Compensate ONLY the failed step's own recorded resources (a retried
        # step's prior partial success is the legitimate target; a first-run
        # validation failure recorded nothing and rolls back nothing).
        # Completed siblings' infrastructure survives — verify (F2) and the
        # operator gates own its disposition (IMP 019fe5d7-1089).
        rollback_step!(step) if on_failure.to_s == "rollback"

        # AFTER the unwind, deliberately. A failed step is terminal for its
        # adaptation and must settle it — without this the diff plan never
        # leaves `executing` and no outcome is recorded, because the settle only
        # ran off the success path. But the settle runs a full live
        # VerificationService pass, so putting it first parked seconds of
        # provider round-trips between a step failing and its resources being
        # released.
        settle_adaptation_for_step!(step)
      end

      # ===== Side effects =====

      # Step-level event emission. Delegates the `provisioning_step_changed`
      # broadcast through OrchestratorService#broadcast_step_event! so the
      # orchestrator owns the single canonical emission path (M1+M2
      # consolidation). The runner_id and skill name are passed through as
      # `extra` payload metadata to preserve the previous broadcast shape
      # for any downstream listeners — frontend (StepProgressStream) only
      # consumes mission_id/step_id/status/outputs/error and ignores extras.
      def announce_step(step, status:, outputs:, error: nil)
        skill = step_config(step)["skill"] || step_config(step)[:skill]

        orchestrator.broadcast_step_event!(
          step: step,
          status: status,
          outputs: outputs,
          error: error,
          extra: { runner_id: @runner_id, skill: skill }.compact
        )

        post_system_message(
          "Step #{step.step_number} (#{skill}) → #{status}",
          status: status,
          metadata: { step_id: step_id(step), status: status, outputs: outputs }
        )
      end

      def broadcast_run_started(step_count:, layer_count:)
        broadcast(RUN_START_EVENT, {
          mission_id: mission.id,
          runner_id: @runner_id,
          started_at: @started_at&.iso8601,
          step_count: step_count,
          layer_count: layer_count
        })
      end

      def broadcast(event_type, payload)
        ::MissionChannel.broadcast_mission_event(mission.id, event_type, payload)
      rescue StandardError => e
        Rails.logger.warn("[SkillCompositionRunner] broadcast failed: #{e.class}: #{e.message}")
      end

      def post_system_message(content, status:, metadata: {})
        conv = mission.respond_to?(:conversation) ? mission.conversation : nil
        return unless conv

        # activity_type/metadata are NOT columns on ai_messages — Ai::Conversation
        # #add_message forwards **options straight into messages.build, so passing
        # them at the top level raised UnknownAttributeError into the rescue below
        # and dropped every step-progress message (IMP-019fe4c5). content_metadata
        # is where the other activity writers put this.
        conv.add_system_message(
          content,
          # stringify first: both call sites pass symbol keys and one of them
          # already carries :status/:runner_id, so a raw merge would emit the
          # same key twice into jsonb.
          content_metadata: metadata.to_h.stringify_keys.merge(
            "activity_type" => ACTIVITY_TYPE,
            "runner_id" => @runner_id,
            "status" => status
          )
        )
      rescue StandardError => e
        Rails.logger.warn("[SkillCompositionRunner] system message failed: #{e.class}: #{e.message}")
      end

      # ===== Misc helpers =====

      def step_config(step)
        cfg = step.respond_to?(:execution_config) ? step.execution_config : {}
        cfg.is_a?(Hash) ? cfg : {}
      end

      def step_id(step)
        step.respond_to?(:id) ? step.id : nil
      end

      def plan_id
        plan.respond_to?(:id) ? plan.id : "<inline>"
      end

      def symbolize(hash)
        return {} unless hash.is_a?(Hash)
        hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end
    end
  end
end
