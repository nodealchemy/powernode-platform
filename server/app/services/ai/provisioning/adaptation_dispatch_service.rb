# frozen_string_literal: true

module Ai
  module Provisioning
    # The CONSUMER of `adaptation_diff` plans (IMP-8c37b9e5ccd5, INC-2).
    #
    # AdaptationProposerService composes a diff-shaped `Ai::GoalPlan` and stops.
    # Before this service nothing read it: the plan sat in `draft` forever, the
    # mission's live plan never grew the steps, the runner never saw them, the
    # verify phase never re-ran, and the RemediationOutcome the fleet validator
    # scores was never minted. The adaptive-evolution lane terminated in a
    # persisted record.
    #
    # Four things happen here, in order:
    #
    #   1. GATE. The plan is dispatched ONLY on the say-so of the
    #      `adaptation_gate` registry seam — the fleet `ApprovalRequest` chain
    #      plus `Ai::InterventionPolicy`, which is *the* policy gate for this
    #      platform. Core holds no policy of its own. An absent seam (core
    #      mode), an erroring seam, or a seam that tries to widen core's bounds
    #      all PARK the plan in draft. There is no silent proceed.
    #
    #   2. APPEND. Cleared steps are appended onto the mission's LIVE plan —
    #      the one `mission.configuration["plan"]["plan_id"]` names — rather
    #      than run out of the diff plan. This is load-bearing, not cosmetic:
    #      that live plan is what VerificationService walks, so an adaptation
    #      executed out of a side plan would be invisible to the very
    #      verification that is supposed to confirm it landed.
    #
    #   3. DISPATCH. Only the appended steps are dispatched, through
    #      `SkillCompositionRunner#execute_appended!`. The ordinary `execute!`
    #      entrypoint refuses to run a plan any of whose steps is past
    #      `pending` — the guard that stops a double-provision — and a live
    #      plan's original steps are all `completed`, so `execute!` would
    #      no-op every adaptation.
    #
    #   4. SETTLE. When the appended steps finish, the runner calls back into
    #      #settle!: VerificationService re-runs against the now-adapted plan
    #      and, ONLY if it comes back healthy, a pending `RemediationOutcome`
    #      is recorded through the seam. A later fleet tick's
    #      RemediationValidator flips that row pending -> effective when the
    #      triggering fingerprint has cleared (or -> ineffective when it is
    #      still firing). Core never re-senses; the sensor that owns the
    #      fingerprint is the only reader of live fleet state.
    #
    # Core purity: nothing here names an extension. The gate and the outcome
    # store are both reached through `Powernode::ExtensionRegistry`, following
    # the `provision_verifier` precedent.
    class AdaptationDispatchService
      # The `gate:` dispositions, and the complete set of them. They describe
      # what happened to the plan, never merely whether an approval object
      # exists — the defect this replaces was a `requested: approval.present?`
      # boolean in which "no approval needed" and "the approval system is not
      # there at all" were the same `false`, inside a success payload implying
      # the change was on its way.
      #
      #   routed                   — a gate now holds this plan; nothing ran.
      #   auto_apply_within_bounds — policy permitted immediate application and
      #                              core's bounds check agreed; steps dispatched.
      #   parked_gate_unavailable  — NO USABLE GATE ANSWER was obtained (seam
      #                              absent, erroring, unintelligible, or trying
      #                              to widen core's bounds). Plan stays draft.
      GATE_ROUTED     = "routed"
      GATE_AUTO_APPLY = "auto_apply_within_bounds"
      GATE_PARKED     = "parked_gate_unavailable"
      GATE_DISPOSITIONS = [ GATE_ROUTED, GATE_AUTO_APPLY, GATE_PARKED ].freeze

      # `plan_data["kind"]` this service consumes, and the registry key it
      # resolves the policy gate through.
      PLAN_KIND = "adaptation_diff"
      GATE_SEAM = :adaptation_gate

      # Who granted an `auto_apply_within_bounds` answer. The gate declares it;
      # anything else (including absent) reads as POLICY, the stricter case, in
      # which core's bounds bind. Only `approval` — a person who looked at this
      # plan and said yes — may release an out-of-bounds plan.
      AUTHORITY_POLICY   = "policy"
      AUTHORITY_APPROVAL = "approval"

      # Step-config key stamped on each appended step, pointing back at the
      # proposal it came from. Top-level (beside "skill" / "composed_by"), never
      # inside "inputs", so it can never reach an executor as a kwarg. The
      # runner reads it to tell an adaptation settle from an execute-phase
      # advance.
      PROVENANCE_KEY = "adapted_from_plan_id"

      class NotAnAdaptationPlanError < ArgumentError; end

      attr_reader :account, :mission

      def initialize(account:, mission:)
        @account = account
        @mission = mission
      end

      # Resolve the gate for `plan` and, if it clears, append + dispatch.
      #
      # Idempotent and safe to re-call: the gate seam is asked afresh every
      # time, so a plan that was routed on the first call and approved later
      # dispatches on a second call without minting a second request. That is
      # what lets the operator MCP path and the sensor path share one queue.
      #
      # @return [Hash] { gate:, dispatched:, plan_id:, approval_request_id:,
      #   within_bounds:, detail:, live_plan_id:, appended_step_numbers: }
      def dispatch!(plan:)
        unless adaptation_plan?(plan)
          raise NotAnAdaptationPlanError,
                "plan #{plan&.id.inspect} is not a #{PLAN_KIND} plan"
        end

        within_bounds = within_bounds?(plan)
        disposition = resolve_gate(plan, within_bounds)
        base = disposition.merge(plan_id: plan.id, within_bounds: within_bounds)

        return base.merge(dispatched: false) unless base[:gate] == GATE_AUTO_APPLY

        apply!(plan, base)
      end

      # Post-adapt settle. Called by SkillCompositionRunner once every step of
      # ONE adaptation has reached a terminal status (completed or failed).
      #
      # @return [Hash] { verified:, healthy:, checks:, outcomes_recorded: }
      def settle!(adaptation_plan_ids:)
        ids = Array(adaptation_plan_ids).compact.uniq
        return empty_settle if ids.empty?

        # CLAIM the plans under a row lock before doing anything else. The final
        # layer of an adaptation can be several steps finishing on different
        # workers at the same moment, and each of them sees "all my siblings are
        # terminal". Without the claim they all verify, all call complete!/fail!,
        # and all attempt the outcome. Only plans still `executing` are claimed,
        # which also stops a LATER adaptation's settle from re-settling this one
        # — the appended steps keep their provenance forever, so its plan id
        # keeps being offered.
        plans = ::Ai::GoalPlan.transaction do
          ::Ai::GoalPlan
            .where(account_id: account.id, id: ids, status: "executing")
            .lock
            .to_a
        end
        return empty_settle if plans.empty?

        # The whole live plan is verified — that is the point of appending onto
        # it, and the full check list is what gets reported. But the ADAPTATION
        # is scored only on ITS OWN steps.
        #
        # Scoring it on the whole plan made the loop unable to record a success
        # in its commonest case: replica drift is usually triggered BY an
        # instance dying, and that dead original still fails live reconciliation
        # after a perfectly good scale-out. The adaptation would be marked
        # failed and no RemediationOutcome minted — so a remediation that worked
        # could never be scored. The dead instance is a separate condition,
        # still reported in `checks`, and its own signal keeps firing until it
        # is dealt with.
        verification = VerificationService.new(account: account, mission: mission).verify

        recorded = 0
        results = plans.map do |plan|
          steps = appended_steps_for(plan)
          healthy = adaptation_healthy?(steps, verification[:checks])

          if healthy
            plan.complete!
            mirror_step_status!(plan, "completed")
            recorded += 1 if record_outcome!(plan)
          else
            plan.fail!(reason: unhealthy_reason(plan, steps, verification[:checks]))
            mirror_step_status!(plan, "failed")
          end
          [ plan.id, healthy ]
        end

        healthy = results.all? { |(_id, ok)| ok }

        Rails.logger.info(
          "[AdaptationDispatchService] post-adapt settle mission=#{mission.id} " \
          "healthy=#{healthy} plans=#{plans.size} outcomes_recorded=#{recorded}"
        )

        { verified: true, healthy: healthy, checks: verification[:checks],
          outcomes_recorded: recorded }
      end

      # True when `plan` is the kind of plan this service consumes.
      def self.adaptation_plan?(plan)
        return false unless plan.respond_to?(:plan_data)

        data = plan.plan_data
        data.is_a?(Hash) && data["kind"].to_s == PLAN_KIND
      end

      private

      def adaptation_plan?(plan)
        self.class.adaptation_plan?(plan)
      end

      # ----- gate ----------------------------------------------------------

      # Ask the seam whether this plan may be applied now.
      #
      # Core contributes exactly one thing to that decision — `within_bounds`,
      # which can only ever say NO (see #within_bounds?). The gate is the only
      # thing that can GRANT application. Every failure mode lands on the same
      # fail-closed default: park in draft.
      def resolve_gate(plan, within_bounds)
        gate = gate_provider
        return parked("no #{GATE_SEAM} registered (core mode) — plan parked in draft") unless gate

        unless gate.respond_to?(:adaptation_disposition)
          return parked("registered #{GATE_SEAM} does not answer #adaptation_disposition")
        end

        answer = gate.adaptation_disposition(
          account: account, mission: mission, plan: plan,
          change_type: change_type_for(plan), auto_apply_eligible: within_bounds
        )
        answer = answer.is_a?(Hash) ? answer.symbolize_keys : {}

        case answer[:disposition].to_s
        when GATE_ROUTED
          { gate: GATE_ROUTED, approval_request_id: answer[:approval_request_id],
            detail: answer[:detail].presence || "held for an operator decision" }
        when GATE_AUTO_APPLY
          # A POLICY may NARROW core's bounds; it may never widen them. An
          # answer granting unattended auto-apply for a plan core already
          # judged out of bounds is a malfunctioning gate, and a malfunctioning
          # gate is no gate — park.
          #
          # A HUMAN APPROVAL is the one thing that legitimately releases an
          # out-of-bounds plan: the bounds check exists to stop the machine
          # applying a large change unattended, not to veto an operator who
          # looked at that change and said yes. Making approval inert here
          # would leave the `routed` lane a dead end for exactly the plans that
          # most need a person.
          #
          # DECLARED, never inferred (the same discipline as the fleet
          # `advisory?` flag): the gate must say `authority: "approval"`. An
          # absent or unrecognized authority reads as "policy", the stricter of
          # the two.
          if !within_bounds && authority_of(answer) != AUTHORITY_APPROVAL
            return parked("#{GATE_SEAM} granted unattended auto-apply for an out-of-bounds plan — refused")
          end

          { gate: GATE_AUTO_APPLY, approval_request_id: answer[:approval_request_id],
            detail: answer[:detail].presence ||
              (within_bounds ? "within operator policy bounds" : "released by operator approval") }
        else
          parked("#{GATE_SEAM} returned no usable disposition (#{answer[:disposition].inspect})")
        end
      rescue StandardError => e
        parked("#{GATE_SEAM} raised #{e.class}: #{e.message[0, 200]}")
      end

      def authority_of(answer)
        value = answer[:authority].to_s
        value == AUTHORITY_APPROVAL ? AUTHORITY_APPROVAL : AUTHORITY_POLICY
      end

      def parked(detail)
        Rails.logger.info("[AdaptationDispatchService] mission=#{mission&.id} parked: #{detail}")
        { gate: GATE_PARKED, approval_request_id: nil, detail: detail }
      end

      def gate_provider
        ::Powernode::ExtensionRegistry.provider(GATE_SEAM)
      rescue StandardError => e
        Rails.logger.warn("[AdaptationDispatchService] #{GATE_SEAM} lookup failed: #{e.message}")
        nil
      end

      # Core's bounds verdict, delegated to the composer that owns the mission's
      # watch_policies. Downgrade-only by construction: it is handed to the gate
      # as `auto_apply_eligible`, and false forces the gate's approval arm.
      def within_bounds?(plan)
        AdaptationProposerService.new(account: account, mission: mission)
                                 .auto_apply?(plan: plan)
      rescue StandardError => e
        Rails.logger.warn("[AdaptationDispatchService] bounds check failed: #{e.message}")
        false
      end

      def change_type_for(plan)
        plan_data(plan)["change_type"].to_s
      end

      def plan_data(plan)
        data = plan.plan_data
        data.is_a?(Hash) ? data : {}
      end

      # ----- append + dispatch ---------------------------------------------

      def apply!(plan, base)
        live_plan = live_plan_for_mission
        unless live_plan
          return base.merge(
            gate: GATE_PARKED, dispatched: false,
            detail: "mission #{mission.id} references no live plan to append onto"
          )
        end

        # IDEMPOTENCY, on GROUND TRUTH rather than on status bookkeeping.
        #
        # #dispatch! is deliberately re-callable — that is how a routed plan
        # gets released once its approval lands. But once the gate says yes it
        # keeps saying yes, so a second call would append this plan's steps a
        # SECOND time and provision the replicas twice. Asking the live plan
        # whether it already carries steps stamped with this plan's id answers
        # "did this adaptation already land?" from the rows themselves, which a
        # status field can drift from and a concurrent caller can race.
        if (existing = already_appended(live_plan, plan)).any?
          Rails.logger.info(
            "[AdaptationDispatchService] plan #{plan.id} already appended onto " \
            "live plan #{live_plan.id} — refusing duplicate dispatch."
          )
          return base.merge(
            dispatched: false, live_plan_id: live_plan.id,
            appended_step_numbers: existing.map { |s| s.step_number.to_i },
            detail: "already applied to this mission's live plan"
          )
        end

        appended = append_steps!(live_plan, plan)
        if appended.empty?
          # Nothing ran, so this is not an auto-apply however the gate answered.
          return base.merge(gate: GATE_PARKED, dispatched: false, live_plan_id: live_plan.id,
                            detail: "adaptation plan carried no steps to append")
        end

        # Leaving `draft` is what releases the fleet DecisionEngine's
        # one-open-proposal-per-mission brake: a dispatched plan is no longer an
        # undecided proposal, so the next genuine breach may propose again.
        plan.start_execution!

        run = SkillCompositionRunner
          .new(account: account, mission: mission, plan: live_plan)
          .execute_appended!(steps: appended)

        # Report what the runner ACTUALLY dispatched. Hardcoding true here made
        # `dispatched` unfalsifiable: the runner's own already-running arm
        # returns 0, and a caller reading `dispatched: true` would believe work
        # was in flight when none had been enqueued.
        dispatched = run[:dispatched].to_i.positive?

        base.merge(
          dispatched: dispatched,
          live_plan_id: live_plan.id,
          appended_step_numbers: appended.map { |s| s.step_number.to_i },
          runner_id: run[:runner_id],
          detail: dispatched ? base[:detail] : "runner dispatched no step (a run is already in flight)"
        )
      end

      # Steps on the live plan already stamped as coming from this adaptation.
      def already_appended(live_plan, plan)
        live_plan.steps.select do |s|
          step_config(s)[PROVENANCE_KEY].to_s == plan.id.to_s
        end
      end

      def live_plan_for_mission
        plan_id = mission.configuration.is_a?(Hash) ? mission.configuration.dig("plan", "plan_id") : nil
        return nil if plan_id.blank?

        ::Ai::GoalPlan.where(account_id: account.id).find_by(id: plan_id)
      end

      # Copy the diff plan's steps onto the tail of the live plan.
      #
      # COPY, not move: the diff plan stays the durable record of what was
      # proposed (the MCP envelope and any operator review read it), while the
      # live plan carries the executable steps the runner and VerificationService
      # walk.
      #
      # Numbering continues past the live plan's current maximum, and intra-diff
      # `dependencies` — which are step_numbers within the diff, not indices —
      # are remapped onto the new numbers. Without the remap a diff step
      # declaring `[1]` would bind to the live plan's unrelated original step 1,
      # which is already `completed`, and dispatch in the wrong layer.
      def append_steps!(live_plan, plan)
        source = ordered_steps(plan)
        return [] if source.empty?

        ::Ai::GoalPlan.transaction do
          offset = live_plan.steps.maximum(:step_number).to_i
          renumbered = source.each_with_index.to_h { |s, i| [ s.step_number.to_i, offset + i + 1 ] }

          source.each_with_index.map do |src, idx|
            live_plan.steps.create!(
              step_number: offset + idx + 1,
              step_type: src.step_type,
              status: "pending",
              description: src.description,
              execution_config: step_config(src).merge(PROVENANCE_KEY => plan.id),
              dependencies: Array(src.dependencies).filter_map { |d| renumbered[d.to_i] }
            )
          end
        end
      end

      def ordered_steps(plan)
        relation = plan.steps
        relation.respond_to?(:in_order) ? relation.in_order.to_a : relation.to_a.sort_by { |s| s.step_number.to_i }
      end

      def step_config(step)
        cfg = step.execution_config
        cfg.is_a?(Hash) ? cfg.deep_stringify_keys : {}
      end

      # ----- settle ---------------------------------------------------------

      # Mint the pending RemediationOutcome the fleet validator later scores.
      #
      # Recorded at SETTLE time, not at dispatch: `acted_at` must be the moment
      # the adaptation actually landed, or the validator's settle window elapses
      # while the plan is still executing and scores a live remediation
      # INEFFECTIVE. And recorded only on a healthy verification — an adaptation
      # that did not land is not a remediation to measure.
      #
      # NO FINGERPRINT, NO OUTCOME. An operator-initiated adaptation carries no
      # sensor signal, so there is nothing that could ever "clear"; keying a row
      # on a synthetic fingerprint would score EFFECTIVE for free on the next
      # tick and manufacture a success in the ground-truth table the LEARN step
      # reads.
      def record_outcome!(plan)
        data = plan_data(plan)
        fingerprint = data["signal_fingerprint"].presence
        return false if fingerprint.blank?

        gate = gate_provider
        return false unless gate.respond_to?(:record_adaptation_outcome!)

        gate.record_adaptation_outcome!(
          account: account, mission: mission, plan: plan,
          fingerprint: fingerprint, signal_kind: data["signal_kind"].to_s
        )
        true
      rescue StandardError => e
        # A bookkeeping failure must not undo an adaptation that succeeded.
        Rails.logger.warn(
          "[AdaptationDispatchService] outcome recording failed for plan=#{plan.id}: " \
          "#{e.class}: #{e.message[0, 200]}"
        )
        false
      end

      def empty_settle
        { verified: false, healthy: nil, checks: [], outcomes_recorded: 0 }
      end

      # The live-plan steps this adaptation contributed.
      def appended_steps_for(plan)
        live_plan = live_plan_for_mission
        return [] unless live_plan

        already_appended(live_plan, plan)
      end

      # Did THIS adaptation land? A step of its own that failed is decisive; so
      # is any failing check naming one of its steps, or one of the instances
      # those steps produced. Checks belonging to the mission's pre-existing
      # footprint are deliberately not consulted — see #settle!.
      def adaptation_healthy?(steps, checks)
        return false if steps.empty?
        return false unless steps.all? { |s| s.status.to_s == "completed" }

        own = own_checks(steps, checks)
        own.all? { |c| c[:ok] }
      end

      # VerificationService names its checks `step_<number>_*` and
      # `instance_<node_instance_id>`, so both can be attributed back to the
      # steps that produced them.
      def own_checks(steps, checks)
        numbers = steps.map { |s| s.step_number.to_i }.to_set
        instance_ids = steps.flat_map { |s| produced_instance_ids(s) }.to_set

        Array(checks).select do |c|
          name = c[:name].to_s
          if (m = name.match(/\Astep_(\d+)_/))
            numbers.include?(m[1].to_i)
          elsif (m = name.match(/\Ainstance_(.+)\z/))
            instance_ids.include?(m[1])
          else
            false
          end
        end
      end

      def produced_instance_ids(step)
        meta = step.metadata.is_a?(Hash) ? step.metadata : {}
        outs = meta["last_outputs"] || meta[:last_outputs] || {}
        outs = outs.is_a?(Hash) ? outs.deep_stringify_keys : {}
        Array(outs.dig("outputs", "node_instance_ids")).map(&:to_s)
      end

      # The diff plan's OWN steps are the proposal record and never execute —
      # the appended copies do. Leaving them `pending` on a completed plan made
      # `all_steps_completed?` false and `progress_percentage` read 0 for a plan
      # that had in fact finished, so mirror the outcome onto them.
      def mirror_step_status!(plan, status)
        plan.steps.where.not(status: status).update_all(status: status, updated_at: Time.current)
      rescue StandardError => e
        Rails.logger.warn("[AdaptationDispatchService] step mirror failed for #{plan.id}: #{e.message}")
      end

      def unhealthy_reason(plan, steps, checks)
        failed_steps = steps.reject { |s| s.status.to_s == "completed" }
        if failed_steps.any?
          return "adaptation step(s) #{failed_steps.map(&:step_number).join(', ')} did not complete"[0, 500]
        end

        failing = own_checks(steps, checks).reject { |c| c[:ok] }
        summary = failing.first(3).map { |c| "#{c[:name]}: #{c[:detail]}" }.join("; ")
        "post-adapt verification failed for plan #{plan.id}: #{summary}"[0, 500]
      end
    end
  end
end
