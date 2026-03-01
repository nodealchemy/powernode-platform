# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class KnowledgeHealthSensor < Base
        def sensor_type
          "knowledge_health"
        end

        def collect
          observations = []

          # Check stale learnings
          stale_count = stale_learnings_count
          if stale_count > 10
            obs = build_observation(
              title: "#{stale_count} stale learnings detected",
              observation_type: "degradation",
              severity: stale_count > 50 ? "warning" : "info",
              data: { stale_count: stale_count, threshold: 10 },
              requires_action: true,
              expires_in: 24.hours
            )
            observations << obs if obs
          end

          # Check knowledge graph health
          orphan_count = orphaned_nodes_count
          if orphan_count > 20
            obs = build_observation(
              title: "#{orphan_count} orphaned knowledge graph nodes",
              observation_type: "degradation",
              severity: "info",
              data: { orphan_count: orphan_count },
              requires_action: false,
              expires_in: 48.hours
            )
            observations << obs if obs
          end

          # Check for learnings conflicts
          conflict_count = conflicting_learnings_count
          if conflict_count > 0
            obs = build_observation(
              title: "#{conflict_count} conflicting learnings need resolution",
              observation_type: "opportunity",
              severity: "warning",
              data: { conflict_count: conflict_count },
              requires_action: true,
              expires_in: 24.hours
            )
            observations << obs if obs
          end

          observations.compact
        end

        private

        def stale_learnings_count
          Ai::CompoundLearning
            .where(account_id: account.id, status: "active")
            .where("updated_at < ?", 30.days.ago)
            .count
        rescue StandardError
          0
        end

        def orphaned_nodes_count
          Ai::KnowledgeGraphNode
            .where(account_id: account.id)
            .left_joins(:source_edges, :target_edges)
            .where(ai_knowledge_graph_edges: { id: nil })
            .count
        rescue StandardError
          0
        end

        def conflicting_learnings_count
          # Look for learnings with contradictory status
          Ai::CompoundLearning
            .where(account_id: account.id, status: "disputed")
            .count
        rescue StandardError
          0
        end
      end
    end
  end
end
