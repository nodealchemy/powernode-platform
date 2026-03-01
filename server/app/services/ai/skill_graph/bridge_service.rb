# frozen_string_literal: true

module Ai
  module SkillGraph
    class BridgeService
      SKILL_RELATION_TYPES = %w[requires enhances composes succeeds uses].freeze

      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Create/update KG node linked to a skill, generate pgvector embedding
      def sync_skill(skill)
        node = skill.knowledge_graph_node

        text = build_embedding_text(skill)
        embedding = embedding_service.generate(text)

        if node.present?
          node.update!(
            name: skill.name,
            description: skill.description,
            properties: build_skill_properties(skill),
            confidence: 1.0,
            status: "active",
            last_seen_at: Time.current
          )
          node.set_embedding!(embedding) if embedding
        else
          node = graph_service.create_node(
            name: skill.name,
            node_type: "entity",
            entity_type: "skill",
            description: skill.description,
            properties: build_skill_properties(skill),
            confidence: 1.0,
            metadata: { ai_skill_id: skill.id }
          )
          # Link the node to the skill via the FK
          node.update!(ai_skill_id: skill.id)
          node.set_embedding!(embedding) if embedding
        end

        node
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::BridgeService] sync_skill failed for #{skill.id}: #{e.message}"
        nil
      end

      # Create/update KG node linked to an agent, generate pgvector embedding, sync edges
      def sync_agent(agent)
        node = account.ai_knowledge_graph_nodes
          .where(entity_type: "agent")
          .where("metadata @> ?", { ai_agent_id: agent.id }.to_json)
          .first

        text = build_agent_embedding_text(agent)
        embedding = embedding_service.generate(text)

        if node.present?
          node.update!(
            name: agent.name,
            description: agent.description,
            properties: build_agent_properties(agent),
            confidence: 1.0,
            status: "active",
            last_seen_at: Time.current
          )
          node.set_embedding!(embedding) if embedding
        else
          node = graph_service.create_node(
            name: agent.name,
            node_type: "entity",
            entity_type: "agent",
            description: agent.description,
            properties: build_agent_properties(agent),
            confidence: 1.0,
            metadata: { ai_agent_id: agent.id }
          )
          node.set_embedding!(embedding) if embedding
        end

        sync_agent_skill_edges(agent, node)
        sync_agent_team_edges(agent, node)

        node
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::BridgeService] sync_agent failed for #{agent.id}: #{e.message}"
        nil
      end

      # Bulk sync all active account skills
      def sync_all_skills
        skills = Ai::Skill.for_account(account.id).active
        results = { synced: 0, failed: 0 }

        skills.find_each do |skill|
          if sync_skill(skill)
            results[:synced] += 1
          else
            results[:failed] += 1
          end
        end

        Rails.logger.info "[SkillGraph::BridgeService] Bulk sync complete: #{results.inspect}"
        results
      end

      # Create a KG edge between two skill nodes
      def create_skill_edge(source_skill_id:, target_skill_id:, relation_type:, weight: 1.0, confidence: 1.0)
        unless SKILL_RELATION_TYPES.include?(relation_type)
          raise ArgumentError, "Invalid skill relation_type: #{relation_type}. Must be one of: #{SKILL_RELATION_TYPES.join(', ')}"
        end

        source_node = find_skill_node!(source_skill_id)
        target_node = find_skill_node!(target_skill_id)

        graph_service.create_edge(
          source: source_node,
          target: target_node,
          relation_type: relation_type,
          weight: weight,
          confidence: confidence,
          metadata: { source_skill_id: source_skill_id, target_skill_id: target_skill_id }
        )
      end

      # Delete a skill edge
      def remove_skill_edge(edge_id)
        graph_service.delete_edge(edge_id)
      end

      # Use pgvector nearest_neighbors to suggest relationships with confidence scores
      def auto_detect_relationships(skill, similarity_threshold: 0.7)
        node = skill.knowledge_graph_node
        return [] unless node&.embedding.present?

        # Find similar skill nodes via pgvector
        candidates = account.ai_knowledge_graph_nodes
          .skill_nodes
          .active
          .with_embeddings
          .where.not(id: node.id)
          .nearest_neighbors(:embedding, node.embedding, distance: "cosine")
          .first(20)

        # Filter by threshold and build suggestions
        # neighbor_distance is virtual — filter in Ruby
        suggestions = candidates.filter_map do |candidate|
          distance = candidate.neighbor_distance
          similarity = 1.0 - distance
          next if similarity < similarity_threshold

          {
            skill_id: candidate.ai_skill_id,
            skill_name: candidate.name,
            node_id: candidate.id,
            similarity: similarity.round(4),
            suggested_relation: infer_relation_type(skill, candidate, similarity),
            confidence: similarity.round(4)
          }
        end

        suggestions.sort_by { |s| -s[:similarity] }
      end

      # Return all skill nodes + interconnecting edges for the account
      def skill_subgraph
        nodes = account.ai_knowledge_graph_nodes.skill_nodes.active
        node_ids = nodes.pluck(:id)

        edges = account.ai_knowledge_graph_edges
          .includes(:source_node, :target_node)
          .where(source_node_id: node_ids, target_node_id: node_ids)
          .active

        {
          nodes: nodes.map { |n| serialize_skill_node(n) },
          edges: edges.map { |e| serialize_skill_edge(e) },
          node_count: nodes.size,
          edge_count: edges.size
        }
      end

      private

      def graph_service
        @graph_service ||= Ai::KnowledgeGraph::GraphService.new(account)
      end

      def embedding_service
        @embedding_service ||= Ai::Memory::EmbeddingService.new(account: account)
      end

      def build_agent_embedding_text(agent)
        parts = [agent.name]
        parts << agent.description if agent.description.present?
        parts << "type: #{agent.agent_type}" if agent.agent_type.present?
        skill_names = agent.skills.active.pluck(:name)
        parts << "skills: #{skill_names.join(', ')}" if skill_names.any?
        parts.join(" | ")
      end

      def build_agent_properties(agent)
        {
          agent_type: agent.agent_type,
          status: agent.status,
          version: agent.version,
          skill_count: agent.agent_skills.where(is_active: true).count
        }.compact
      end

      def sync_agent_skill_edges(agent, agent_node)
        skill_nodes = account.ai_knowledge_graph_nodes
          .skill_nodes.active
          .where(ai_skill_id: agent.skills.active.select(:id))

        existing_edge_target_ids = account.ai_knowledge_graph_edges
          .where(source_node_id: agent_node.id, relation_type: "uses")
          .pluck(:target_node_id)
          .to_set

        skill_nodes.find_each do |skill_node|
          next if existing_edge_target_ids.include?(skill_node.id)

          graph_service.create_edge(
            source: agent_node,
            target: skill_node,
            relation_type: "uses",
            weight: 1.0,
            confidence: 1.0,
            metadata: { ai_agent_id: agent.id, ai_skill_id: skill_node.ai_skill_id }
          )
        end
      rescue StandardError => e
        Rails.logger.warn "[SkillGraph::BridgeService] sync_agent_skill_edges failed: #{e.message}"
      end

      def sync_agent_team_edges(agent, agent_node)
        team_ids = agent.agent_team_members.pluck(:ai_agent_team_id)
        return if team_ids.empty?

        team_nodes = account.ai_knowledge_graph_nodes
          .where(entity_type: "team")
          .where("metadata @> ?", { source: "agent_team" }.to_json)

        existing_edge_target_ids = account.ai_knowledge_graph_edges
          .where(source_node_id: agent_node.id, relation_type: "part_of")
          .pluck(:target_node_id)
          .to_set

        team_nodes.find_each do |team_node|
          next if existing_edge_target_ids.include?(team_node.id)

          graph_service.create_edge(
            source: agent_node,
            target: team_node,
            relation_type: "part_of",
            weight: 1.0,
            confidence: 1.0,
            metadata: { ai_agent_id: agent.id }
          )
        end
      rescue StandardError => e
        Rails.logger.warn "[SkillGraph::BridgeService] sync_agent_team_edges failed: #{e.message}"
      end

      def build_embedding_text(skill)
        parts = [skill.name]
        parts << skill.description if skill.description.present?
        parts << "category: #{skill.category}" if skill.category.present?
        parts << "tags: #{skill.tags.join(', ')}" if skill.tags.present? && skill.tags.any?
        parts.join(" | ")
      end

      def build_skill_properties(skill)
        {
          category: skill.category,
          tags: skill.tags,
          status: skill.status,
          is_system: skill.is_system,
          usage_count: skill.usage_count,
          version: skill.version
        }.compact
      end

      def find_skill_node!(skill_id)
        node = account.ai_knowledge_graph_nodes.skill_nodes.active.find_by(ai_skill_id: skill_id)
        raise Ai::KnowledgeGraph::GraphServiceError, "Skill node not found for skill: #{skill_id}" unless node

        node
      end

      def infer_relation_type(source_skill, target_node, similarity)
        target_skill = Ai::Skill.find_by(id: target_node.ai_skill_id)
        return "enhances" unless target_skill

        # Same category → enhances; different category with high similarity → composes
        if source_skill.category == target_skill.category
          similarity > 0.9 ? "enhances" : "requires"
        else
          "composes"
        end
      end

      def serialize_skill_node(node)
        props = node.properties || {}
        skill = node.ai_skill_id.present? ? ::Ai::Skill.find_by(id: node.ai_skill_id) : nil

        {
          id: node.id,
          name: node.name,
          skill_id: node.ai_skill_id,
          category: props["category"] || skill&.category || "uncategorized",
          status: props["status"] || skill&.status || "active",
          description: node.description,
          command_count: skill&.agent_skills&.count || 0,
          connector_count: 0,
          dependency_count: account.ai_knowledge_graph_edges
            .where(source_node_id: node.id)
            .or(account.ai_knowledge_graph_edges.where(target_node_id: node.id))
            .count,
          confidence: node.confidence,
          created_at: node.created_at
        }
      end

      def serialize_skill_edge(edge)
        {
          id: edge.id,
          source_node_id: edge.source_node_id,
          target_node_id: edge.target_node_id,
          source_skill_id: edge.source_node_id,
          target_skill_id: edge.target_node_id,
          source_skill_name: edge.source_node&.name,
          target_skill_name: edge.target_node&.name,
          relation_type: edge.relation_type,
          weight: edge.weight,
          confidence: edge.confidence,
          created_at: edge.created_at
        }
      end
    end
  end
end
