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
    # The plan is then routed through `Ai::Autonomy::ApprovalWorkflowService`
    # with an `action_type: "project.adapt_<change_type>"` so the operator
    # policy resolver can choose between auto-apply (low-blast) and
    # require-approval (high-blast).
    #
    # The plan returned by `propose_from_signals` is a *diff plan*: only
    # the steps that change. The Skill Composition Runner appends them
    # onto the live mission's existing plan rather than replacing it.
    #
    # LLM access is funneled through `#diff_from_llm` so test specs can
    # inject a fixture proposal without exercising provider plumbing —
    # mirrors the seam in `IntentCaptureService` from the M0 sprint.
    class AdaptationProposerService
      class MissionMissingError < StandardError; end

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

      DEFAULT_SKILL_FOR_CHANGE = {
        "scale_horizontal" => "scale_project",
        "cost_control" => "scale_project",
        "relocate" => "relocate_workload",
        "schema_change" => "attach_storage",
        "security_change" => "configure_sdwan_for_project"
      }.freeze

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
        change_type = derive_change_type(primary)
        diff_steps = build_steps_for(primary, change_type)
        return nil if diff_steps.blank?

        plan = persist_diff_plan!(change_type, diff_steps, primary)
        request_approval_for!(plan, change_type, primary) if plan
        plan
      rescue StandardError => e
        Rails.logger.warn("[AdaptationProposerService] propose failed mission=#{mission.id}: #{e.class}: #{e.message}")
        nil
      end

      # Auto-apply heuristic. Replica scale within
      # `mission.configuration.watch_policies.auto_scale_max_replicas`
      # is auto-applied via the `notify_and_proceed` policy. Cross-region
      # / schema / security plans are always require_approval.
      def auto_apply?(plan:)
        return false unless plan

        replica_steps = plan.steps.select do |s|
          cfg = step_config(s)
          cfg["skill"].to_s == "scale_project" &&
            cfg.dig("inputs", "change_type").to_s == "scale_horizontal"
        end
        return false if replica_steps.empty?

        max_replicas = watch_policies.dig("auto_scale_max_replicas")&.to_i
        return false if max_replicas.nil? || max_replicas <= 0

        replica_steps.all? do |s|
          desired = step_config(s).dig("inputs", "desired_replica_count").to_i
          desired.positive? && desired <= max_replicas
        end
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

      def build_llm_client
        return nil unless defined?(::WorkerLlmClient)
        ::WorkerLlmClient.for_account(account)
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

      def build_steps_for(signal, change_type)
        # Try the LLM first; fall back to the heuristic when it returns nothing.
        from_llm = safe_call { diff_from_llm(signal: signal, change_type: change_type) }
        sanitized = sanitize_steps(from_llm)
        if sanitized.any?
          decorate_with_signal_metadata!(sanitized, signal)
          return sanitized
        end

        heuristic_steps(signal, change_type)
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
          inputs["desired_replica_count"] = recommended_replica_count(payload)
        when "cost_control"
          inputs["target_cost_usd"] = payload["target_usd"]
          inputs["desired_replica_count"] = downscale_replica_count
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

      def recommended_replica_count(payload)
        # SLO violation → scale up. Use breach_pct to pick a step.
        breach = payload["breach_pct"].to_f
        current = brief_initial_replicas
        return nil unless current.positive?

        delta = if breach >= 50.0 then 2
        elsif breach >= 25.0 then 1
        else 1
        end

        current + delta
      end

      def downscale_replica_count
        current = brief_initial_replicas
        return nil unless current >= 2
        current - 1
      end

      def brief_initial_replicas
        brief.dig("scale", "initial").to_i
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
            "signal_payload" => signal_payload(signal),
            "mission_id" => mission.id
          }
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
          desired = step_attrs.dig("inputs", "desired_replica_count")
          "Scale project (#{change_type})#{desired ? " → #{desired} replicas" : ''}"
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

      # ----- approval routing --------------------------------------------

      def request_approval_for!(plan, change_type, signal)
        return nil unless defined?(::Ai::Autonomy::ApprovalWorkflowService)
        return nil unless defined?(::Ai::ApprovalRequest)

        agent = plan.agent
        return nil unless agent

        action_type = "project.adapt_#{change_type}"
        description = "Adaptation: #{action_type} for mission #{mission.name}"

        service = ::Ai::Autonomy::ApprovalWorkflowService.new(account: account)
        service.request_approval(
          agent: agent,
          action_type: action_type,
          description: description,
          request_data: {
            "mission_id" => mission.id,
            "plan_id" => plan.id,
            "change_type" => change_type,
            "signal_kind" => signal_kind(signal),
            "signal_payload" => signal_payload(signal),
            "auto_apply" => auto_apply?(plan: plan)
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[AdaptationProposerService] approval request failed: #{e.message}")
        nil
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

          Mission brief:
          #{JSON.dump(brief)}

          SLO targets:
          #{JSON.dump(slo)}

          Signal payload:
          #{JSON.dump(payload)}

          Recommended change_type: #{change_type}
        PROMPT
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
