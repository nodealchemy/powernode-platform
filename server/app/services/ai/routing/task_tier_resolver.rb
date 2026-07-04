# frozen_string_literal: true

module Ai
  module Routing
    # Governed per-task model-TIER router (campaign 019f2163 inc2).
    #
    # ONE complexity classification per task (TaskComplexityClassifierService
    # #classify_preview — no DB write during resolve) feeds BOTH a target tier and
    # the reasoning effort, wrapped in a machine-auditable rationale. Wired into
    # both execution seams (Ai::Ralph::TaskExecutor#build_agent_options and
    # Ai::McpAgentExecutor::ProviderExecution#resolve_model_config) BEHIND the
    # account gate `ai_task_tier_routing_enabled` (default OFF ⇒ byte-identical to
    # pre-inc2 behavior; the seams do not even call the resolver while OFF).
    #
    # ─────────────────────────── Tier policy ───────────────────────────────────
    # complexity level → INDICATED ladder tier (Ai::ModelTiers):
    #   trivial / simple → :light   moderate → :standard
    #   complex → :reasoning        expert  → :frontier
    #
    # From the agent's BASELINE tier (Ai::ModelTiers.classify of its resolved
    # model) the resolver either holds, escalates, or downgrades:
    #
    #   * EFFORT-FIRST BEFORE TIER-JUMP. A one-rung jump to :reasoning is the place
    #     we most want to avoid paying for a bigger model when a cheaper lever
    #     exists. So when :reasoning is indicated over a lower baseline whose model
    #     is effort-capable (Ai::Llm::ModelCapabilities.supports_effort?), the
    #     resolver PREFERS holding the baseline tier and raising reasoning effort —
    #     UNLESS the complexity score clears ESCALATE_OVER_EFFORT_SCORE. When it DOES
    #     escalate, the rationale states why effort-substitution was rejected (score
    #     over threshold, or a non-effort-capable baseline model). expert→:frontier
    #     is never effort-substituted (a frontier task wants a frontier model).
    #
    #   * FRONTIER requires ALL of: the Fable gate ON (Ai::FableRouting.enabled_for?,
    #     OFF today ⇒ expert falls back to :reasoning), an allowlisted agent_type
    #     (AgentModelSelector.fable_preferred_agent_type?), expert complexity OR an
    #     explicit operator tier pin, budget headroom (…fable_budget_exhausted?),
    #     no active refusal pre-route (…fable_preroute_suppressed?), AND a recorded
    #     rationale. Any missing condition caps to :reasoning.
    #
    #   * MANDATORY RATIONALE (fail-closed). Any tier above :standard OR above the
    #     baseline tier requires a non-empty rationale; if the escalation
    #     justification is empty the resolver fails closed to the cheaper (baseline)
    #     tier. Downgrades also record a (cheap) rationale.
    #
    #   * PINS. A model pin (agent mcp_metadata.model_config.model, honored by
    #     Ai::Agent#resolved_model) is the articulable reason: the tier is fixed at
    #     baseline, no re-selection, no downgrade. Downgrade/escalation re-selection
    #     applies ONLY to selector-chosen models.
    #
    # The concrete model for a non-baseline tier is re-selected via
    # AgentModelSelector.recommend(requirements: { tier: target }) — the same
    # mechanism the seams would call, centralized here so effort is computed against
    # the FINAL model in one place and the seam becomes a thin consumer of
    # `resolution.model` / `resolution.effort`.
    class TaskTierResolver
      POLICY_VERSION = "1.0.0"
      GATE_SETTING = "ai_task_tier_routing_enabled"
      DEFAULT_TASK_TYPE = "agent_task"

      # complexity level → indicated ladder tier.
      LEVEL_TO_TIER = {
        "trivial"  => :light,
        "simple"   => :light,
        "moderate" => :standard,
        "complex"  => :reasoning,
        "expert"   => :frontier
      }.freeze

      # A "complex" task escalates the model TIER only when its score clears this
      # bar; below it we prefer holding baseline and raising reasoning effort.
      ESCALATE_OVER_EFFORT_SCORE = 0.60

      DECISION_LABELS = {
        escalate: "escalate", downgrade: "downgrade", baseline: "baseline",
        pinned: "pinned", effort_first_hold: "effort_first_hold", fail_closed: "baseline"
      }.freeze

      STRATEGY_BY_KIND = {
        escalate: "quality_optimized", downgrade: "cost_optimized", baseline: "hybrid",
        pinned: "hybrid", effort_first_hold: "hybrid", fail_closed: "hybrid"
      }.freeze

      # Immutable result of one resolution. Carries the seam-facing values
      # (tier/model/effort/rationale) plus everything #persist! needs to write the
      # durable governance record — so persistence is decoupled from resolution and
      # never runs on the gate-OFF path.
      class Resolution
        attr_reader :tier, :model, :effort, :rationale, :baseline_tier, :baseline_model, :kind

        def initialize(tier:, model:, effort:, rationale:, baseline_tier:, baseline_model:, kind:,
                       account:, agent:, request_type:, assessment_attributes:, preroute_rule: nil)
          @tier = tier
          @model = model
          @effort = effort
          @rationale = rationale
          @baseline_tier = baseline_tier
          @baseline_model = baseline_model
          @kind = kind
          @account = account
          @agent = agent
          @request_type = request_type
          @assessment_attributes = assessment_attributes
          @preroute_rule = preroute_rule
        end

        def escalated? = @kind == :escalate
        def downgraded? = @kind == :downgrade

        # Persist ONE Ai::TaskComplexityAssessment (from the already-computed
        # classification — no re-classify) and ONE Ai::RoutingDecision carrying the
        # rationale, linked bidirectionally. Best-effort: a persistence failure must
        # never break the calling execution path.
        def persist!(agent_execution: nil)
          ActiveRecord::Base.transaction do
            assessment = ::Ai::TaskComplexityAssessment.create!(@assessment_attributes)
            decision = ::Ai::RoutingDecision.create!(
              account: @account,
              request_type: @request_type,
              strategy_used: STRATEGY_BY_KIND[@kind] || "hybrid",
              model_tier: @tier.to_s,
              decision_reason: @rationale[:summary].to_s[0, 500],
              rationale: @rationale.deep_stringify_keys,
              complexity_assessment: assessment,
              agent_execution: agent_execution,
              routing_rule: @preroute_rule,
              request_metadata: {
                "agent_id" => @agent&.id,
                "agent_type" => @agent&.agent_type,
                "effort" => @effort,
                "policy_version" => POLICY_VERSION
              }.compact
            )
            assessment.update!(routing_decision_id: decision.id,
                               actual_tier_used: ::Ai::ModelTiers.to_label(@tier))
            decision
          end
        rescue StandardError => e
          Rails.logger.error("[TaskTierResolver] persist failed: #{e.class}: #{e.message}")
          nil
        end
      end

      # Account gate — Account#settings → SiteSetting fallback → false. Mirrors
      # Ai::FableRouting.enabled_for? (reuses its settings reader + truthy coercion).
      def self.enabled_for?(account)
        val = ::Ai::FableRouting.setting(account, GATE_SETTING)
        return ::Ai::FableRouting.truthy?(val) unless val.nil?

        global = ::Ai::FableRouting.global_setting(GATE_SETTING)
        return ::Ai::FableRouting.truthy?(global) unless global.nil?

        false
      rescue StandardError
        false
      end

      def self.resolve(account:, agent:, task_type: nil, messages: [], tools: [], pinned_effort: nil, operator_tier_pin: nil)
        new(account: account, agent: agent, task_type: task_type, messages: messages,
            tools: tools, pinned_effort: pinned_effort, operator_tier_pin: operator_tier_pin).resolve
      end

      def initialize(account:, agent:, task_type: nil, messages: [], tools: [], pinned_effort: nil, operator_tier_pin: nil)
        @account = account
        @agent = agent
        @task_type = task_type
        @messages = Array(messages)
        @tools = Array(tools)
        @pinned_effort = pinned_effort
        @operator_tier_pin = operator_tier_pin
      end

      def resolve
        classification = classify
        level = classification[:complexity_level].to_s
        score = classification[:complexity_score].to_f

        baseline_model = @agent.resolved_model.to_s
        baseline_tier  = ::Ai::ModelTiers.classify(baseline_model)

        decision = decide(level: level, score: score, baseline_model: baseline_model, baseline_tier: baseline_tier)

        final_model = resolve_model(decision[:tier], baseline_tier, baseline_model)
        effort = ::Ai::Routing::EffortMapper.effort_for_level(
          model: final_model, complexity_level: level, pinned_effort: @pinned_effort
        )

        rationale = build_rationale(
          classification: classification, level: level, score: score,
          baseline_tier: baseline_tier, baseline_model: baseline_model,
          decision: decision, effort: effort, final_model: final_model
        )

        Resolution.new(
          tier: decision[:tier], model: final_model, effort: effort, rationale: rationale,
          baseline_tier: baseline_tier, baseline_model: baseline_model, kind: decision[:kind],
          account: @account, agent: @agent, request_type: (@task_type.presence || DEFAULT_TASK_TYPE),
          assessment_attributes: assessment_attributes(classification: classification, level: level, score: score),
          # Set only when frontier_or_cap actually capped BECAUSE of this rule
          # (see the preroute branch in #frontier_or_cap) — never derived merely
          # from "a matching rule exists," which would misattribute feedback.
          preroute_rule: @matched_preroute_rule
        )
      end

      private

      # ONE classification per task — memoized preview, no DB write.
      def classify
        @classification ||= ::Ai::Routing::TaskComplexityClassifierService
                            .new(account: @account)
                            .classify_preview(
                              task_type: (@task_type.presence || DEFAULT_TASK_TYPE),
                              messages: @messages, tools: @tools
                            )
      end

      # Returns { tier:, kind:, evidence: [..], effort_first: {}, frontier_considered: bool }.
      def decide(level:, score:, baseline_model:, baseline_tier:)
        if @messages.empty?
          return hold(baseline_tier, "no task signal (messages empty); held baseline #{baseline_tier}")
        end

        if model_pinned?(baseline_model)
          return { tier: baseline_tier, kind: :pinned, frontier_considered: false, effort_first: { considered: false },
                   evidence: [ "model pinned to #{baseline_model}; tier fixed at baseline #{baseline_tier}" ] }
        end

        indicated = indicated_tier(level)
        order = ::Ai::ModelTiers::ORDER
        ind_i = order.index(indicated)
        base_i = order.index(baseline_tier)

        if ind_i > base_i
          decide_escalation(level: level, score: score, indicated: indicated,
                            baseline_tier: baseline_tier, baseline_model: baseline_model)
        elsif ind_i < base_i
          { tier: indicated, kind: :downgrade, frontier_considered: false, effort_first: { considered: false },
            evidence: [ "complexity #{level} (score #{score.round(3)}) below baseline tier #{baseline_tier}; downgrade to #{indicated} for cost efficiency" ] }
        else
          hold(baseline_tier, "complexity #{level} (score #{score.round(3)}) matches baseline tier #{baseline_tier}")
        end
      end

      def hold(baseline_tier, reason)
        { tier: baseline_tier, kind: :baseline, frontier_considered: false,
          effort_first: { considered: false }, evidence: [ reason ] }
      end

      def decide_escalation(level:, score:, indicated:, baseline_tier:, baseline_model:)
        evidence = []
        effort_first = { considered: false }
        frontier_considered = (indicated == :frontier)
        target = indicated

        target = frontier_or_cap(level: level, evidence: evidence) if frontier_considered

        order = ::Ai::ModelTiers::ORDER
        if order.index(target) <= order.index(baseline_tier)
          evidence << "no tier escalation above baseline #{baseline_tier} after gating"
          return { tier: baseline_tier, kind: :baseline, frontier_considered: frontier_considered,
                   effort_first: effort_first, evidence: evidence }
        end

        if target == :reasoning
          baseline_capable = ::Ai::Llm::ModelCapabilities.supports_effort?(baseline_model)
          effort_first = { considered: true, baseline_supports_effort: baseline_capable }

          if baseline_capable && score < ESCALATE_OVER_EFFORT_SCORE
            effort_first[:chosen] = "effort_bump"
            effort_first[:reason] = "score #{score.round(3)} < effort-first threshold #{ESCALATE_OVER_EFFORT_SCORE}; hold #{baseline_tier} and raise reasoning effort"
            evidence << effort_first[:reason]
            return { tier: baseline_tier, kind: :effort_first_hold, frontier_considered: frontier_considered,
                     effort_first: effort_first, evidence: evidence }
          end

          effort_first[:chosen] = "tier_escalation"
          effort_first[:reason] = if baseline_capable
                                    "score #{score.round(3)} ≥ effort-first threshold #{ESCALATE_OVER_EFFORT_SCORE}"
                                  else
                                    "baseline model #{baseline_model} is not effort-capable — cannot raise effort in place"
                                  end
          evidence << effort_first[:reason]
        end

        # Mandatory-rationale gate: an escalation above standard/baseline must be
        # justified, else fail closed to the cheaper (baseline) tier.
        justification = escalation_justification(target: target, baseline_tier: baseline_tier, level: level, score: score)
        if justification.blank?
          evidence << "escalation to #{target} lacked a rationale; failing closed to baseline #{baseline_tier}"
          return { tier: baseline_tier, kind: :fail_closed, frontier_considered: frontier_considered,
                   effort_first: effort_first, evidence: evidence }
        end
        evidence.concat(justification)

        { tier: target, kind: :escalate, frontier_considered: frontier_considered,
          effort_first: effort_first, evidence: evidence }
      end

      # Capability/empirical justification lines for an escalation (the non-empty
      # rationale the fail-closed rule requires). Isolated so it is independently
      # testable and so future increments can fold in empirical evidence.
      def escalation_justification(target:, baseline_tier:, level:, score:)
        [
          "escalate #{baseline_tier} → #{target}: #{level} complexity (score #{score.round(3)}) exceeds baseline capability",
          "target tier #{target} provides higher reasoning capability for #{level} tasks"
        ]
      end

      # Full frontier gate; returns :frontier when admitted, else :reasoning (with a
      # capping reason appended to evidence).
      def frontier_or_cap(level:, evidence:)
        unless fable_gate_enabled?
          evidence << "frontier requires fable_routing_enabled=true (currently OFF); capping to reasoning"
          return :reasoning
        end
        unless frontier_allowlisted?
          evidence << "frontier requires an allowlisted agent_type (#{@agent.agent_type} not allowlisted); capping to reasoning"
          return :reasoning
        end
        unless level == "expert" || operator_frontier_pin?
          evidence << "frontier requires expert complexity or an operator pin (level=#{level}); capping to reasoning"
          return :reasoning
        end
        if frontier_budget_exhausted?
          evidence << "frontier suppressed: account budget ≥90% consumed; capping to reasoning"
          return :reasoning
        end
        if frontier_preroute_rule
          # Only recorded here, where the rule is the ACTUAL reason for the cap —
          # not derived later from "a matching rule exists somewhere," which would
          # misattribute record_match! feedback to a rule that had no bearing on
          # this decision (e.g. one from before the Fable gate was turned off).
          @matched_preroute_rule = frontier_preroute_rule
          evidence << "frontier suppressed: active fable-refusal pre-route rule for #{@agent.agent_type}; capping to reasoning"
          return :reasoning
        end
        evidence << "frontier admitted: gate ON, #{@agent.agent_type} allowlisted, #{level} complexity, budget OK, no refusal pre-route"
        :frontier
      end

      def resolve_model(target_tier, baseline_tier, baseline_model)
        return baseline_model if target_tier == baseline_tier
        return baseline_model if model_pinned?(baseline_model)

        rec = ::Ai::AgentModelSelector.recommend(
          account: @account, agent_type: @agent.agent_type, requirements: { tier: target_tier }
        )
        (rec && rec[:model].presence) || baseline_model
      rescue StandardError => e
        Rails.logger.warn("[TaskTierResolver] re-selection failed for tier #{target_tier}: #{e.class}: #{e.message}")
        baseline_model
      end

      def indicated_tier(level)
        operator_pin_tier || LEVEL_TO_TIER[level] || :standard
      end

      # An operator-supplied tier pin (symbol/ladder name or economy/standard/premium
      # label). :frontier is reachable only via an explicit :frontier/"frontier"
      # value (the label vocabulary tops out at "premium" ⇒ :reasoning).
      def operator_pin_tier
        return nil if @operator_tier_pin.blank?

        sym = @operator_tier_pin.to_s.strip.downcase.to_sym
        return sym if ::Ai::ModelTiers::ORDER.include?(sym)

        ::Ai::ModelTiers.from_label(@operator_tier_pin.to_s)
      end

      def operator_frontier_pin?
        operator_pin_tier == :frontier
      end

      def model_pinned?(baseline_model)
        pin = @agent.mcp_metadata&.dig("model_config", "model").presence
        return false if pin.nil?

        # A pin that did not survive Ai::Agent#compute_model_resolution (e.g. a Fable
        # pin while the framework is off) won't equal the resolved model ⇒ unpinned.
        pin == baseline_model
      end

      def build_rationale(classification:, level:, score:, baseline_tier:, baseline_model:, decision:, effort:, final_model:)
        {
          decision: DECISION_LABELS[decision[:kind]] || "baseline",
          summary: "#{DECISION_LABELS[decision[:kind]]} #{baseline_tier}→#{decision[:tier]} (#{level} #{score.round(3)})",
          target_tier: decision[:tier].to_s,
          baseline_tier: baseline_tier.to_s,
          baseline_model: baseline_model,
          delivered_model: final_model,
          effort: effort,
          complexity: {
            level: level,
            score: score.round(4),
            task_type: (@task_type.presence || DEFAULT_TASK_TYPE),
            task_type_baseline: classification.dig(:signals, :task_type_baseline),
            top_signals: top_signals(classification[:signals])
          },
          gates: gate_states(frontier_considered: decision[:frontier_considered]),
          effort_first: decision[:effort_first],
          evidence: Array(decision[:evidence]),
          policy_version: POLICY_VERSION
        }
      end

      # Cheap gates (settings reads) always recorded; the pricier budget SUM and
      # pre-route scan only when frontier was actually considered.
      def gate_states(frontier_considered:)
        gates = {
          fable_routing_enabled: fable_gate_enabled?,
          agent_type_allowlisted: frontier_allowlisted?
        }
        if frontier_considered
          gates[:budget_headroom] = !frontier_budget_exhausted?
          gates[:refusal_preroute_clear] = !frontier_preroute_suppressed?
        end
        gates
      end

      def top_signals(signals)
        return [] unless signals.is_a?(Hash)

        signals.except(:raw, "raw")
               .select { |_k, v| v.is_a?(Numeric) }
               .sort_by { |_k, v| -v.to_f }
               .first(3)
               .map { |k, v| { signal: k.to_s, value: v.to_f.round(3) } }
      end

      def assessment_attributes(classification:, level:, score:)
        signals = classification[:signals] || {}
        raw = signals[:raw] || signals["raw"] || {}
        {
          account: @account,
          task_type: (@task_type.presence || DEFAULT_TASK_TYPE),
          input_token_count: (raw[:token_count] || raw["token_count"] || 0),
          tool_count: @tools.length,
          conversation_depth: @messages.length,
          complexity_signals: signals.except(:raw, "raw").merge(raw_summary: raw),
          complexity_score: score,
          complexity_level: level,
          recommended_tier: classification[:recommended_tier],
          classifier_version: classification[:classifier_version] || "unknown"
        }
      end

      # ---- gate helpers (memoized; reuse AgentModelSelector's shared checks) ----

      def fable_gate_enabled?
        return @fable_gate_enabled if defined?(@fable_gate_enabled)

        @fable_gate_enabled = ::Ai::FableRouting.enabled_for?(@account)
      end

      def frontier_allowlisted?
        return @frontier_allowlisted if defined?(@frontier_allowlisted)

        @frontier_allowlisted = ::Ai::AgentModelSelector.fable_preferred_agent_type?(
          account: @account, agent_type: @agent.agent_type
        )
      end

      def frontier_budget_exhausted?
        return @frontier_budget_exhausted if defined?(@frontier_budget_exhausted)

        @frontier_budget_exhausted = ::Ai::AgentModelSelector.fable_budget_exhausted?(@account)
      end

      def frontier_preroute_suppressed?
        frontier_preroute_rule.present?
      end

      # Memoized so the boolean check above and the Resolution#persist! linkage
      # (see #resolve) share the one query instead of running it twice.
      def frontier_preroute_rule
        return @frontier_preroute_rule if defined?(@frontier_preroute_rule)

        @frontier_preroute_rule = ::Ai::AgentModelSelector.matching_fable_preroute_rule(
          account: @account, agent_type: @agent.agent_type
        )
      end
    end
  end
end
