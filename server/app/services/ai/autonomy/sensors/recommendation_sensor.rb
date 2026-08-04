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

        # Agent attribution is the polymorphic target, and the rich fields live in
        # the evidence jsonb (see Ai::Tools::ImprovementTool#create_improvement).
        # Recommendations aimed at another agent are somebody else's; anything not
        # aimed at an agent at all is fleet-wide and relevant to everyone.
        #
        # Code-quality offers are excluded: they are the /improve loop's backlog,
        # drained as Ralph tasks by Ai::DevLoop::ImprovementPromotionService, and
        # are repository-targeted rather than agent-targeted. Feeding them here
        # would hand every agent another repository's lint findings as its own
        # action items and spend the AgentObservation per-hour budget the other
        # sensors need. Newest-first so an agent's own recent recommendations
        # cannot be crowded out of the limit by an older backlog.
        def pending_recommendations
          Ai::ImprovementRecommendation
            .where(account_id: account.id, status: "pending")
            .where.not(recommendation_type: Ai::ImprovementRecommendation::CODE_QUALITY_TYPES)
            .where("target_type <> 'Ai::Agent' OR target_id = ?", agent.id)
            .order(created_at: :desc)
            .limit(5)
            .map do |rec|
              evidence = rec.evidence.is_a?(Hash) ? rec.evidence : {}
              {
                id: rec.id,
                title: evidence["title"].presence || "#{rec.recommendation_type} improvement",
                recommendation_type: rec.recommendation_type,
                priority: evidence["priority"],
                description: evidence["description"]&.truncate(200)
              }
            end
        rescue StandardError => e
          Rails.logger.error "[Sensors::Recommendation] pending_recommendations failed: #{e.class}: #{e.message}"
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
