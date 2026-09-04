# frozen_string_literal: true

module Ai
  module SelfImprovement
    # The VERSIONED path for refining a skill's prompt (HIER-P3; proposal §5
    # ruling 6).
    #
    # SkillMutationService is the LLM-driven mutator and deliberately reads only
    # an account's OWN skills — a global canonical (HIER-P2G made the system
    # catalog global) is never mutated in place by an account. The canonical
    # rule for skills is the same as for agents: an account clones and refines
    # the clone, and a canonical itself is refined only through the Platform
    # Architect's versioned path. This class IS that path: it takes a prompt
    # that was already authored and reviewed (an approved governance offer's
    # diff, or a trusted agent's refinement) and records it as an
    # Ai::SkillVersion — diffable (the previous prompt travels in the version's
    # metadata), revertible (activate the prior version), attributable (the
    # acting agent is the version's author).
    #
    # It WRITES; it does not gate. The caller resolves `dev.prompt_refine`
    # through Ai::AutonomyGate first — the P2B-ENG pair rows auto-approve a
    # `trusted` Platform Architect and park anything below it — and reaches
    # this seam only on :proceed or on the approved replay.
    class SkillRefinementService
      Result = Struct.new(:version, :changed, keyword_init: true)

      CHANGE_TYPE = "evolution"
      SOURCE = "governance"

      def initialize(account:, agent: nil, user: nil)
        raise ArgumentError, "account is required" if account.nil?

        @account = account
        @agent = agent
        @user = user
      end

      # @param skill [Ai::Skill] global canonical or account skill
      # @param system_prompt [String] the refined prompt, in full
      # @param reason [String] why — becomes the version's change_reason
      # @return [Result] version nil and changed false when the prompt is unchanged
      def refine!(skill:, system_prompt:, reason:)
        raise ArgumentError, "skill is required" if skill.nil?
        raise ArgumentError, "system_prompt must not be blank" if system_prompt.to_s.strip.empty?

        prompt = system_prompt.to_s
        previous = skill.system_prompt.to_s
        return Result.new(version: nil, changed: false) if prompt == previous

        version = nil
        ::Ai::Skill.transaction do
          version = ::Ai::SkillVersion.create!(
            account: @account,
            ai_skill: skill,
            version: next_version_for(skill),
            change_type: CHANGE_TYPE,
            change_reason: reason.to_s,
            system_prompt: prompt,
            created_by_agent: @agent,
            created_by_user: @user,
            is_active: false,
            metadata: {
              "source" => SOURCE,
              "previous_system_prompt" => previous,
              "agent_id" => @agent&.id
            }.compact
          )
          version.activate!
          skill.update!(system_prompt: prompt)
        end

        Result.new(version: version, changed: true)
      end

      private

      # Same convention as SkillMutationService#create_variant and
      # SkillGraph::EvolutionService: count + 1, unique per skill (validated),
      # and never below an existing numeric version so a re-numbered history
      # cannot collide with a live one.
      def next_version_for(skill)
        highest = skill.versions.pluck(:version).filter_map { |v| Integer(v, exception: false) }.max || 0
        [ skill.versions.count + 1, highest + 1 ].max.to_s
      end
    end
  end
end
