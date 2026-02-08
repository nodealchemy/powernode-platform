# frozen_string_literal: true

module Api
  module V1
    module Ai
      class LearningController < ApplicationController
        before_action :validate_permissions

        # GET /api/v1/ai/learning/recommendations
        def recommendations
          recs = ::Ai::ImprovementRecommendation.where(account: current_user.account)
                                                 .recent(params[:limit]&.to_i || 50)

          recs = recs.where(status: params[:status]) if params[:status].present?
          recs = recs.by_type(params[:type]) if params[:type].present?

          render_success(
            recommendations: recs.map { |r| recommendation_json(r) }
          )
        end

        # POST /api/v1/ai/learning/recommendations/:id/apply
        def apply_recommendation
          recommender = ::Ai::Learning::ImprovementRecommender.new(account: current_user.account)
          recommendation = recommender.apply_recommendation!(params[:id], user: current_user)

          if recommendation
            render_success(recommendation: recommendation_json(recommendation))
          else
            render_error("Recommendation not found or cannot be applied", status: :not_found)
          end
        end

        # POST /api/v1/ai/learning/recommendations/:id/dismiss
        def dismiss_recommendation
          recommendation = ::Ai::ImprovementRecommendation.find_by(
            id: params[:id], account: current_user.account
          )

          if recommendation
            recommendation.dismiss!
            render_success(recommendation: recommendation_json(recommendation))
          else
            render_error("Recommendation not found", status: :not_found)
          end
        end

        # GET /api/v1/ai/learning/agent_trends
        def agent_trends
          evaluation_service = ::Ai::Learning::EvaluationService.new(account: current_user.account)
          agents = current_user.account.ai_agents.where(status: "active")

          trends = agents.filter_map do |agent|
            trend_data = evaluation_service.agent_score_trends(agent.id)
            next if trend_data.blank?

            trend_data.merge(agent_id: agent.id, agent_name: agent.name)
          end

          render_success(trends: trends)
        end

        # GET /api/v1/ai/learning/cache_metrics
        def cache_metrics
          metrics = ::Ai::Learning::PromptCacheService.metrics

          render_success(metrics: metrics)
        end

        # GET /api/v1/ai/learning/compound_metrics
        def compound_metrics
          service = ::Ai::Learning::CompoundLearningService.new(account: current_user.account)
          metrics = service.compound_metrics

          render_success(metrics: metrics)
        end

        # GET /api/v1/ai/learning/learnings
        def learnings
          service = ::Ai::Learning::CompoundLearningService.new(account: current_user.account)
          results = service.list_learnings(
            status: params[:status] || "active",
            category: params[:category],
            scope: params[:scope],
            min_importance: params[:min_importance]&.to_f,
            team_id: params[:team_id],
            query: params[:query],
            limit: params[:limit]&.to_i || 50
          )

          render_success(
            learnings: results.map { |l| l.respond_to?(:learning_summary) ? l.learning_summary : l }
          )
        end

        # POST /api/v1/ai/learning/reinforce/:id
        def reinforce
          service = ::Ai::Learning::CompoundLearningService.new(account: current_user.account)
          learning = service.reinforce_learning(params[:id])

          if learning
            render_success(learning: learning.learning_summary)
          else
            render_error("Learning not found", status: :not_found)
          end
        end

        # POST /api/v1/ai/learning/promote
        def promote
          service = ::Ai::Learning::CompoundLearningService.new(account: current_user.account)
          count = service.promote_cross_team

          render_success(promoted_count: count)
        end

        # POST /api/v1/ai/learning/compound_maintenance (internal, called by worker)
        def compound_maintenance
          service = ::Ai::Learning::CompoundLearningService.new(account: current_user.account)

          maintenance_result = service.decay_and_consolidate
          promotion_count = service.promote_cross_team

          render_success(
            maintenance: maintenance_result,
            promoted: promotion_count
          )
        end

        private

        def validate_permissions
          case action_name
          when "recommendations", "agent_trends", "cache_metrics"
            require_permission("ai.analytics.read")
          when "compound_metrics", "learnings"
            require_permission("ai.analytics.read")
          when "apply_recommendation", "dismiss_recommendation"
            require_permission("ai.analytics.manage")
          when "reinforce", "promote", "compound_maintenance"
            require_permission("ai.analytics.manage")
          end
        end

        def recommendation_json(rec)
          {
            id: rec.id,
            recommendation_type: rec.recommendation_type,
            target_type: rec.target_type,
            target_id: rec.target_id,
            current_config: rec.current_config,
            recommended_config: rec.recommended_config,
            evidence: rec.evidence,
            confidence_score: rec.confidence_score,
            status: rec.status,
            created_at: rec.created_at&.iso8601
          }
        end
      end
    end
  end
end
