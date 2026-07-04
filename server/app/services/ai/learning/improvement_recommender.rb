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
        else
          recommendation.apply!(user)
        end

        recommendation
      end

      private

      def create_or_update_recommendation(analysis)
        existing = Ai::ImprovementRecommendation.find_by(
          account: @account,
          recommendation_type: analysis[:recommendation_type],
          target_type: analysis[:target_type],
          target_id: analysis[:target_id],
          status: "pending"
        )

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
      def apply_skill_evolution(recommendation, user)
        version_id = recommendation.recommended_config["proposed_version_id"]
        Ai::SkillGraph::EvolutionService.new(@account).activate_version(version_id: version_id) if version_id.present?

        recommendation.apply!(user)
      end
    end
  end
end
