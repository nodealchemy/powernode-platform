# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class RecommendationSensor < Base
        def sensor_type
          "recommendation"
        end

        def collect
          observations = []

          # Check pending improvement recommendations
          pending_recs = pending_recommendations
          pending_recs.each do |rec|
            obs = build_observation(
              title: "Recommendation: #{rec[:title]}",
              observation_type: "recommendation",
              severity: rec[:priority] == "high" ? "warning" : "info",
              data: {
                recommendation_id: rec[:id],
                recommendation_type: rec[:recommendation_type],
                priority: rec[:priority],
                description: rec[:description]
              },
              requires_action: true,
              expires_in: 72.hours
            )
            observations << obs if obs
          end

          # Check trajectory-based recommendations specific to this agent
          trajectory_recs = agent_trajectory_recommendations
          trajectory_recs.each do |rec|
            obs = build_observation(
              title: "Performance insight: #{rec[:insight]}",
              observation_type: "recommendation",
              severity: "info",
              data: rec,
              requires_action: false,
              expires_in: 48.hours
            )
            observations << obs if obs
          end

          observations.compact
        end

        private

        def pending_recommendations
          Ai::ImprovementRecommendation
            .where(account_id: account.id, status: "pending")
            .where(ai_agent_id: [agent.id, nil])
            .limit(5)
            .map do |rec|
              {
                id: rec.id,
                title: rec.title,
                recommendation_type: rec.recommendation_type,
                priority: rec.priority,
                description: rec.description&.truncate(200)
              }
            end
        rescue StandardError
          []
        end

        def agent_trajectory_recommendations
          Ai::Trajectory
            .where(account_id: account.id, ai_agent_id: agent.id)
            .where("created_at >= ?", 7.days.ago)
            .where.not(analysis: nil)
            .order(created_at: :desc)
            .limit(3)
            .filter_map do |trajectory|
              analysis = trajectory.analysis
              next unless analysis.is_a?(Hash) && analysis["recommendations"].present?

              {
                trajectory_id: trajectory.id,
                insight: analysis["summary"]&.truncate(200) || "Performance analysis available",
                recommendations: analysis["recommendations"]&.first(3)
              }
            end
        rescue StandardError
          []
        end
      end
    end
  end
end
