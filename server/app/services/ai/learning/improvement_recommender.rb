# frozen_string_literal: true

module Ai
  module Learning
    class ImprovementRecommender
      def initialize(account:)
        @account = account
      end

      def generate_recommendations
        return [] unless Shared::FeatureFlagService.enabled?(:trajectory_analysis)

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
    end
  end
end
