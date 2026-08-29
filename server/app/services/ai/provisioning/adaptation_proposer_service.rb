# frozen_string_literal: true

module Ai
  module Provisioning
    # Consumes adaptation signals (system.project_slo_violation,
    # system.project_drift, system.project_cost_breach) emitted by
    # `System::Fleet::Sensors::ProjectSloSensor` and turns them into a
    # diff-shaped `Ai::GoalPlan` whose steps invoke the M2 provisioning
    # skill executors (`scale_project`, `relocate_workload`,
    # `attach_storage`, `configure_sdwan_for_project`).
    #
    # This service COMPOSES AND NOTHING ELSE. It used to route the plan through
    # `Ai::Autonomy::ApprovalWorkflowService` as
    # `project.adapt_<change_type>`; that call was removed in IMP-8c37b9e5ccd5
    # (ratified §4). It was a SECOND approval namespace — a per-action_type
    # chain with no policy resolution, no dedup, and no consent budget — sitting
    # beside the fleet `ApprovalRequest` chain + `Ai::InterventionPolicy` that
    # gates every other remediation on this platform. One gate, and this is not
    # it: `Ai::Provisioning::AdaptationDispatchService` resolves the
    # `adaptation_gate` seam and owns dispatch.
    #
    # `#auto_apply?` survives that removal as a DOWNGRADE-ONLY bounds check —
    # core's input to the gate, never a decision to apply.
    #
    # The plan returned by `propose_from_signals` is a *diff plan*: only
    # the steps that change. The Skill Composition Runner appends them
    # onto the live mission's existing plan rather than replacing it.
    #
    # Two entrypoints, one internal path:
    #   - `propose_from_signals` — sensor-driven (ProjectSloSensor →
    #     DecisionEngine). Swallows errors, returns the plan or nil.
    #   - `propose_change`       — operator-driven (MCP
    #     `platform_provisioning_adapt`). Wraps the explicit request in a
    #     signal-shaped envelope and funnels it into the identical
    #     `compose_and_route!` internal, so an operator cannot get a
    #     differently-shaped plan by asking for a change directly. Its caller
    #     then puts the plan through the same gate the sensor path uses.
    #     Raises rather than swallowing, because its caller is interactive.
    #
    # LLM access is funneled through `#diff_from_llm` so test specs can
    # inject a fixture proposal without exercising provider plumbing —
    # mirrors the seam in `IntentCaptureService` from the M0 sprint.
    class AdaptationProposerService
      # Supplies tracked_client_for / resolve_service_agent so this service's
      # LLM calls are recorded rather than invisible (IMP 019fe1da).
      include AgentBackedService

      class MissionMissingError < StandardError; end
      # ArgumentError so MCP/tool callers that already funnel ArgumentError
      # into an error envelope get a clean message for free.
      class UnknownChangeTypeError < ArgumentError; end
      # Requestable and well-formed, but not actuatable yet. ArgumentError for
      # the same reason as above — callers already funnel it into an error
      # envelope with the message intact.
      class UnsupportedChangeTypeError < ArgumentError; end

      # Maps a signal kind (and optional payload metric) to the canonical
      # change_type used by the proposer + intervention policy resolver.
      CHANGE_TYPES = {
        "system.project_slo_violation" => "scale_horizontal",
        "system.project_drift" => "scale_horizontal",
        "system.project_cost_breach" => "cost_control"
      }.freeze

      # Allowed provisioning skills the proposer may emit. Must stay in
      # sync with Slice B's executors. Note: only the M2 adaptation
      # skills are listed here — initial-provisioning skills are not.
      ADAPTATION_SKILLS = %w[
        scale_project
        relocate_workload
        attach_storage
        configure_sdwan_for_project
      ].freeze

      # Change types the deterministic composer fully owns. Every
      # sensor-derived signal lands in this set (CHANGE_TYPES maps them to
      # scale_horizontal / cost_control, and region_count drift to relocate),
      # so the autonomous path is deterministic end-to-end. Change types only
      # an operator can request (schema_change, security_change) still route
      # to the LLM — see #build_steps_for.
      # `relocate` is deliberately NOT here. Its executor requires eight inputs
      # (from/to region, cutover strategy, template, instance type, count,
      # source instance ids, project id) and the heuristic composer has no
      # source for them, so routing relocate deterministically would compose a
      # step that cannot bind — the very defect this inversion removes. It
      # stays on the LLM path, and #bindable? drops whatever fails to carry
      # the kwargs. Move it here only alongside a composer that supplies them.
      DETERMINISTIC_CHANGE_TYPES = %w[scale_horizontal cost_control].freeze

      DEFAULT_SKILL_FOR_CHANGE = {
        "scale_horizontal" => "scale_project",
        "cost_control" => "scale_project",
        "relocate" => "relocate_workload",
        "schema_change" => "attach_storage",
        "security_change" => "configure_sdwan_for_project"
      }.freeze

      # Change types an EXPLICIT (operator / MCP-initiated) adaptation request
      # may name. Superset of `CHANGE_TYPES.values` because an operator can ask
      # for a relocate / schema / security change that no sensor signal derives
      # on its own — every entry must have a skill in DEFAULT_SKILL_FOR_CHANGE
      # so a composer has something to NAME.
      #
      # Naming a skill is NOT the same as being able to BIND it. This comment
      # used to claim the heuristic composer "can always produce at least one
      # step"; that stopped being true when #reject_unbindable landed, and the
      # claim is what hid the gap. For `relocate` / `schema_change` /
      # `security_change` the heuristic supplies only envelope keys
      # (mission_id, change_type, signal_kind, signal_payload, correlation_id)
      # and their executors require operational ones (instance_id + size_gb;
      # project_id + instance_ids + network_name + topology), so every
      # heuristic step for those three is DROPPED at the single exit of
      # #build_steps_for. Their working composer is the LLM path, which is
      # handed the operator's `details:` inside the signal payload plus, since
      # IMP-15d12f9ace83, each skill's declared input contract — see
      # #build_diff_prompt. A change type here composes when the LLM is
      # reachable AND the caller supplied the executor's required inputs; it
      # declines otherwise rather than emitting a step that dies on dispatch.
      REQUESTABLE_CHANGE_TYPES = (CHANGE_TYPES.values | DEFAULT_SKILL_FOR_CHANGE.keys).freeze

      # Signal kind stamped on the synthetic envelope built for an explicit
      # request, so downstream consumers can tell an operator-initiated
      # adaptation apart from a sensor-initiated one.
      EXPLICIT_SIGNAL_KIND = "operator.adaptation_request"

      # Inputs describing the footprint a mission already runs, read off its
      # original provisioning plan so a scale-out replicates that footprint
      # rather than inventing a new one — see #existing_footprint.
      #
      # `network_id` and `with_storage_gb` are the keys that make a composed
      # scale-out arrive with an SDWAN peer and a volume instead of bare
      # compute. This list carried both from the start, but the threading was
      # inert until IMP-cdc1d0703e5a: PlanComposerService did not STAMP either
      # key onto the `provision_full_stack` step it composes, so they were
      # absent from every plan this reads. It stamps both now, so this is a
      # working guarantee rather than plumbing — do not re-document it as one.
      #
      # These are the CANONICAL spellings, i.e. the keys a composed step
      # emits. For the spellings this tolerates on the way IN, see
      # FOOTPRINT_KEY_ALIASES.
      FOOTPRINT_KEYS = %w[
        template_id
        provider_region_id
        provider_instance_type_id
        network_id
        with_storage_gb
      ].freeze

      # Alternate spellings tolerated on a plan step's inputs, mapped onto the
      # canonical key above. Read-side only: the footprint always EMITS the
      # canonical key.
      #
      # The deterministic composer stamps `with_storage_gb`, but a plan built
      # by MissionComposer (the LLM-general path) or authored by hand may
      # declare the size as bare `storage_gb`. Both readers of a PROVISION
      # step's inputs already accept that spelling, canonical first:
      # `CostEstimatorService#declared_gb(inputs, "with_storage_gb",
      # "storage_gb")` prices it, and the actuating executor resolves it at run
      # time (`ProvisionFullStackExecutor.resolve_storage_gb`, first present).
      # This service was the one reader that did not, so a storage-bearing
      # mission written that way lost its storage and scaled out as bare
      # compute: the exact failure #existing_footprint exists to prevent,
      # arrived at through the spelling rather than through a missing key.
      #
      # Exactly those two spellings, deliberately. PlanSnapshotService accepts
      # a THIRD (`size_gb`) but only on an `attach_storage` step, and
      # #original_provision_inputs selects the step that named a template —
      # never that one — so `size_gb` is not an alias on this surface and
      # adding it here would invent tolerance no writer or executor has.
      #
      # NORMALIZED rather than carried through, which is why this is a map and
      # not two more entries in FOOTPRINT_KEYS. The footprint is merged
      # straight into the composed step's inputs, and `with_storage_gb` is the
      # only storage spelling the `scale_project` skill DECLARES; emitting the
      # alias would rest the composed step on the executor's run-time
      # tolerance instead of its declared schema.
      #
      # Canonical-first, matching the executors' own alias resolution: a step
      # carrying both spellings keeps the canonical value.
      FOOTPRINT_KEY_ALIASES = {
        "with_storage_gb" => %w[storage_gb]
      }.freeze

      # The only additive scaling strategy the `scale_project` skill offers.
      # A plain string flowing through the skill-resolution seam (slug →
      # bound executor) — core deliberately does not reference the extension
      # executor or its strategy list.
      SCALE_OUT_STRATEGY = "add_replicas"

      # The scale-IN strategy (INC-4). Named here as a plain string for the
      # same reason as SCALE_OUT_STRATEGY — it flows through the skill seam and
      # core does not reference the extension's strategy list.
      #
      # This is deliberately NOT a second entry in #auto_apply?'s allowlist:
      # removals never auto-apply regardless of bounds (ratified §4). It is
      # named here because two readers need it: `VerificationService` (a
      # removal creates nothing, so it must not be graded with the
      # instance-creation oracle) and the `cost_control` composer below, which
      # emits it (IMP-e68a93c47106).
      REMOVAL_STRATEGY = "remove_replicas"

      # The OTHER strategy that creates instances: a parallel stack in a NEW
      # region. Named here for the same reason as the two above — a plain
      # string flowing through the skill seam — and NOT proposed by this
      # service (nothing in core composes it; it arrives on operator-authored
      # or LLM-decomposed plans). It is named here because it is a
      # `scale_project` strategy and this is where core keeps that vocabulary.
      REGION_SCALE_OUT_STRATEGY = "add_region"

      # The `scale_project` strategies whose `target_count` means "instances to
      # CREATE". IMP-529b8514bbc6: the two readers of that question —
      # CostEstimatorService (is this delta real marginal compute?) and
      # VerificationService (how many instances must this step have produced?)
      # — each carried their own answer and DISAGREED about `add_region`: the
      # quote priced it as new compute while verification expected ZERO
      # instances from it, so a region scale-out that fully succeeded scored
      # "provisioned N/0" and failed its mission permanently.
      #
      # The skill's own input descriptor settles it — `target_count` is
      # "Number of instances to add (add_replicas / add_region)" — so both
      # readers now share ONE list rather than two hand-written rules about
      # the same seam. The skill's remaining arms (`vertical_resize`,
      # REMOVAL_STRATEGY) also carry a target_count and create NOTHING, which
      # is why this is an allowlist and not "anything but removal".
      INSTANCE_CREATING_STRATEGIES = [ SCALE_OUT_STRATEGY, REGION_SCALE_OUT_STRATEGY ].freeze

      # Scale-IN step size, by cost-breach severity.
      #
      # THE SHAPE LOOKS LIKE #recommended_replica_count's LADDER AND IS NOT THE
      # SAME THING, so do not "unify" them. The scale-OUT ladder steps off a
      # LIVE replica count that the scale-out itself moves, so successive
      # passes converge. This one reads `breach_pct` over MONTH-TO-DATE cost,
      # which is monotone non-decreasing within a billing month: removing
      # replicas lowers the burn RATE, never the accumulated total. So the
      # observation this ladder reads cannot improve in response to the action,
      # and once MTD passes the severe threshold every later proposal composes
      # the larger rung. There is no feedback loop here to converge.
      #
      # The bound is therefore doing ALL of the work, and that is why it is
      # small: it caps what a single proposal may shed on a reading that will
      # not answer back. Each proposal is also a separate human decision (a
      # removal never auto-applies), so the operator is the loop this metric
      # cannot close.
      #
      # Deliberately NOT proportional to the overshoot either. Shedding 30% of
      # spend is not "remove 30% of the replicas" — replicas do not cost the
      # same as each other (different instance types, different attached
      # storage), so a proportional count is a fiction dressed as arithmetic.
      #
      # `target_count` here is a COUNT TO REMOVE (a delta), so no absolute
      # baseline is fabricated and there is no ratchet to reintroduce. Both
      # rungs sit well inside the actuating skill's own 1..MAX_DELTA bound, and
      # the skill clamps the removal at its own replica floor — core never
      # composes a scale-to-zero.
      SEVERE_COST_BREACH_PCT   = 50.0
      SEVERE_REMOVAL_REPLICAS  = 2
      DEFAULT_REMOVAL_REPLICAS = 1

      # Kwargs the `scale_project` skill requires, as the deterministic
      # composer understands them. #bindable? reads requirements live through
      # the skill-resolution seam rather than from this list; it remains as the
      # composer's own statement of intent, and the extension-side contract
      # spec asserts it still matches the executor's declared required inputs
      # so composer and executor cannot drift apart silently.
      SCALE_PROJECT_REQUIRED_INPUTS = %w[
        project_id
        target_count
        scaling_strategy
      ].freeze

      # Fallback ceiling on a single scale-out step, used only when the
      # mission declares no `watch_policies.max_scale_out_delta`. The skill
      # that actuates the step enforces its own bound and rejects anything
      # above it; core cannot read that bound (it belongs to the executor
      # behind the skill seam), so this mirrors it as a documented core-side
      # default rather than importing it. See #max_scale_out_delta.
      DEFAULT_MAX_SCALE_OUT_DELTA = 50

      # Compute-side footprint keys the scaling skill requires for an
      # additive strategy. Without all three the step cannot bind, so the
      # composer declines rather than emitting it (see #scale_out_inputs).
      COMPUTE_FOOTPRINT_KEYS = %w[
        template_id
        provider_region_id
        provider_instance_type_id
      ].freeze

      # How often a repeating decline may log. See #log_decline_throttled.
      DECLINE_LOG_INTERVAL = 1.hour

      # Change types that remain REQUESTABLE — so the advertised MCP schema
      # stays stable — but cannot be actuated yet. An operator asking for one
      # gets this reason instead of a generic "nothing could be composed".
      #
      # CURRENTLY EMPTY. The accurate statement is narrower than the one this
      # comment used to make ("every requestable change type has a composer"):
      # every requestable change type has a REACHABLE composer, but not every
      # one has a DETERMINISTIC composer that binds unaided.
      #
      #   scale_horizontal / cost_control — deterministic, bind unaided.
      #   relocate / schema_change / security_change — the LLM path is their
      #     only composer. It binds when the model is reachable and the
      #     required executor inputs are available to it (the operator's
      #     `details:` ride into the prompt via the signal payload, and
      #     #build_diff_prompt now states each skill's input contract). When
      #     either condition fails, #reject_unbindable drops the step and the
      #     caller gets an empty plan.
      #
      # An entry here would mean "cannot be actuated under ANY reachable
      # condition". None of the five qualifies: an empty plan from an
      # unreachable LLM is a runtime/deployment outcome, not a property of the
      # change type, and declaring it here would refuse the request even where
      # the lane works. `cost_control` was the last entry and was removed in
      # IMP-e68a93c47106 when the scale-in composer below landed — an
      # advertisement of "not supported" that outlives its cause is its own
      # defect. The mechanism stays because the next change type to be
      # requestable-before-actuatable needs it; an entry here must be deleted
      # in the same commit that composes for it.
      UNSUPPORTED_CHANGE_TYPES = {}.freeze

      DEFAULT_TEMPERATURE = 0.2
      DEFAULT_MAX_TOKENS  = 1024

      attr_reader :account, :mission

      def initialize(account:, mission:)
        @account = account
        @mission = mission
        raise MissionMissingError, "mission required" unless mission
      end

      # Build a diff plan from one or more signals. Returns the persisted
      # `Ai::GoalPlan` (with `Ai::GoalPlanStep` rows of step_type
      # "provisioning_skill"), or nil when no signal yields a non-empty
      # diff. Defensive try/rescue per-helper so an LLM failure or a
      # single missing lookup doesn't cascade — the worst case is an
      # empty plan rather than an exception bubbling up to the engine.
      def propose_from_signals(signals:)
        signals = Array(signals).compact
        return nil if signals.empty?

        primary = primary_signal(signals)
        compose_and_route!(signal: primary, change_type: derive_change_type(primary))[:plan]
      rescue StandardError => e
        Rails.logger.warn("[AdaptationProposerService] propose failed mission=#{mission.id}: #{e.class}: #{e.message}")
        nil
      end

      # Explicit, operator-initiated adaptation request — the seam the MCP
      # `platform_provisioning_adapt` action calls. It does NOT bypass any of
      # the signal path: the change request is wrapped in a signal-shaped
      # envelope and handed to the same `compose_and_route!` internal, so step
      # composition and plan persistence are byte-identical to the sensor path
      # — and the caller then routes the result through the same
      # `adaptation_gate`, so both paths join one queue.
      #
      # Unlike `propose_from_signals` (called from a reconciler, where an
      # exception must never cascade) this raises, so an interactive caller
      # gets a real message instead of a silent nil.
      #
      # @param change_type [String] one of REQUESTABLE_CHANGE_TYPES
      # @param metric [String, nil] optional metric that motivated the request
      # @param details [Hash, nil] optional structured payload (observed,
      #   target, breach_pct, target_usd, correlation_id, …)
      # @return [Hash] { plan:, change_type:, signal:, auto_apply: } —
      #   `plan` is nil when no diff could be composed; `auto_apply` is the
      #   downgrade-only bounds verdict, not a decision to apply.
      def propose_change(change_type:, metric: nil, details: nil)
        normalized = change_type.to_s.strip
        unless REQUESTABLE_CHANGE_TYPES.include?(normalized)
          raise UnknownChangeTypeError,
                "Unknown change_type '#{change_type}' — must be one of: " \
                "#{REQUESTABLE_CHANGE_TYPES.join(', ')}"
        end

        # Interactive caller — give it the actionable reason rather than
        # letting composition return an empty result the caller can only
        # report as "nothing could be composed". The sensor path stays silent
        # (it declines inside the composer); only this one raises, matching
        # this method's documented raise-don't-swallow contract.
        if (reason = UNSUPPORTED_CHANGE_TYPES[normalized])
          raise UnsupportedChangeTypeError, reason
        end

        signal = explicit_signal(normalized, metric: metric, details: details)
        compose_and_route!(signal: signal, change_type: normalized)
      end

      # DOWNGRADE-ONLY bounds check (IMP-8c37b9e5ccd5, ratified §4).
      #
      # This is NOT a decision to apply. It is core's single contribution to
      # the gate decision: `Ai::Provisioning::AdaptationDispatchService` hands
      # the result to the `adaptation_gate` seam as `auto_apply_eligible`.
      # False PARKS the plan behind the gate; true merely permits the gate —
      # the fleet ApprovalRequest chain + InterventionPolicy — to grant
      # immediate application. It may never skip a required gate, and the
      # dispatcher refuses a gate answer that tries to widen it.
      #
      # FAIL-CLOSED ALLOWLIST. The previous form SELECTED the additive
      # scale_project steps and measured only those, so a plan carrying a
      # relocate or a storage reshape alongside one in-bounds scale step
      # reported true and would have auto-applied a cross-region move. Every
      # step must now be an additive scale-out inside the mission's replica
      # ceiling; anything else is out of bounds.
      #
      # REMOVALS NEVER AUTO-APPLY, regardless of bounds. Stating that as an
      # allowlist of the one additive strategy this composer emits — rather
      # than a blocklist of scale-in names — means INC-4's `remove_replicas`,
      # and any strategy after it, is ineligible by construction instead of by
      # remembering to add it.
      def auto_apply?(plan:)
        return false unless plan

        steps = plan.steps.to_a
        # An empty plan is not vacuously safe to apply — there is nothing to
        # have judged in bounds.
        return false if steps.empty?

        max_replicas = watch_policies["auto_scale_max_replicas"]&.to_i
        return false if max_replicas.nil? || max_replicas <= 0

        steps.all? { |s| additive_scale_out_within?(s, max_replicas) }
      rescue StandardError => e
        Rails.logger.warn("[AdaptationProposerService] auto_apply? failed: #{e.message}")
        false
      end

      # ----- internal seams (stubbed in specs) ------------------------------

      # Returns an array of step descriptors:
      #   [{ "skill" => String, "inputs" => {...}, "on_failure" => "rollback"|"continue" }]
      # The LLM is allowed to omit the array entirely (returns nil) — in
      # which case the heuristic fallback in #build_steps_for kicks in.
      def diff_from_llm(signal:, change_type:)
        client = llm_client
        return nil unless client

        prompt = build_diff_prompt(signal, change_type)
        response = safe_complete(
          client,
          messages: [ { role: "user", content: prompt } ],
          max_tokens: DEFAULT_MAX_TOKENS,
          temperature: DEFAULT_TEMPERATURE
        )
        return nil unless response&.success?

        parse_diff_json(response.content)
      end

      def llm_client
        @llm_client ||= build_llm_client
      end

      private

      # The single composition path shared by the sensor-driven
      # (`propose_from_signals`) and the operator-driven (`propose_change`)
      # entrypoints. Nothing may compose a diff plan without passing through
      # here, so every plan reaching the gate has the same shape and carries
      # the same provenance.
      def compose_and_route!(signal:, change_type:)
        diff_steps = build_steps_for(signal, change_type)
        return empty_result(signal, change_type) if diff_steps.blank?

        plan = persist_diff_plan!(change_type, diff_steps, signal)
        return empty_result(signal, change_type) unless plan

        # Composition ONLY. Gating belongs to
        # Ai::Provisioning::AdaptationDispatchService via the `adaptation_gate`
        # seam — see the class doc for why this service no longer routes.
        # `auto_apply` here is the downgrade-only bounds verdict, not a
        # decision to apply.
        {
          plan: plan,
          change_type: change_type,
          signal: signal,
          auto_apply: auto_apply?(plan: plan)
        }
      end

      def empty_result(signal, change_type)
        { plan: nil, change_type: change_type, signal: signal, auto_apply: false }
      end

      # One step of a diff plan is eligible for auto-apply only if it is the
      # additive scale-out this composer emits, carries a real delta, and lands
      # at or below the mission's replica ceiling. See #auto_apply? for why
      # this is an allowlist.
      def additive_scale_out_within?(step, max_replicas)
        cfg = step_config(step)
        return false unless cfg["skill"].to_s == "scale_project"

        inputs = cfg["inputs"].is_a?(Hash) ? cfg["inputs"] : {}
        return false unless inputs["change_type"].to_s == "scale_horizontal"
        return false unless inputs["scaling_strategy"].to_s == SCALE_OUT_STRATEGY
        return false unless inputs["target_count"].to_i.positive?

        desired = inputs["desired_replica_count"].to_i
        desired.positive? && desired <= max_replicas
      end

      # Signal-shaped envelope for an explicit request. Hash form is
      # deliberate: every reader (#signal_kind, #signal_payload,
      # #signal_severity) already accepts a Hash, so no branch is needed
      # anywhere downstream.
      def explicit_signal(change_type, metric:, details:)
        payload = details.respond_to?(:deep_stringify_keys) ? details.deep_stringify_keys : {}
        payload = {} unless payload.is_a?(Hash)
        payload = payload.dup
        payload["metric"] = metric.to_s if metric.present?
        payload["mission_id"] ||= mission.id
        payload["change_type"] = change_type
        payload["requested_via"] = "operator"
        payload["correlation_id"] ||= "provisioning_adapt:#{mission.id}:#{SecureRandom.hex(4)}"

        {
          "kind" => EXPLICIT_SIGNAL_KIND,
          "severity" => payload["severity"].presence || "high",
          "payload" => payload
        }
      end

      # Wrapped so this service's LLM calls land Ai::AgentExecution records —
      # cost, tokens, performance_metrics and the budget debit (IMP 019fe1da).
      # #tracked_client_for wraps without re-routing which provider serves the
      # call; see its doc for why, and for why there is no double-debit.
      def build_llm_client
        return nil unless defined?(::WorkerLlmClient)

        tracked_client_for(
          ::WorkerLlmClient.for_account(account),
          slugs: ::Ai::Provisioning::TrackingAgents::SLUGS
        )
      rescue StandardError => e
        Rails.logger.warn("[AdaptationProposerService] LLM client unavailable: #{e.message}")
        nil
      end

      def safe_complete(client, **opts)
        client.complete(model: resolve_model, **opts)
      rescue StandardError => e
        Rails.logger.warn("[AdaptationProposerService] LLM call failed: #{e.message}")
        nil
      end

      # Same provider-aware strategy as IntentCaptureService: prefer an
      # explicit agent-configured model, otherwise resolve the model from the
      # same provider WorkerLlmClient.for_account picks (the account's first
      # active *credential's* provider) so the model ID is compatible with
      # whatever HTTP client the worker actually instantiates.
      def resolve_model
        agent = mission.respond_to?(:conversation) ? mission.conversation&.agent : nil
        model = agent&.try(:model)
        model ||= agent&.mcp_tool_manifest&.dig("model")
        return model if model.present?

        credential = account&.ai_provider_credentials&.active
                            &.includes(:provider)&.first
        credential&.provider&.default_model.presence || "gpt-4.1-mini"
      end

      # ----- signal selection / classification ----------------------------

      def primary_signal(signals)
        # Pick the highest-severity signal first; fall back to the first.
        order = { critical: 0, high: 1, medium: 2, low: 3 }
        sorted = signals.sort_by do |s|
          sev = (s.respond_to?(:severity) ? s.severity : (s[:severity] || s["severity"])).to_s.to_sym
          order[sev] || 99
        end
        sorted.first
      end

      def signal_kind(signal)
        return signal.kind if signal.respond_to?(:kind)
        signal[:kind] || signal["kind"]
      end

      def signal_payload(signal)
        raw = if signal.respond_to?(:payload)
          signal.payload
        else
          signal[:payload] || signal["payload"]
        end
        return {} unless raw.is_a?(Hash)
        raw.deep_stringify_keys
      end

      def signal_severity(signal)
        sev = signal.respond_to?(:severity) ? signal.severity : (signal[:severity] || signal["severity"])
        sev.to_s
      end

      # A sensor Signal carries `fingerprint` as an attribute; the synthetic
      # envelope #explicit_signal builds for an operator request is a plain Hash
      # and carries none — nil is the correct, meaningful answer there, not a
      # gap to fill in. Returns nil rather than "" so the plan_data `.compact`
      # drops the key entirely.
      def signal_fingerprint(signal)
        raw = if signal.respond_to?(:fingerprint)
          signal.fingerprint
        else
          signal[:fingerprint] || signal["fingerprint"]
        end
        raw.presence&.to_s
      end

      def derive_change_type(signal)
        kind = signal_kind(signal)
        payload = signal_payload(signal)

        # Drift on region count → relocate. Otherwise honor the kind→change map.
        if kind == "system.project_drift" && payload["drift_type"].to_s == "region_count"
          return "relocate"
        end

        CHANGE_TYPES[kind] || "scale_horizontal"
      end

      # ----- step composition ---------------------------------------------

      # DETERMINISTIC-FIRST. The LLM used to run first and win whenever it
      # returned anything allowlisted — #sanitize_steps validates the skill
      # slug and injects mission_id, nothing else — so with an active provider
      # credential (the production default) the deterministic composer below
      # never ran. LLM steps shipped without `project_id` / `target_count` /
      # `scaling_strategy` and failed at execution with "missing required
      # input: project_id", and the cost_control decline was unreachable.
      #
      # The deterministic composer is the one that knows the executor
      # contract, so it OWNS every change type it can compose — which is
      # every sensor-derived one. The LLM is reserved for change types only an
      # operator can request, where there is no structured composition to use.
      # This mirrors the provisioning decomposition redesign, which replaced
      # LLM decomposition with deterministic synthesis for recognized briefs.
      #
      # An EMPTY deterministic result is a decision (converged), never a miss —
      # it must not fall through to the LLM.
      def build_steps_for(signal, change_type)
        steps =
          if DETERMINISTIC_CHANGE_TYPES.include?(change_type)
            stamp_composition_source!(heuristic_steps(signal, change_type), "deterministic")
          else
            from_llm = safe_call { diff_from_llm(signal: signal, change_type: change_type) }
            sanitized = sanitize_steps(from_llm)
            if sanitized.any?
              decorate_with_signal_metadata!(sanitized, signal)
              stamp_composition_source!(sanitized, "llm")
            else
              stamp_composition_source!(heuristic_steps(signal, change_type), "deterministic")
            end
          end

        # ONE guard, applied to whatever composed the steps. Putting it only
        # in #sanitize_steps covered the LLM path and left the heuristic
        # branch — which never passes through there — free to emit a step
        # that cannot bind.
        reject_unbindable(steps)
      end

      def reject_unbindable(steps)
        Array(steps).select do |step|
          inputs = step["inputs"].is_a?(Hash) ? step["inputs"] : {}
          bindable?(step["skill"].to_s, inputs)
        end
      end

      # Provenance stamp so an operator reading a persisted plan can tell
      # which composer produced each step. Lives at step level rather than in
      # `inputs` so it never reaches an executor as a kwarg.
      def stamp_composition_source!(steps, source)
        Array(steps).each { |step| step["composed_by"] = source }
      end

      # Mirror the heuristic path: ensure correlation_id from the originating
      # signal flows into LLM-proposed step inputs so downstream skill
      # executors can correlate the action with the alert that triggered it.
      # `||=` preserves any value the LLM supplied explicitly.
      def decorate_with_signal_metadata!(steps, signal)
        correlation_id = signal_payload(signal)["correlation_id"]
        return steps if correlation_id.blank?

        steps.each do |step|
          inputs = (step["inputs"] ||= {})
          inputs["correlation_id"] ||= correlation_id
        end
        steps
      end

      def heuristic_steps(signal, change_type)
        payload = signal_payload(signal)
        skill   = DEFAULT_SKILL_FOR_CHANGE[change_type] || "scale_project"

        inputs = {
          "mission_id" => mission.id,
          "change_type" => change_type,
          "signal_kind" => signal_kind(signal),
          "signal_payload" => payload,
          "correlation_id" => payload["correlation_id"]
        }

        case change_type
        when "scale_horizontal"
          scale_inputs = scale_out_inputs(payload)
          return [] if scale_inputs.nil?

          inputs.merge!(scale_inputs)
        when "cost_control"
          inputs.merge!(scale_in_inputs(payload))
        when "relocate"
          inputs["target_regions"] = brief_regions
        end

        [
          {
            "skill" => skill,
            "inputs" => inputs.compact,
            "on_failure" => "rollback"
          }
        ]
      end

      def sanitize_steps(steps)
        Array(steps).filter_map do |raw|
          next nil unless raw.is_a?(Hash)
          h = raw.deep_stringify_keys
          skill = h["skill"].to_s
          next nil unless ADAPTATION_SKILLS.include?(skill)

          inputs = h["inputs"].is_a?(Hash) ? h["inputs"] : {}
          inputs["mission_id"] ||= mission.id
          on_failure = %w[rollback continue].include?(h["on_failure"]) ? h["on_failure"] : "rollback"

          { "skill" => skill, "inputs" => inputs, "on_failure" => on_failure }
        end
      end

      # A composed step must carry the inputs its executor requires, NO MATTER
      # which skill it names or which composer produced it. #sanitize_steps
      # validates only the skill slug, so without this a step ships and dies
      # on dispatch with "missing required input: …".
      #
      # Deliberately generic: an earlier version special-cased `scale_project`
      # and waved every other skill through, which is how `relocate_workload`
      # (8 required inputs, none of which the heuristic supplies) slipped past.
      # Requirements are read through SkillCompositionRunner's resolution seam
      # — the same slug → executor lookup that dispatch uses — so core never
      # names an executor and a newly added skill is covered automatically.
      #
      # An UNRESOLVABLE skill (nil requirements) is allowed through rather than
      # dropped: core mode legitimately has no executors loaded, and silently
      # composing nothing there would be worse than letting dispatch report a
      # missing skill.
      def bindable?(skill, inputs)
        required = ::Ai::Provisioning::SkillCompositionRunner.required_inputs_for(skill)
        return true if required.nil? || required.empty?

        missing = required.reject { |key| inputs[key].present? }
        return true if missing.empty?

        Rails.logger.warn(
          "[AdaptationProposerService] dropping #{skill} step for mission=#{mission.id}: " \
          "missing required executor inputs #{missing.inspect}"
        )
        false
      end

      # Composes the scale-out half of a `scale_horizontal` adaptation, or nil
      # when there is nothing to do. Returning nil collapses the whole diff to
      # empty, so the proposer produces no plan at all — that is what makes a
      # converged system quiet.
      #
      # Two different semantics share this branch and must not be conflated:
      #
      #   DRIFT — the signal carries both the ground truth (`observed`) and
      #     the declared `target`, so the correct action is to CONVERGE: close
      #     exactly the observed gap. Composing off `brief.scale.initial`
      #     instead ignored the observation entirely, and because the drift
      #     sensor derives its expected replica count FROM that same brief
      #     value, every drift proposal landed exactly one above the target
      #     and re-fired on the next tick — a ratchet, not a correction.
      #
      #   SLO — a latency/availability breach has no replica target to
      #     converge on, so the deliberate +1/+2 stepping is
      #     kept — but it steps off the OBSERVED count, not the brief. Only
      #     the step SIZE is preserved; anchoring it to the brief is what
      #     made the baseline a constant.
      def scale_out_inputs(payload)
        # Read the observation ONCE and thread it through. Two independent
        # reads race the metrics collector on the same 60s tick chain: a row
        # landing between them makes the delta non-positive (the proposal
        # silently vanishes) or overshoots the target.
        observed = observed_replica_count(payload)
        return nil if observed.nil?

        desired = recommended_replica_count(payload, observed: observed)
        return nil if desired.nil?

        delta = desired - observed
        if delta <= 0
          # Converged (0) or over-provisioned (<0). Emitting an add_replicas
          # step for an over-count would grow a fleet that is already too
          # large, so stay quiet.
          #
          # A scale-IN strategy DOES exist now (see #scale_in_inputs), so
          # over-provision drift is composable in principle — it is out of
          # scope for IMP-e68a93c47106, which wired `cost_control` only. This
          # arm stays additive by DECISION, not by impossibility; widening it
          # means giving drift the same never-auto-apply treatment removals get
          # and is its own piece of work.
          log_decline_throttled(
            "no_scale_out",
            "[AdaptationProposerService] no scale-out composed mission=#{mission.id} " \
            "observed=#{observed} desired=#{desired} (delta=#{delta})"
          )
          return nil
        end

        # Decline at COMPOSE time when the compute-side footprint is unknown.
        # A mission composed by a path that emits no template (or whose
        # original plan is gone) yields no template/region/instance-type, and
        # the scaling skill rejects `add_replicas` without all three. Since
        # #auto_apply? only measures the replica ceiling, an auto-apply policy
        # would happily dispatch a step we already know cannot bind — the
        # exact failure this composition exists to remove. Decline instead.
        footprint = existing_footprint
        missing = COMPUTE_FOOTPRINT_KEYS.reject { |key| footprint[key].present? }
        if missing.any?
          log_decline_throttled(
            "missing_footprint",
            "[AdaptationProposerService] no scale-out composed mission=#{mission.id}: " \
            "unresolved footprint #{missing.inspect} — cannot bind #{SCALE_OUT_STRATEGY}"
          )
          return nil
        end

        # Bound a single step. The actuating skill rejects a delta above its
        # own ceiling outright, so an unclamped delta composes a step that
        # cannot bind. Clamping converges across successive passes instead —
        # each pass closes up to the ceiling, monotonically toward target.
        delta = [ delta, max_scale_out_delta ].min

        # What this step actually REACHES, which is below `desired` whenever
        # the delta was clamped. #auto_apply? measures this against
        # `auto_scale_max_replicas`, so reporting the unreachable absolute
        # would refuse auto-apply for a step well inside policy and strand
        # the multi-pass convergence above, which only works unattended.
        reachable = observed + delta

        {
          # Absolute count this step reaches — the policy-facing value
          # #auto_apply? measures, and what the step description renders.
          "desired_replica_count" => reachable,
          # Executor-facing kwargs. `target_count` is a DELTA ("number of new
          # instances"), NOT an absolute count — passing the absolute here
          # would provision `desired` instances on top of the `observed` ones
          # already running.
          "project_id" => mission.id,
          "target_count" => delta,
          "scaling_strategy" => SCALE_OUT_STRATEGY
        }.merge(footprint)
      end

      # Composes the scale-IN half of a `cost_control` adaptation
      # (IMP-e68a93c47106). Always returns inputs — unlike #scale_out_inputs
      # there is no arm that can decline, and the asymmetry is the point:
      #
      #   A SCALE-OUT must know the fleet. It reports an ABSOLUTE
      #   `desired_replica_count` measured against the mission's ceiling, and
      #   it has to name the template / region / instance type the new replicas
      #   are cut from. Absent any of those it composes a step that cannot bind
      #   — so it declines.
      #
      #   A REMOVAL knows enough by construction. `target_count` is a COUNT TO
      #   REMOVE, the actuating skill resolves the victims itself (the newest
      #   replicas of this mission's own set, behind its blast-radius prefix
      #   rail) and clamps at its own replica floor, and nothing is created, so
      #   no footprint is required. The three kwargs below are the executor's
      #   full contract for this strategy.
      #
      # No `desired_replica_count`: a removal has no absolute target, and
      # inventing one would hand #auto_apply? a number to measure on a plan
      # that must be ineligible regardless of any number.
      def scale_in_inputs(payload)
        {
          "project_id" => mission.id,
          "target_count" => removal_replica_count(payload),
          "scaling_strategy" => REMOVAL_STRATEGY
        }
      end

      # See the SEVERE_COST_BREACH_PCT / *_REMOVAL_REPLICAS constants for why
      # this is a bounded ladder rather than a proportional shed.
      def removal_replica_count(payload)
        return SEVERE_REMOVAL_REPLICAS if payload["breach_pct"].to_f >= SEVERE_COST_BREACH_PCT

        DEFAULT_REMOVAL_REPLICAS
      end

      # Where the mission is scaling FROM — the LIVE fleet, never the brief.
      #
      # Both kinds of signal carry the count in their own payload: drift as
      # `observed`, an SLO breach as `replica_count` (its `observed` is the
      # breached metric — latency, availability — not a count). The sensor is
      # the only reader of the telemetry; this service never consults metric
      # rows, `latest_observations`, or the brief.
      #
      # This baseline MUST be live. Stepping off `brief.scale.initial` makes
      # `desired_replica_count` a CONSTANT, so #auto_apply?'s
      # `auto_scale_max_replicas` ceiling never binds to the actual fleet:
      # every tick recomputes the same "within cap" number while the fleet
      # grows by the step size (3 → 5 → 7 → 9), each step reporting
      # auto_apply: true. That is the same ratchet this service removes from
      # the drift path, and it must not be reintroduced here.
      # A real 0 is an OBSERVATION ("nothing is running"), not "unknown", and
      # the two must not collapse: a fleet that is fully down while a critical
      # availability breach fires is the strongest case for scaling out, and
      # `primary_signal` sorts that breach ahead of the medium replica-drift
      # signal, so the SLO path is the one that has to compose it. Only a
      # genuine absence of any reading returns nil.
      def observed_replica_count(payload)
        return payload["observed"].to_i if replica_drift?(payload)

        # SLO breaches carry the fleet size alongside the breached metric
        # (`observed` there is latency/availability, not a count). The sensor
        # that samples the telemetry is the ONLY reader — core does not query
        # metrics itself, which would both duplicate the sampler and make core
        # depend on an extension.
        #
        # Absent means "cannot see the fleet", and that is NOT the same
        # statement as "the fleet is at its declared initial size". Falling
        # back to `brief.scale.initial` here would make the baseline a
        # constant, which is precisely the ratchet documented above: every
        # tick would recompute the same "within cap" number while the fleet
        # grew. An unobservable fleet must DECLINE, never degrade to intent.
        count = payload["replica_count"]
        count.nil? ? nil : count.to_i
      end

      # DB-driven per the platform's config convention: the mission's own
      # `watch_policies` owns this, alongside `auto_scale_max_replicas`.
      # Falls back to the documented core-side default.
      # Bounded ABOVE by the core-side default as well: a mission configuring
      # 100 against an actuator that refuses anything over its own ceiling
      # would compose exactly the unbindable step this clamp exists to
      # prevent. Config may only lower the bound, never raise it.
      def max_scale_out_delta
        configured = watch_policies["max_scale_out_delta"].to_i
        return DEFAULT_MAX_SCALE_OUT_DELTA unless configured.positive?

        [ configured, DEFAULT_MAX_SCALE_OUT_DELTA ].min
      end

      # These declines re-evaluate on every tick, so an unthrottled log would
      # repeat forever for a persistent breach. Keyed per mission and reason
      # so distinct causes still surface independently.
      #
      # Fails OPEN: with no usable cache (null store, or a backend that
      # errors) the message is logged rather than dropped — a repeated log is
      # a smaller problem than a silently lost one.
      def log_decline_throttled(reason, message)
        store = Rails.cache
        if store.nil? || store.is_a?(::ActiveSupport::Cache::NullStore)
          Rails.logger.info(message)
          return
        end

        key = "adaptation_proposer:decline:#{mission.id}:#{reason}"
        return unless store.write(key, true, expires_in: DECLINE_LOG_INTERVAL, unless_exist: true)

        Rails.logger.info(message)
      rescue StandardError
        Rails.logger.info(message)
      end

      def recommended_replica_count(payload, observed:)
        # Drift → converge on the declared target.
        return payload["target"].to_i if replica_drift?(payload)

        # SLO violation → step up from the LIVE count. The +1/+2 stepping is
        # deliberate — an SLO breach has no replica target to converge on —
        # so only the BASELINE changes here, never the step size. `observed`
        # is threaded in (never re-read) and may legitimately be 0.
        current = observed
        return nil if current.nil?

        breach = payload["breach_pct"].to_f
        delta = if breach >= 50.0 then 2
        elsif breach >= 25.0 then 1
        else 1
        end

        current + delta
      end

      def replica_drift?(payload)
        payload["drift_type"].to_s == "replica_count" &&
          payload["observed"].present? && payload["target"].present?
      end

      # The footprint the mission already runs, read off the provisioning plan
      # it was built from (`configuration.plan.plan_id` — the same seam
      # VerificationService resolves). A scale-out must land on the same
      # template/region/instance-type, and must carry the same network and
      # per-instance storage, otherwise the new replicas come up as bare
      # compute: no SDWAN peer, no volume.
      #
      # Missing keys are omitted rather than nil-filled so the executor's own
      # required-input check fails loud instead of silently provisioning a
      # degraded replica.
      def existing_footprint
        @existing_footprint ||= normalize_footprint_aliases(original_provision_inputs)
          .slice(*FOOTPRINT_KEYS)
          .reject { |_k, v| v.nil? }
      end

      # Fold each tolerated alias onto its canonical key BEFORE the slice, so
      # the slice stays a plain statement of what a footprint contains. Only
      # fills a canonical key that is absent — see FOOTPRINT_KEY_ALIASES for
      # why precedence runs canonical-first.
      #
      # One memo, so several canonical keys fold independently. Do not add an
      # entry whose canonical key is another entry's ALIAS: each iteration
      # reads a value earlier ones may have written, so a chain would resolve
      # in map order rather than by precedence.
      def normalize_footprint_aliases(inputs)
        FOOTPRINT_KEY_ALIASES.each_with_object(inputs.dup) do |(canonical, aliases), out|
          next if out[canonical].present?

          fallback = aliases.filter_map { |key| out[key] }.find(&:present?)
          out[canonical] = fallback if fallback
        end
      end

      def original_provision_inputs
        plan_id = mission.configuration.is_a?(Hash) ? mission.configuration.dig("plan", "plan_id") : nil
        return {} if plan_id.blank?

        # Account-scoped: `plan_id` comes off mission configuration, and an
        # unscoped lookup would read another tenant's plan if it were ever
        # wrong. Scope regardless of likelihood.
        plan = ::Ai::GoalPlan.where(account_id: account.id).find_by(id: plan_id)
        return {} unless plan

        # The provisioning step is the one that named a template — matching on
        # that rather than on a skill slug keeps this agnostic to which
        # provisioning skill composed the original plan.
        #
        # KNOWN GAP (deferred, needs a placement decision): a multi-region
        # mission fans out into one provision step PER REGION, and this takes
        # the first. There is nothing here to tie-break on — neither the drift
        # nor the SLO signal payload carries a region (both are mission-wide
        # aggregates: `actual_replica_count` is a total, not a per-region
        # count), so "which region absorbs the scale-out" is an unanswered
        # placement-policy question (spread evenly? fill the emptiest? follow
        # operator policy?) rather than a lookup bug. Picking the first region
        # is at least deterministic and matches the mission's own first step.
        step = plan.steps.in_order.detect { |s| step_config(s).dig("inputs", "template_id").present? }
        return {} unless step

        step_config(step)["inputs"] || {}
      rescue StandardError => e
        Rails.logger.warn("[AdaptationProposerService] footprint lookup failed: #{e.message}")
        {}
      end

      def brief_regions
        Array(brief["regions"])
      end

      def brief
        @brief ||= begin
          cfg = mission.configuration.is_a?(Hash) ? mission.configuration.deep_stringify_keys : {}
          cfg["brief"].is_a?(Hash) ? cfg["brief"] : {}
        end
      end

      def watch_policies
        @watch_policies ||= begin
          cfg = mission.configuration.is_a?(Hash) ? mission.configuration.deep_stringify_keys : {}
          cfg["watch_policies"].is_a?(Hash) ? cfg["watch_policies"] : {}
        end
      end

      # ----- persistence --------------------------------------------------

      def persist_diff_plan!(change_type, diff_steps, signal)
        goal = find_or_create_goal!(change_type, signal)
        next_version = (::Ai::GoalPlan.where(goal_id: goal.id).maximum(:version) || 0) + 1

        plan = ::Ai::GoalPlan.create!(
          account: account,
          goal: goal,
          agent: goal.agent,
          status: "draft",
          version: next_version,
          plan_data: {
            "kind" => "adaptation_diff",
            "change_type" => change_type,
            "signal_kind" => signal_kind(signal),
            # The key the remediation outcome is scored by. Absent on the
            # operator path by design — an explicit request has no sensor
            # signal that could ever clear, and the consumer refuses to record
            # an outcome without one rather than manufacture a free EFFECTIVE.
            "signal_fingerprint" => signal_fingerprint(signal),
            "signal_payload" => signal_payload(signal),
            "mission_id" => mission.id
          }.compact
        )

        diff_steps.each_with_index do |step_attrs, idx|
          plan.steps.create!(
            step_number: idx + 1,
            step_type: "provisioning_skill",
            status: "pending",
            description: build_step_description(step_attrs, change_type),
            execution_config: step_attrs,
            dependencies: idx.zero? ? [] : [ idx ]
          )
        end

        plan
      end

      def find_or_create_goal!(change_type, signal)
        existing = ::Ai::AgentGoal
          .where(account_id: account.id)
          .where("metadata @> ?", { "provisioning_mission_id" => mission.id, "kind" => "adaptation" }.to_json)
          .active
          .order(created_at: :desc)
          .first
        return existing if existing

        agent = resolve_agent
        ::Ai::AgentGoal.create!(
          account: account,
          agent: agent,
          title: "Adapt: #{mission.name} (#{change_type})",
          description: "Adaptation in response to #{signal_kind(signal)}",
          goal_type: "improvement",
          status: "pending",
          priority: 3,
          progress: 0.0,
          success_criteria: { "mission_id" => mission.id, "change_type" => change_type },
          metadata: { "provisioning_mission_id" => mission.id, "kind" => "adaptation" }
        )
      end

      def resolve_agent
        agent = account.ai_agents.where(status: "active").first if account.respond_to?(:ai_agents)
        agent ||= account.ai_agents.first if account.respond_to?(:ai_agents)
        agent
      end

      def build_step_description(step_attrs, change_type)
        skill = step_attrs["skill"]
        case skill
        when "scale_project"
          # A removal carries a DELTA, not an absolute, so the scale-out
          # rendering ("→ N replicas") would read as a target it never had.
          if step_attrs.dig("inputs", "scaling_strategy").to_s == REMOVAL_STRATEGY
            count = step_attrs.dig("inputs", "target_count")
            "Scale project in (#{change_type}) → remove #{count} replica(s)"
          else
            desired = step_attrs.dig("inputs", "desired_replica_count")
            "Scale project (#{change_type})#{desired ? " → #{desired} replicas" : ''}"
          end
        when "relocate_workload"
          regions = Array(step_attrs.dig("inputs", "target_regions")).join(", ")
          "Relocate workload#{regions.empty? ? '' : " → #{regions}"}"
        when "attach_storage"
          "Attach storage to project"
        when "configure_sdwan_for_project"
          "Reconfigure SDWAN for project"
        else
          "Adaptation step (#{skill})"
        end
      end

      # ----- helpers ------------------------------------------------------

      def step_config(step)
        cfg = step.execution_config
        cfg.is_a?(Hash) ? cfg.deep_stringify_keys : {}
      end

      def safe_call
        yield
      rescue StandardError => e
        Rails.logger.warn("[AdaptationProposerService] helper failed: #{e.message}")
        nil
      end

      # ----- prompts / parsing -------------------------------------------

      def build_diff_prompt(signal, change_type)
        kind = signal_kind(signal)
        severity = signal_severity(signal)
        payload = signal_payload(signal)
        slo = mission.configuration.is_a?(Hash) ? mission.configuration["slo_targets"] : {}

        <<~PROMPT
          You are an infrastructure adaptation planner. The running mission
          "#{mission.name}" raised a #{severity} #{kind} signal. Propose the
          smallest set of provisioning steps that brings the mission back
          into spec.

          Return ONLY a JSON array of steps. Each step:
            { "skill": one of #{ADAPTATION_SKILLS.inspect},
              "inputs": { ... structured input for the skill ... },
              "on_failure": "rollback" | "continue" }

          #{skill_contracts_block}
          Mission brief:
          #{JSON.dump(brief)}

          SLO targets:
          #{JSON.dump(slo)}

          Signal payload:
          #{JSON.dump(payload)}

          Recommended change_type: #{change_type}
        PROMPT
      end

      # The input contract for every skill the model may name, rendered into
      # the prompt (IMP-15d12f9ace83).
      #
      # WHY THIS EXISTS. The prompt used to hand the model skill NAMES only —
      # `ADAPTATION_SKILLS.inspect` plus the placeholder "structured input for
      # the skill". Nothing told it that `attach_storage` needs `instance_id`
      # and `size_gb`, or that `configure_sdwan_for_project` needs
      # `project_id`, `instance_ids`, `network_name` and `topology`. A model
      # asked to invent key names guesses (`node_instance_id`, `volume_size`),
      # #bindable? then drops the step for missing required inputs, and the
      # operator sees "nothing could be composed" for a lane that is wired
      # end-to-end. Stating the contract is the difference between a lane that
      # composes when its inputs exist and one that composes by luck.
      #
      # This does NOT relax #reject_unbindable. The guard stays the arbiter of
      # what persists; this only stops the composer from failing it for a
      # reason it was never told about. A model that still omits a required
      # input is still dropped.
      #
      # Resolved through SkillCompositionRunner's seam, so core names no
      # executor. In core mode nothing resolves and this returns an empty
      # string — the prompt degrades to exactly its previous form rather than
      # emitting an empty "contracts" heading.
      def skill_contracts_block
        contracts = ADAPTATION_SKILLS.filter_map do |skill|
          inputs = ::Ai::Provisioning::SkillCompositionRunner.input_contract_for(skill)
          next nil if inputs.blank?

          lines = inputs.map do |spec|
            flag = spec["required"] ? "REQUIRED" : "optional"
            desc = spec["description"].presence
            "    - #{spec['name']} (#{spec['type']}, #{flag})#{desc ? ": #{desc}" : ''}"
          end
          "  #{skill}:\n#{lines.join("\n")}"
        end
        return "" if contracts.empty?

        "Skill input contracts — a step MISSING a REQUIRED input is discarded,\n" \
        "so emit a step only when you can supply every REQUIRED input for it.\n" \
        "Draw values from the mission brief and signal payload below; do not\n" \
        "invent identifiers.\n#{contracts.join("\n")}\n"
      end

      def parse_diff_json(content)
        return nil unless content.is_a?(String)

        stripped = content.strip
        stripped = stripped.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "")
        first = stripped.index("[")
        last = stripped.rindex("]")
        return nil unless first && last && last > first

        parsed = JSON.parse(stripped[first..last])
        parsed.is_a?(Array) ? parsed : nil
      rescue JSON::ParserError => e
        Rails.logger.warn("[AdaptationProposerService] diff JSON parse failed: #{e.message}")
        nil
      end
    end
  end
end
