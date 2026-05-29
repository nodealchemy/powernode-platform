# frozen_string_literal: true

module Ai
  module Missions
    # LLM-driven composer that turns a high-level natural-language intent
    # (e.g. "stand up a 3-region federated platform with public ingress") into
    # an executable DAG — the novel-intent half of the hybrid mission
    # composition strategy. (The deterministic half is Ai::MissionTemplate +
    # Ai::Provisioning::PlanComposerService for known scenarios.)
    #
    # Reuse-first: rather than introduce a parallel plan model, the composer
    # emits the SAME shape SkillCompositionRunner already executes — an
    # Ai::GoalPlan of `provisioning_skill` Ai::GoalPlanSteps whose
    # execution_config carries { skill, inputs, depends_on_outputs, on_failure }.
    # That means the Phase-0 cross-step data-flow substrate, rollback, and the
    # plan_review approval gate (wired to the inline ApprovalCard) all apply
    # unchanged. The difference from PlanComposerService is generality: the
    # composer may sequence ANY agent-bound skill (federation, sdwan, ingress,
    # runtime, …), not just the provisioning allow-list.
    #
    # Guardrails (every one enforced before a plan is persisted):
    #   - cost cap   — CostCapGuard.allow? gates the (expensive) LLM call.
    #   - bound-skill — every emitted step must reference a skill that is in the
    #                   candidate set (i.e. active AND bound to an agent). The
    #                   LLM cannot invent skills.
    #   - acyclic    — the dependency graph is cycle-checked; a cyclic plan is
    #                  rejected outright.
    #   - bounded    — at most MAX_STEPS steps.
    #   - dry-run    — compose! only PERSISTS a draft plan; execution stays
    #                  behind the mission's plan_review gate (operator approval).
    class MissionComposer
      include ::Ai::LlmCallable

      class CompositionError < StandardError; end

      # Upper bounds. Candidate pool is capped so the prompt stays tractable;
      # step count is capped so a hallucinated mega-plan can't run away.
      MAX_CANDIDATES = 20
      MAX_STEPS = 15

      VALID_SELECTORS = %w[first last all].freeze

      attr_reader :account, :mission, :intent, :cap_exceeded_payload

      def initialize(account:, mission: nil, intent:)
        @account = account
        @mission = mission
        @intent = intent.to_s
      end

      # Compose and persist a draft GoalPlan from the intent.
      #
      # @return [Ai::GoalPlan, nil] the draft plan, or nil when the cost cap is
      #   exceeded (cap_exceeded_payload is set) or nothing composable surfaced.
      # @raise [CompositionError] on empty intent, no candidate skills, or a
      #   composition that fails validation (cycle / no valid steps).
      def compose!
        raise CompositionError, "intent is required" if @intent.strip.empty?

        guard = ::Ai::Provisioning::CostCapGuard.allow?(account: account)
        if guard.cap_exceeded?
          @cap_exceeded_payload = guard.payload
          Rails.logger.warn(
            "[MissionComposer] cost cap exceeded for account=#{account&.id} — skipping composition"
          )
          return nil
        end

        candidates = candidate_skills
        raise CompositionError, "no agent-bound skills available to compose" if candidates.empty?

        dag = decompose(candidates)
        return nil if dag.blank?

        steps = validate_and_normalize!(dag, candidates)
        raise CompositionError, "composition produced no valid steps" if steps.empty?

        persist_plan!(steps, candidates)
      end

      private

      # ===== Candidate pool =====
      #
      # Only ACTIVE skills BOUND to at least one agent are composable — a skill
      # no agent can run is not a valid DAG step. Each candidate is resolved to
      # its executor's I/O contract (descriptor inputs/outputs) so the LLM can
      # wire data flow and so we can validate the skill identifier the runner
      # will actually dispatch (the executor `name`, e.g. "provision_full_stack",
      # NOT the Ai::Skill slug). Skills without a resolvable executor (e.g. the
      # provision-infrastructure delegation entry) are dropped — they are not
      # DAG steps.
      #
      # NOTE: v1 uses a deterministic bound-skill pool capped at MAX_CANDIDATES;
      # the LLM performs intent→skill selection. Embedding-based pre-ranking
      # (à la ConciergeRouter#discover_relevant_skills) is a future refinement.
      def candidate_skills
        bound_ids = ::Ai::AgentSkill.where(is_active: true).distinct.pluck(:ai_skill_id)
        return [] if bound_ids.empty?

        ::Ai::Skill.where(id: bound_ids, status: "active", account_id: account.id)
                   .order(:name)
                   .filter_map { |skill| skill_contract(skill) }
                   .first(MAX_CANDIDATES)
      end

      def skill_contract(skill)
        klass = resolve_executor(skill)
        desc = klass.respond_to?(:descriptor) ? klass.descriptor : nil if klass
        return nil unless desc.is_a?(Hash) && desc[:name].present?

        {
          skill: desc[:name].to_s,
          slug: skill.slug,
          description: skill.description.to_s,
          inputs: stringify(desc[:inputs] || {}),
          outputs: stringify(desc[:outputs] || {})
        }
      end

      def resolve_executor(skill)
        name = skill.metadata.is_a?(Hash) ? skill.metadata["executor_class"].to_s : ""
        return nil if name.empty?

        name.constantize
      rescue NameError
        nil
      end

      # ===== LLM decomposition =====

      def decompose(candidates)
        agent = composer_agent
        raise CompositionError, "no text-capable agent available for composition" unless agent

        response = call_llm(
          agent: agent,
          prompt: build_prompt(candidates),
          max_tokens: 1800,
          temperature: 0.2
        )
        content = response&.dig(:content) || response&.dig("content")
        return nil if content.blank?

        parse_dag(content)
      rescue CompositionError
        raise
      rescue StandardError => e
        Rails.logger.warn("[MissionComposer] LLM decomposition failed: #{e.class}: #{e.message}")
        nil
      end

      def build_prompt(candidates)
        catalog = candidates.map do |c|
          "- #{c[:skill]}: #{c[:description]}\n    inputs: #{c[:inputs].keys.join(', ')}\n    outputs: #{output_keys(c[:outputs]).join(', ')}"
        end.join("\n")

        <<~PROMPT
          You are a platform mission composer. Decompose the operator's INTENT into an
          ordered DAG of skill invocations, choosing ONLY from the AVAILABLE SKILLS below.

          INTENT:
          #{@intent}

          AVAILABLE SKILLS (use the exact skill identifier on the left):
          #{catalog}

          Rules:
          - Use ONLY skills from the list above. Never invent a skill.
          - Order steps so prerequisites come first; express ordering via `dependencies`
            (a list of earlier step_numbers).
          - When a step needs a value PRODUCED by an earlier step, do NOT guess it —
            wire it via `depends_on_outputs`: { "<input_key>": { "from_step": N,
            "path": "<dot.path into that step's outputs>", "select": "first|last|all" } }.
          - Keep the plan minimal: no redundant steps. Max #{MAX_STEPS} steps.

          Respond with ONLY valid JSON, no prose:
          {
            "steps": [
              { "step_number": 1, "skill": "<id>", "inputs": { }, "dependencies": [],
                "depends_on_outputs": { } }
            ]
          }
        PROMPT
      end

      # Extract the first JSON object from the LLM content and return its
      # `steps` array (raw hashes). Tolerant of code fences / surrounding prose.
      def parse_dag(content)
        json = content[/\{.*\}/m]
        return nil if json.blank?

        parsed = JSON.parse(json)
        steps = parsed["steps"] || parsed[:steps]
        steps.is_a?(Array) ? steps : nil
      rescue JSON::ParserError => e
        Rails.logger.warn("[MissionComposer] could not parse DAG JSON: #{e.message}")
        nil
      end

      # ===== Validation / normalization =====
      #
      # Returns a normalized, ordered Array of step hashes ready to persist, or
      # raises CompositionError when the DAG is unsound (cycle). Steps that
      # reference an unknown (non-candidate) skill are DROPPED with a log line
      # rather than failing the whole composition — the LLM occasionally emits a
      # near-miss, and a partial valid plan beats none. Dependencies pointing at
      # dropped steps are pruned.
      def validate_and_normalize!(dag, candidates)
        allowed = candidates.map { |c| c[:skill] }.to_set

        kept = dag.first(MAX_STEPS).filter_map do |raw|
          skill = (raw["skill"] || raw[:skill]).to_s
          unless allowed.include?(skill)
            Rails.logger.info("[MissionComposer] dropping step with unknown skill #{skill.inspect}")
            next
          end
          {
            step_number: (raw["step_number"] || raw[:step_number]).to_i,
            skill: skill,
            inputs: stringify(raw["inputs"] || raw[:inputs] || {}),
            dependencies: Array(raw["dependencies"] || raw[:dependencies]).map(&:to_i),
            depends_on_outputs: normalize_depends_on_outputs(raw["depends_on_outputs"] || raw[:depends_on_outputs])
          }
        end

        kept = renumber(kept)
        raise CompositionError, "composed DAG has a dependency cycle" if cyclic?(kept)
        kept
      end

      # Renumber to a contiguous 1..N ordering (by the LLM's declared order) and
      # remap dependencies / depends_on_outputs.from_step accordingly. Drops
      # dependency references to steps that didn't survive validation.
      def renumber(steps)
        order = steps.map { |s| s[:step_number] }
        remap = order.each_with_index.to_h { |old, idx| [old, idx + 1] }

        steps.each_with_index.map do |s, idx|
          new_deps = s[:dependencies].filter_map { |d| remap[d] }.uniq
          new_dofo = s[:depends_on_outputs].each_with_object({}) do |(k, spec), acc|
            from = remap[spec["from_step"]]
            next unless from
            acc[k] = spec.merge("from_step" => from)
          end
          s.merge(step_number: idx + 1, dependencies: new_deps.reject { |d| d == idx + 1 }, depends_on_outputs: new_dofo)
        end
      end

      def normalize_depends_on_outputs(raw)
        return {} unless raw.is_a?(Hash)

        raw.each_with_object({}) do |(input_key, spec), acc|
          spec = spec.is_a?(Hash) ? spec : {}
          from = (spec["from_step"] || spec[:from_step])
          next if from.nil?

          selector = (spec["select"] || spec[:select] || "all").to_s
          selector = "all" unless VALID_SELECTORS.include?(selector) || selector.match?(/\A-?\d+\z/)
          acc[input_key.to_s] = {
            "from_step" => from.to_i,
            "path" => (spec["path"] || spec[:path] || input_key).to_s,
            "select" => selector
          }
        end
      end

      # Kahn/DFS cycle detection over step_number → dependencies.
      def cyclic?(steps)
        adjacency = steps.to_h { |s| [s[:step_number], s[:dependencies]] }
        visiting = {}
        visited = {}
        walk = lambda do |node|
          return false if visited[node]
          return true if visiting[node]

          visiting[node] = true
          Array(adjacency[node]).each { |dep| return true if walk.call(dep) }
          visiting[node] = false
          visited[node] = true
          false
        end
        adjacency.keys.any? { |node| walk.call(node) }
      end

      # ===== Persistence =====

      def persist_plan!(steps, candidates)
        agent = composer_agent
        goal = create_goal!(agent)
        version = (::Ai::GoalPlan.for_goal(goal.id).maximum(:version) || 0) + 1

        plan = ::Ai::GoalPlan.create!(
          account: account,
          goal: goal,
          agent: agent,
          status: "draft",
          version: version,
          plan_data: {
            "composed_by" => "mission_composer",
            "intent" => @intent,
            "mission_id" => mission&.id,
            "candidate_skills" => candidates.map { |c| c[:skill] }
          }
        )

        steps.each do |s|
          plan.steps.create!(
            step_number: s[:step_number],
            step_type: "provisioning_skill",
            description: "#{s[:skill]} (composed)",
            dependencies: s[:dependencies],
            execution_config: {
              "skill" => s[:skill],
              "inputs" => s[:inputs],
              "depends_on_outputs" => s[:depends_on_outputs],
              "on_failure" => "rollback"
            }
          )
        end

        link_plan_to_mission!(plan)
        Rails.logger.info("[MissionComposer] composed plan #{plan.id} with #{steps.size} step(s) for intent")
        plan
      end

      def create_goal!(agent)
        ::Ai::AgentGoal.create!(
          account: account,
          agent: agent,
          title: "Composed mission: #{@intent.to_s[0, 80]}",
          description: @intent,
          goal_type: "creation",
          status: "pending",
          priority: 3,
          progress: 0.0,
          success_criteria: { "intent" => @intent, "mission_id" => mission&.id },
          metadata: { "composed_by" => "mission_composer", "mission_id" => mission&.id }
        )
      end

      # Stamp the plan id onto the mission so the existing execute path
      # (AiProvisioningExecuteJob → SkillCompositionRunner) resolves the same
      # plan once the operator approves the plan_review gate.
      def link_plan_to_mission!(plan)
        return unless mission.respond_to?(:configuration) && mission.respond_to?(:update_columns)

        cfg = mission.configuration.is_a?(Hash) ? mission.configuration.deep_dup : {}
        cfg["plan"] ||= {}
        cfg["plan"]["plan_id"] = plan.id
        mission.update_columns(configuration: cfg)
      rescue StandardError => e
        Rails.logger.warn("[MissionComposer] failed to link plan to mission: #{e.message}")
      end

      def composer_agent
        @composer_agent ||= begin
          text_types = %w[assistant code_assistant data_analyst monitor mcp_client]
          account.ai_agents.where(status: "active", agent_type: text_types).first ||
            account.ai_agents.where(agent_type: text_types).first ||
            account.ai_agents.first
        end
      end

      def output_keys(outputs)
        return [] unless outputs.is_a?(Hash)
        # Surface nested ids (e.g. outputs.node_instance_ids) so the LLM can
        # wire dot-paths, plus top-level keys.
        nested = outputs["outputs"] || outputs[:outputs]
        keys = outputs.keys.map(&:to_s)
        keys += nested.keys.map { |k| "outputs.#{k}" } if nested.is_a?(Hash)
        keys
      end

      def stringify(hash)
        return {} unless hash.is_a?(Hash)
        hash.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      end
    end
  end
end
