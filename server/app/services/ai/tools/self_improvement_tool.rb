# frozen_string_literal: true

module Ai
  module Tools
    class SelfImprovementTool < BaseTool
      # SECURITY (IMP-6fbfeff384fa): authorization here is per ACTION, not per
      # tool. REQUIRED_PERMISSION was inherited as nil from BaseTool, and
      # McpPlatformToolRegistrar#enforce_permission! opens with
      # `return if required.nil?` — ABOVE the authentication raise and the
      # has_permission? raise. Every action was
      # therefore reachable by any MCP caller with no check at all, including
      # mutate_skill and compose_skills, which write Ai::Skill records.
      #
      # This tool bundles two unrelated surfaces whose REST twins are gated
      # differently — self-challenges on the coarse ai.manage, skill writes on
      # the ai.skills.* family — so no single constant expresses parity. The
      # floor is ai.skills.read: every legitimate caller of EITHER surface holds
      # it (granted to member upward, permissions.rb:738; every role granted
      # ai.skills.update/create or ai.manage also carries it), so it is the
      # least-privileged thing the registrar can demand before the action is
      # known. Unusually, NO action sits at the floor — each one raises above it.
      REQUIRED_PERMISSION = "ai.skills.read"

      # Each entry names the permission the REST twin of that action requires.
      ACTION_PERMISSIONS = {
        # Api::V1::Ai::AgentIntelligenceController#validate_permissions is
        # blanket ai.manage (agent_intelligence_controller.rb:7,76-81), and
        # #self_challenges is the twin of list_challenges. get_challenge_result
        # returns rows from that same list, and generate_self_challenge WRITES
        # one — the whole Ai::SelfChallenge surface is gated as a family, and
        # ai.manage is the only permission any human surface asks for it.
        "generate_self_challenge" => "ai.manage",
        "list_challenges" => "ai.manage",
        "get_challenge_result" => "ai.manage",

        # The skill writes. Their operational twins
        # (Api::V1::Internal::Ai::SkillsController#mutate / #auto_evolve) are
        # mTLS worker endpoints carrying no permission string, so the binding
        # twin is the human surface that performs the same MUTATION:
        # Api::V1::Ai::SkillsController#update requires ai.skills.update, and
        # #create requires ai.skills.create. compose_skills CREATES a new
        # composite Ai::Skill; the other two mutate existing ones.
        "mutate_skill" => "ai.skills.update",
        "auto_evolve_skill" => "ai.skills.update",
        "compose_skills" => "ai.skills.create"
      }.freeze

      # Advertisement is deliberately NOT overridden (unlike AgentAutonomyTool,
      # whose escalate/report_issue are an agent's only route to a human). The
      # floor is a member-tier permission, so BaseTool.permitted? re-arming
      # narrows advertisement only in an account where NO user can read skills.

      # HIER-P2B-ENG — the two REFINE verbs gate on the engineering policy
      # set's trust-conditioned categories (operator ruling 2026-09-03 #3:
      # skill and prompt refinements auto-approve on trusted agents, require
      # approval below). mutate_skill rewrites ONE skill's prompt under a
      # strategy — dev.prompt_refine; auto_evolve_skill sweeps every
      # underperforming skill — dev.skill_refine. The verdict is the row pair
      # db/seeds/ai_engineering_agents_seed.rb writes on the Platform
      # Developer and the Platform Architect (auto_approve conditioned on
      # trust_tier_minimum "trusted" above an unconditioned require_approval),
      # so the SAME declaration parks a supervised agent and proceeds for a
      # trusted one — nothing new in the gate. A caller with no matching row
      # meets the unmatched default and parks. The generic replay executor
      # re-invokes the action as the ORIGINAL principal on approval, so the
      # action body stays the single author of the write, and each gate
      # context resolves the target under the account BEFORE parking so an
      # unknown or foreign skill keeps its inline error.
      REFINE_PROMPT_CATEGORY = "dev.prompt_refine"
      REFINE_SKILL_CATEGORY  = "dev.skill_refine"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. The `mutating:`-only ones are NON-ENFORCING:
      # BaseTool#gated_action? is false for them, so #execute still routes to
      # #call and behaviour is unchanged. The two refine verbs carry the full
      # quartet (HIER-P2B-ENG, above).
      declare_action "auto_evolve_skill",
                     mutating: true,
                     action_category: REFINE_SKILL_CATEGORY,
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :auto_evolve_skill_gate_context,
                     on_proceed: :deferred_tool_call_result
      declare_action "compose_skills", mutating: true
      declare_action "generate_self_challenge", mutating: true
      declare_action "get_challenge_result", mutating: false
      declare_action "list_challenges", mutating: false
      declare_action "mutate_skill",
                     mutating: true,
                     action_category: REFINE_PROMPT_CATEGORY,
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :mutate_skill_gate_context,
                     on_proceed: :deferred_tool_call_result

      def self.definition
        { name: "self_improvement", description: "Self-challenge generation, skill mutation, and skill composition", parameters: { type: "object", properties: {} } }
      end

      def self.action_definitions
        {
          "generate_self_challenge" => {
            description: "Generate a self-challenge for an agent to practice and improve",
            parameters: {
              skill_id: { type: "string", required: false, description: "Skill to challenge (optional)" },
              difficulty: { type: "string", required: false, description: "Difficulty level: easy, medium, hard, expert" }
            }
          },
          "list_challenges" => {
            description: "List self-challenges for the current agent",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status" },
              limit: { type: "integer", required: false, description: "Max results (default 20)" }
            }
          },
          "get_challenge_result" => {
            description: "Get detailed result for a specific self-challenge",
            parameters: {
              challenge_id: { type: "string", required: true, description: "Challenge ID" }
            }
          },
          "mutate_skill" => {
            description: "Mutate a skill using a specified strategy to improve it — rewrites that ONE skill's prompt as a new version. APPROVAL-GATED (dev.prompt_refine): when policy requires approval this returns {pending: true} with a deferred_operation_id and NOTHING is mutated until an operator approves — do not retry and do not report the mutation as done on that response. The seeded Platform Developer / Platform Architect rows auto-approve only from the `trusted` trust tier and require approval below it; a caller with no matching row meets the unmatched default and parks.",
            parameters: {
              skill_id: { type: "string", required: true, description: "Skill ID to mutate" },
              strategy: { type: "string", required: true, description: "Mutation strategy: learning_driven, failure_analysis, challenge_derived, peer_comparison" }
            }
          },
          "compose_skills" => {
            description: "Create a composite skill from multiple component skills",
            parameters: {
              component_skill_ids: { type: "array", required: true, description: "Array of skill IDs to compose" },
              name: { type: "string", required: true, description: "Name for the composite skill" },
              strategy: { type: "string", required: false, description: "Composition strategy: sequential, parallel, conditional" }
            }
          },
          "auto_evolve_skill" => {
            description: "Automatically find and mutate underperforming skills — a sweep that rewrites EVERY skill below the effectiveness threshold. APPROVAL-GATED (dev.skill_refine): when policy requires approval this returns {pending: true} with a deferred_operation_id and NOTHING is mutated until an operator approves — do not retry and do not report the sweep as done on that response. The seeded Platform Developer / Platform Architect rows auto-approve only from the `trusted` trust tier and require approval below it; a caller with no matching row meets the unmatched default and parks.",
            parameters: {
              threshold: { type: "number", required: false, description: "Effectiveness threshold (default 0.4)" }
            }
          }
        }
      end

      def call(params)
        action = params[:action].to_s

        if (refusal = authorization_error(params))
          return refusal
        end

        case action
        when "generate_self_challenge" then generate_self_challenge(params)
        when "list_challenges" then list_challenges(params)
        when "get_challenge_result" then get_challenge_result(params)
        when "mutate_skill" then mutate_skill(params)
        when "compose_skills" then compose_skills(params)
        when "auto_evolve_skill" then auto_evolve_skill(params)
        else error_result("Unknown action: #{action}")
        end
      end

      private

      # === Per-action permission gating (IMP-6fbfeff384fa) ===
      #
      # Keyed on the action that RUNS, never on the name that was invoked: a
      # user principal is deliberately NOT pinned to the invoked tool name
      # (McpPlatformToolRegistrar#action_pinned_to_name?), so a name-keyed check
      # is bypassable by supplying a sibling :action.

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two bypasses, both EXPLICIT, matching the sibling tools' ladder:
      #
      #   internal?            in-process system callers that opted in with
      #                        `internal: true`. Never inferred from a nil user —
      #                        an MCP instance principal also arrives with none
      #                        (IMP-9030413bc292).
      #   instance_authorized? an mTLS node principal whose SPECIFIC tool name
      #                        already cleared Mcp::Principal#may_invoke?, and
      #                        whose action the registrar then pins to that same
      #                        name. Without this arm every such call is
      #                        hard-denied (BUG-R).
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the
        # MCP path coerces a permission answer, and a truthy non-boolean must not
        # read as a grant.
        user.has_permission?(required_perm_for(action)) == true
      end

      def generate_self_challenge(params)
        service = Ai::SelfImprovement::ChallengeService.new(account: account)
        skill = params["skill_id"] ? Ai::Skill.find_by(id: params["skill_id"], account: account) : nil
        challenge = service.generate_challenge!(
          agent: agent,
          skill: skill,
          difficulty: params["difficulty"] || "medium"
        )
        return error_result("Failed to generate challenge") unless challenge
        success_result(challenge.as_json(only: [:id, :challenge_id, :status, :difficulty, :challenge_prompt]))
      rescue StandardError => e
        error_result("Challenge generation failed: #{e.message}")
      end

      def list_challenges(params)
        scope = Ai::SelfChallenge.for_agent(agent.id)
        scope = scope.where(status: params["status"]) if params["status"]
        challenges = scope.recent.limit((params["limit"] || 20).to_i)
        success_result({
          challenges: challenges.map { |c| c.as_json(only: [:id, :challenge_id, :status, :difficulty, :quality_score, :created_at]) },
          count: challenges.size
        })
      rescue StandardError => e
        error_result("List challenges failed: #{e.message}")
      end

      def get_challenge_result(params)
        challenge = Ai::SelfChallenge.find_by(id: params["challenge_id"], account: account)
        return error_result("Challenge not found") unless challenge
        success_result(challenge.as_json(except: [:updated_at]))
      rescue StandardError => e
        error_result("Get challenge failed: #{e.message}")
      end

      # The tool's own pre-dispatch authorization, hoisted out of #call so a
      # GATED refine verb — which bypasses #call — is authorized exactly as an
      # ungated action is (BaseTool#execute reads this seam before the gate).
      # Keyed on the action that RUNS (routed_action_name), never on the
      # invoked name, for the reason ACTION_PERMISSIONS states.
      def authorization_error(params)
        action = routed_action_name(params)
        return nil if action_permitted?(action)

        Rails.logger.warn(
          "[SelfImprovementTool] Refused action for insufficient permission: " \
          "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
        )
        error_result("permission denied: #{required_perm_for(action)} required")
      end

      # Params reach the body with STRING keys on the first hop (the MCP layer
      # hands an indifferent hash) and with SYMBOL keys on an approved replay
      # (Ai::Executors::DeferredToolCall#replay restores the shape
      # validate_params! reads). Reading both keeps the replay from silently
      # failing with "Skill not found" on the very call an operator approved.
      def param(params, key)
        params[key.to_sym] || params[key.to_s]
      end

      # The gated mutation's context (HIER-P2B-ENG): the same account-scoped
      # lookup as the body, so an unknown or foreign skill keeps its inline
      # error and parks nothing. Anchored to the skill row; the description
      # names the skill (a row value) and not the strategy (a caller value —
      # that belongs on the operation's params under Ai::SensitiveParams).
      def mutate_skill_gate_context(params)
        skill = Ai::Skill.find_by(id: param(params, :skill_id), account: account)
        raise ArgumentError, "Skill not found" unless skill

        deferred_tool_call_context(params).merge(
          source_type: "Ai::Skill",
          source_id: skill.id,
          description: "Refine the prompt of skill '#{skill.name}' (#{skill.slug}) with a mutation strategy"
        )
      end

      def mutate_skill(params)
        skill = Ai::Skill.find_by(id: param(params, :skill_id), account: account)
        return error_result("Skill not found") unless skill
        strategy = param(params, :strategy)
        service = Ai::SelfImprovement::SkillMutationService.new(account: account)
        version = service.mutate!(skill: skill, strategy: strategy)
        return error_result("Mutation produced no variant") unless version
        success_result({ version_id: version.id, strategy: strategy })
      rescue StandardError => e
        error_result("Skill mutation failed: #{e.message}")
      end

      def compose_skills(params)
        service = Ai::SelfImprovement::SkillMutationService.new(account: account)
        composite = service.compose_skills!(
          component_skill_ids: params["component_skill_ids"],
          name: params["name"],
          strategy: params["strategy"] || "sequential"
        )
        return error_result("Composition failed") unless composite
        success_result({ skill_id: composite.id, name: composite.name, is_composite: true })
      rescue StandardError => e
        error_result("Skill composition failed: #{e.message}")
      end

      # The sweep's admission rule, spelled once for the body and the gate
      # context: an absent threshold takes the default, a present one must be
      # a number — a call that could only ever be refused must not park.
      # Returns the Float, or raises ArgumentError with the refusal.
      def evolve_threshold(params)
        raw = param(params, :threshold)
        return 0.4 if raw.nil?
        return raw.to_f if raw.is_a?(Numeric)
        return raw.to_f if raw.is_a?(String) && raw.strip.match?(/\A-?\d+(\.\d+)?\z/)

        raise ArgumentError, "threshold must be a number (got #{raw.inspect})"
      end

      # The gated sweep's context (HIER-P2B-ENG). No single source row — the
      # sweep touches every underperforming skill in the account — so it is
      # anchored to nothing and described by its scope.
      def auto_evolve_skill_gate_context(params)
        threshold = evolve_threshold(params)

        deferred_tool_call_context(params).merge(
          description: "Auto-evolve every skill below effectiveness #{threshold} in this account " \
                       "(a new prompt version per underperforming skill)"
        )
      end

      def auto_evolve_skill(params)
        threshold = evolve_threshold(params)
        service = Ai::SelfImprovement::SkillMutationService.new(account: account)
        mutated = service.auto_mutate_underperforming!(threshold: threshold)
        success_result({ skills_mutated: mutated })
      rescue ArgumentError => e
        error_result(e.message)
      rescue StandardError => e
        error_result("Auto evolution failed: #{e.message}")
      end
    end
  end
end
