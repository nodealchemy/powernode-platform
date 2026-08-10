# frozen_string_literal: true

module Ai
  module Learning
    class ImprovementRecommender
      def initialize(account:)
        @account = account
      end

      def generate_recommendations
        return [] unless Shared::FeatureFlagService.enabled?(:trajectory_analysis)
        # Tier-2(a) gate #3: kill-switch every write path — no recommendation
        # writes while the account's AI is emergency-halted.
        return [] if @account.respond_to?(:ai_suspended?) && @account.ai_suspended?

        analyzer = Ai::Learning::TrajectoryAnalyzer.new(account: @account)
        analyses = analyzer.analyze

        recommendations = analyses.map do |analysis|
          create_or_update_recommendation(analysis)
        end.compact

        recommendations
      end

      def apply_recommendation!(recommendation_id, user:)
        recommendation = Ai::ImprovementRecommendation.find_by(
          id: recommendation_id, account: @account
        )
        return nil unless recommendation

        target = recommendation.target
        return nil unless target

        case recommendation.recommendation_type
        when "provider_switch"
          apply_provider_switch(recommendation, target, user)
        when "timeout_adjustment"
          recommendation.apply!(user)
        when "cost_optimization"
          recommendation.apply!(user)
        when "skill_health"
          apply_skill_evolution(recommendation, user)
        when "skill_creation"
          apply_skill_creation(recommendation, user)
        when "prompt_refinement"
          return nil unless apply_prompt_refinement(recommendation, target, user)
        else
          recommendation.apply!(user)
        end

        recommendation
      end

      private

      # Refreshing an existing offer replaces its evidence/config wholesale, so it
      # must only ever match a row this analyzer owns. Rows written by another
      # subsystem tag themselves with evidence["source"] (e.g. policy tuning's
      # agent_reliability offers, which share this exact tuple); untagged rows are
      # this analyzer's own, including every row written before the tag existed.
      def create_or_update_recommendation(analysis)
        existing = Ai::ImprovementRecommendation.where(
          account: @account,
          recommendation_type: analysis[:recommendation_type],
          target_type: analysis[:target_type],
          target_id: analysis[:target_id],
          status: "pending"
        ).where("evidence->>'source' IS NULL").first

        if existing
          existing.update!(
            current_config: analysis[:current_config],
            recommended_config: analysis[:recommended_config],
            evidence: analysis[:evidence],
            confidence_score: analysis[:confidence_score]
          )
          existing
        else
          Ai::ImprovementRecommendation.create!(
            account: @account,
            recommendation_type: analysis[:recommendation_type],
            target_type: analysis[:target_type],
            target_id: analysis[:target_id],
            current_config: analysis[:current_config],
            recommended_config: analysis[:recommended_config],
            evidence: analysis[:evidence],
            confidence_score: analysis[:confidence_score]
          )
        end
      rescue => e
        Rails.logger.error "[ImprovementRecommender] Failed to create recommendation: #{e.message}"
        nil
      end

      def apply_provider_switch(recommendation, agent, user)
        new_provider_id = recommendation.recommended_config["provider_id"]
        return unless new_provider_id

        agent.update!(ai_provider_id: new_provider_id)
        recommendation.apply!(user)
      end

      # Approving a scheduled evolution proposal (Ai::SkillGraph::
      # EvolutionProposalService) activates the pre-drafted, already
      # clone-on-write-safe version it points at — the concrete "operator
      # said yes" action this recommendation type exists to gate. Older
      # skill_health recommendations (Ai::Learning::TrajectoryAnalyzer's
      # nightly low-success-rate signal) carry no proposed_version_id and
      # have nothing to activate — applying one just acknowledges review.
      # Approving a prompt_refinement used to fall through to the bare
      # `else recommendation.apply!(user)`, which only flips status — so the
      # operator approved "Refine prompt for 'X' based on 5 compound
      # learnings", the row read `applied`, and the skill's prompt was never
      # touched. A false actuator is worse than a dropped one, because the
      # audit trail asserts the change landed.
      #
      # There was nothing to write: SelfLearningService#propose_prompt_refinements
      # records only a title, description, learning_ids and effectiveness — it
      # never computes a refined prompt. So the refinement has to be PRODUCED
      # here, and EvolutionService#propose_evolution already does exactly that
      # (same nearest-neighbour compound-learning gather, build_evolved_prompt,
      # a new inactive SkillVersion). Reusing it also inherits the F5
      # clone-on-evolve guarantee: a global is_system skill is redirected onto
      # this account's editable clone instead of being versioned in place.
      #
      # An already-proposed version wins if one is present, mirroring
      # apply_skill_evolution — that keeps the two paths convergent if a
      # future proposer starts precomputing the version.
      #
      # Returns falsy when no refined version could be produced, and the
      # caller then refuses to mark the recommendation applied. That refusal
      # IS the fix: propose_evolution rescues internally and returns nil, so
      # without it a failed refinement would still report success.
      def apply_prompt_refinement(recommendation, target, user)
        service = Ai::SkillGraph::EvolutionService.new(@account)

        version_id = recommendation.recommended_config.is_a?(Hash) ? recommendation.recommended_config["proposed_version_id"] : nil
        version =
          if version_id.present?
            service.activate_version(version_id: version_id)
          else
            proposed = service.propose_evolution(skill_id: target.id)
            proposed && meaningful_refinement?(proposed) && service.activate_version(version_id: proposed.id)
          end

        unless version
          Rails.logger.warn(
            "[ImprovementRecommender] prompt_refinement #{recommendation.id} produced no refined " \
            "version for skill #{target.id} — leaving the recommendation unapplied rather than " \
            "reporting a refinement that did not happen"
          )
          return nil
        end

        recommendation.apply!(user)
        version
      end

      # propose_evolution SUCCEEDS even when the skill has no KG embedding or no
      # near-neighbour learnings: build_evolved_prompt then returns the previous
      # prompt plus a regenerated "# Skill context: ..." footer and nothing
      # else. Activating that and marking the recommendation applied would be
      # the very defect this branch was added to fix — an audit trail asserting
      # a refinement that did not happen — just one level further in. Worse, it
      # compounds: each apply builds on the last version's prompt, accreting
      # footers.
      #
      # learning_count is recorded by propose_evolution itself, so this asks the
      # service what it actually incorporated rather than diffing prompt text,
      # which would be fragile against the footer's exact format.
      def meaningful_refinement?(version)
        meta = version.metadata.respond_to?(:with_indifferent_access) ? version.metadata.with_indifferent_access : {}
        return true if meta[:learning_count].to_i.positive?

        Rails.logger.warn(
          "[ImprovementRecommender] discarding proposed version #{version.id} for skill " \
          "#{version.ai_skill_id}: no compound learnings were incorporated, so the 'evolved' prompt " \
          "differs from the current one only by a regenerated context footer"
        )
        version.destroy
        false
      end

      def apply_skill_evolution(recommendation, user)
        version_id = recommendation.recommended_config["proposed_version_id"]
        Ai::SkillGraph::EvolutionService.new(@account).activate_version(version_id: version_id) if version_id.present?

        recommendation.apply!(user)
      end

      # Approving a cluster-promotion skill_creation recommendation (Ai::
      # Learning::LearningToSkillPromoter#propose_from_cluster) approves the
      # underlying SkillProposal draft, then applies it — creating/refreshing
      # the skill, wiring KG provenance, and inheriting effectiveness from
      # the cluster's outcome aggregate. Older skill_creation recommendations
      # (Ai::SkillGraph::SelfLearningService#detect_capability_gaps's
      # capability-gap signal) carry no skill_proposal_id and have nothing to
      # apply — approving one just acknowledges review, same as before.
      def apply_skill_creation(recommendation, user)
        proposal_id = recommendation.recommended_config["skill_proposal_id"]
        if proposal_id.present?
          Ai::SkillGraph::LifecycleService.new(@account).approve_proposal(proposal_id: proposal_id, reviewer: user)
          Ai::Learning::LearningToSkillPromoter.new(account: @account).apply_approved_proposal!(proposal_id)
        end

        recommendation.apply!(user)
      end
    end
  end
end
