# frozen_string_literal: true

module Ai
  module SkillGraph
    class ConflictDetectionService
      DUPLICATE_THRESHOLD = 0.92
      OVERLAP_THRESHOLD_LOW = 0.7
      STALE_DAYS = 90
      STALE_MIN_AGE = 30
      STALE_USAGE_CAP = 5
      ORPHAN_MIN_AGE = 30
      ORPHAN_EXTENDED_AGE = 60

      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Run all 6 detectors and return summary
      def scan_all
        results = {
          duplicate: detect_duplicates,
          overlapping: detect_overlapping,
          circular_dependency: detect_circular_dependencies,
          stale: detect_stale_skills,
          orphan: detect_orphan_skills,
          version_drift: detect_version_drift
        }

        summary = results.transform_values { |v| v.is_a?(Array) ? v.size : 0 }
        total = summary.values.sum

        Rails.logger.info "[SkillGraph::ConflictDetection] Scan complete: #{total} conflicts found (#{summary.inspect})"
        { conflicts: results, summary: summary, total: total, scanned_at: Time.current }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ConflictDetection] scan_all failed: #{e.message}"
        { conflicts: {}, summary: {}, total: 0, error: e.message }
      end

      # Detect duplicate skills (similarity >= 0.92)
      def detect_duplicates
        created = []
        skill_nodes = account.ai_knowledge_graph_nodes.skill_nodes.active.with_embeddings.to_a

        skill_nodes.each_with_index do |node, idx|
          candidates = skill_nodes[(idx + 1)..] || []
          next if candidates.empty?

          # Use pgvector nearest_neighbors from this node's embedding
          similar = account.ai_knowledge_graph_nodes
            .skill_nodes.active.with_embeddings
            .where.not(id: node.id)
            .nearest_neighbors(:embedding, node.embedding, distance: "cosine")
            .first(5)

          similar.each do |candidate|
            similarity = 1.0 - candidate.neighbor_distance
            next if similarity < DUPLICATE_THRESHOLD
            next unless candidate.ai_skill_id.present? && node.ai_skill_id.present?

            conflict = create_conflict_if_new(
              skill_a_id: node.ai_skill_id,
              skill_b_id: candidate.ai_skill_id,
              conflict_type: "duplicate",
              severity: "critical",
              auto_resolvable: true,
              similarity_score: similarity.round(4),
              node_a_id: node.id,
              node_b_id: candidate.id,
              resolution_strategy: "merge_to_higher_usage"
            )
            created << conflict if conflict
          end
        end

        Rails.logger.info "[SkillGraph::ConflictDetection] detect_duplicates found #{created.size} conflicts"
        created
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ConflictDetection] detect_duplicates failed: #{e.message}"
        []
      end

      # Detect overlapping skills (similarity 0.7-0.92, same category)
      def detect_overlapping
        created = []
        skill_nodes = account.ai_knowledge_graph_nodes.skill_nodes.active.with_embeddings.to_a

        skill_nodes.each do |node|
          similar = account.ai_knowledge_graph_nodes
            .skill_nodes.active.with_embeddings
            .where.not(id: node.id)
            .nearest_neighbors(:embedding, node.embedding, distance: "cosine")
            .first(10)

          similar.each do |candidate|
            similarity = 1.0 - candidate.neighbor_distance
            next unless similarity.between?(OVERLAP_THRESHOLD_LOW, DUPLICATE_THRESHOLD)
            next unless candidate.ai_skill_id.present? && node.ai_skill_id.present?

            # Only flag if same category
            skill_a = Ai::Skill.find_by(id: node.ai_skill_id)
            skill_b = Ai::Skill.find_by(id: candidate.ai_skill_id)
            next unless skill_a && skill_b && skill_a.category == skill_b.category

            conflict = create_conflict_if_new(
              skill_a_id: node.ai_skill_id,
              skill_b_id: candidate.ai_skill_id,
              conflict_type: "overlapping",
              severity: "medium",
              auto_resolvable: false,
              similarity_score: similarity.round(4),
              node_a_id: node.id,
              node_b_id: candidate.id,
              resolution_strategy: "human_review"
            )
            created << conflict if conflict
          end
        end

        Rails.logger.info "[SkillGraph::ConflictDetection] detect_overlapping found #{created.size} conflicts"
        created
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ConflictDetection] detect_overlapping failed: #{e.message}"
        []
      end

      # Detect circular dependencies via recursive CTE on knowledge_graph_edges
      def detect_circular_dependencies
        created = []

        sql = <<~SQL
          WITH RECURSIVE cycle_search AS (
            SELECT
              e.id AS edge_id,
              e.source_node_id,
              e.target_node_id,
              e.relation_type,
              e.weight,
              e.confidence,
              ARRAY[e.source_node_id] AS path,
              false AS is_cycle
            FROM ai_knowledge_graph_edges e
            INNER JOIN ai_knowledge_graph_nodes src ON src.id = e.source_node_id
            WHERE e.account_id = :account_id
              AND e.status = 'active'
              AND src.entity_type = 'skill'
              AND src.status = 'active'

            UNION ALL

            SELECT
              e2.id AS edge_id,
              e2.source_node_id,
              e2.target_node_id,
              e2.relation_type,
              e2.weight,
              e2.confidence,
              cs.path || e2.source_node_id,
              e2.target_node_id = ANY(cs.path) AS is_cycle
            FROM cycle_search cs
            INNER JOIN ai_knowledge_graph_edges e2
              ON e2.source_node_id = cs.target_node_id
              AND e2.status = 'active'
              AND e2.account_id = :account_id
            INNER JOIN ai_knowledge_graph_nodes tgt ON tgt.id = e2.source_node_id
            WHERE NOT cs.is_cycle
              AND array_length(cs.path, 1) < 10
              AND tgt.entity_type = 'skill'
              AND tgt.status = 'active'
          )
          SELECT DISTINCT path, edge_id, source_node_id, target_node_id, weight, confidence
          FROM cycle_search
          WHERE is_cycle = true
          LIMIT 20
        SQL

        results = ActiveRecord::Base.connection.exec_query(
          ActiveRecord::Base.sanitize_sql([sql, account_id: account.id])
        )

        results.each do |row|
          source_node = account.ai_knowledge_graph_nodes.find_by(id: row["source_node_id"])
          target_node = account.ai_knowledge_graph_nodes.find_by(id: row["target_node_id"])
          next unless source_node&.ai_skill_id && target_node&.ai_skill_id

          conflict = create_conflict_if_new(
            skill_a_id: source_node.ai_skill_id,
            skill_b_id: target_node.ai_skill_id,
            conflict_type: "circular_dependency",
            severity: "high",
            auto_resolvable: true,
            edge_id: row["edge_id"],
            node_a_id: source_node.id,
            node_b_id: target_node.id,
            resolution_strategy: "remove_weakest_edge",
            resolution_details: {
              cycle_edge_id: row["edge_id"],
              edge_weight: row["weight"].to_f,
              edge_confidence: row["confidence"].to_f
            }
          )
          created << conflict if conflict
        end

        Rails.logger.info "[SkillGraph::ConflictDetection] detect_circular_dependencies found #{created.size} conflicts"
        created
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ConflictDetection] detect_circular_dependencies failed: #{e.message}"
        []
      end

      # Detect stale skills: last_used_at > 90 days ago (or nil) AND usage_count < 5 AND created > 30 days
      def detect_stale_skills
        created = []

        stale_skills = Ai::Skill.for_account(account.id).active
          .where("ai_skills.created_at < ?", STALE_MIN_AGE.days.ago)
          .where("ai_skills.usage_count < ?", STALE_USAGE_CAP)
          .where(
            "ai_skills.last_used_at IS NULL OR ai_skills.last_used_at < ?",
            STALE_DAYS.days.ago
          )

        stale_skills.find_each do |skill|
          conflict = create_conflict_if_new(
            skill_a_id: skill.id,
            skill_b_id: nil,
            conflict_type: "stale",
            severity: "low",
            auto_resolvable: true,
            resolution_strategy: "decay_effectiveness",
            resolution_details: {
              usage_count: skill.usage_count,
              last_used_at: skill.last_used_at&.iso8601,
              days_since_use: skill.last_used_at ? ((Time.current - skill.last_used_at) / 1.day).to_i : nil
            }
          )
          created << conflict if conflict
        end

        Rails.logger.info "[SkillGraph::ConflictDetection] detect_stale_skills found #{created.size} conflicts"
        created
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ConflictDetection] detect_stale_skills failed: #{e.message}"
        []
      end

      # Detect orphan skills: no agent_skills AND no KG edges AND created > 30 days
      def detect_orphan_skills
        created = []

        orphan_skills = Ai::Skill.for_account(account.id).active
          .where("ai_skills.created_at < ?", ORPHAN_MIN_AGE.days.ago)
          .left_joins(:agent_skills)
          .where(ai_agent_skills: { id: nil })

        orphan_skills.find_each do |skill|
          # Also check for KG edges
          node = skill.knowledge_graph_node
          if node
            edge_count = account.ai_knowledge_graph_edges.active
              .where("source_node_id = :nid OR target_node_id = :nid", nid: node.id)
              .count
            next if edge_count > 0
          end

          conflict = create_conflict_if_new(
            skill_a_id: skill.id,
            skill_b_id: nil,
            conflict_type: "orphan",
            severity: "low",
            auto_resolvable: true,
            resolution_strategy: "auto_connect_or_recommend",
            resolution_details: {
              has_kg_node: node.present?,
              days_since_creation: ((Time.current - skill.created_at) / 1.day).to_i
            }
          )
          created << conflict if conflict
        end

        Rails.logger.info "[SkillGraph::ConflictDetection] detect_orphan_skills found #{created.size} conflicts"
        created
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ConflictDetection] detect_orphan_skills failed: #{e.message}"
        []
      end

      # Detect version drift: multiple active skills sharing the same first word in name
      def detect_version_drift
        created = []

        skills = Ai::Skill.for_account(account.id).active.pluck(:id, :name)
        prefix_groups = skills.group_by { |_, name| name.to_s.split(/\s+/).first&.downcase }.select { |_, v| v.size > 1 }

        prefix_groups.each do |_prefix, group|
          next if group.size < 2

          # Create conflicts between each pair
          group.combination(2).each do |a, b|
            conflict = create_conflict_if_new(
              skill_a_id: a[0],
              skill_b_id: b[0],
              conflict_type: "version_drift",
              severity: "medium",
              auto_resolvable: false,
              resolution_strategy: "human_review",
              resolution_details: {
                skill_a_name: a[1],
                skill_b_name: b[1],
                shared_prefix: a[1].to_s.split(/\s+/).first
              }
            )
            created << conflict if conflict
          end
        end

        Rails.logger.info "[SkillGraph::ConflictDetection] detect_version_drift found #{created.size} conflicts"
        created
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ConflictDetection] detect_version_drift failed: #{e.message}"
        []
      end

      private

      # Idempotent: skip conflicts where an active one already exists for the same combo
      def create_conflict_if_new(skill_a_id:, skill_b_id:, conflict_type:, severity:, auto_resolvable:, **attrs)
        existing = Ai::SkillConflict.where(account: account, conflict_type: conflict_type)
          .active
          .where(skill_a_id: skill_a_id)

        if skill_b_id
          existing = existing.where(skill_b_id: skill_b_id)
            .or(
              Ai::SkillConflict.where(account: account, conflict_type: conflict_type)
                .active
                .where(skill_a_id: skill_b_id, skill_b_id: skill_a_id)
            )
        else
          existing = existing.where(skill_b_id: nil)
        end

        return nil if existing.exists?

        conflict = Ai::SkillConflict.create!(
          account: account,
          skill_a_id: skill_a_id,
          skill_b_id: skill_b_id,
          conflict_type: conflict_type,
          severity: severity,
          status: "detected",
          auto_resolvable: auto_resolvable,
          detected_at: Time.current,
          **attrs.slice(:similarity_score, :node_a_id, :node_b_id, :edge_id,
                        :resolution_strategy, :resolution_details)
        )

        conflict.calculate_priority!
        conflict
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "[SkillGraph::ConflictDetection] Conflict creation failed: #{e.message}"
        nil
      end
    end
  end
end
