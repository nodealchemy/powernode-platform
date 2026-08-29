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
            description: "Mutate a skill using a specified strategy to improve it",
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
            description: "Automatically find and mutate underperforming skills",
            parameters: {
              threshold: { type: "number", required: false, description: "Effectiveness threshold (default 0.4)" }
            }
          }
        }
      end

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[SelfImprovementTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
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

      def mutate_skill(params)
        skill = Ai::Skill.find_by(id: params["skill_id"], account: account)
        return error_result("Skill not found") unless skill
        service = Ai::SelfImprovement::SkillMutationService.new(account: account)
        version = service.mutate!(skill: skill, strategy: params["strategy"])
        return error_result("Mutation produced no variant") unless version
        success_result({ version_id: version.id, strategy: params["strategy"] })
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

      def auto_evolve_skill(params)
        service = Ai::SelfImprovement::SkillMutationService.new(account: account)
        mutated = service.auto_mutate_underperforming!(threshold: (params["threshold"] || 0.4).to_f)
        success_result({ skills_mutated: mutated })
      rescue StandardError => e
        error_result("Auto evolution failed: #{e.message}")
      end
    end
  end
end
