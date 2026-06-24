# frozen_string_literal: true

module Ai
  module Tools
    class SelfImprovementTool < BaseTool
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
        case params[:action]
        when "generate_self_challenge" then generate_self_challenge(params)
        when "list_challenges" then list_challenges(params)
        when "get_challenge_result" then get_challenge_result(params)
        when "mutate_skill" then mutate_skill(params)
        when "compose_skills" then compose_skills(params)
        when "auto_evolve_skill" then auto_evolve_skill(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      end

      private

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
