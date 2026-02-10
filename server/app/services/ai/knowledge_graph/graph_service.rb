# frozen_string_literal: true

module Ai
  module KnowledgeGraph
    class GraphServiceError < StandardError; end

    class GraphService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # ============================================================================
      # NODE OPERATIONS
      # ============================================================================

      def create_node(name:, node_type:, **attrs)
        validate_node_type!(node_type)

        node = Ai::KnowledgeGraphNode.create!(
          account: account,
          name: name,
          node_type: node_type,
          entity_type: attrs[:entity_type],
          description: attrs[:description],
          properties: attrs[:properties] || {},
          path: attrs[:path],
          knowledge_base_id: attrs[:knowledge_base_id],
          source_document_id: attrs[:source_document_id],
          confidence: attrs[:confidence] || 1.0,
          metadata: attrs[:metadata] || {},
          last_seen_at: Time.current
        )

        # Generate and set embedding if description available
        if node.description.present?
          embedding = embedding_service.generate(
            "#{node.name}: #{node.description}"
          )
          node.set_embedding!(embedding) if embedding
        end

        node
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "[GraphService] Create node failed: #{e.message}"
        raise GraphServiceError, "Failed to create node: #{e.message}"
      end

      def update_node(node_id, **attrs)
        node = find_node!(node_id)
        update_attrs = attrs.slice(
          :name, :description, :entity_type, :properties,
          :path, :confidence, :metadata, :status
        ).compact

        node.update!(update_attrs)

        # Regenerate embedding if name or description changed
        if (attrs.key?(:name) || attrs.key?(:description)) && node.description.present?
          embedding = embedding_service.generate(
            "#{node.name}: #{node.description}"
          )
          node.set_embedding!(embedding) if embedding
        end

        node
      end

      def delete_node(node_id)
        node = find_node!(node_id)
        node.destroy!
      end

      def find_node!(node_id)
        account.ai_knowledge_graph_nodes.find(node_id)
      rescue ActiveRecord::RecordNotFound
        raise GraphServiceError, "Node not found: #{node_id}"
      end

      def list_nodes(filters = {})
        nodes = account.ai_knowledge_graph_nodes.active
        nodes = nodes.by_type(filters[:node_type]) if filters[:node_type].present?
        nodes = nodes.by_entity_type(filters[:entity_type]) if filters[:entity_type].present?
        nodes = nodes.search_by_name(filters[:query]) if filters[:query].present?
        nodes = nodes.for_knowledge_base(filters[:knowledge_base_id]) if filters[:knowledge_base_id].present?
        nodes = nodes.order(created_at: :desc)
        nodes = nodes.page(filters[:page]).per(filters[:per_page] || 20) if filters[:page].present?
        nodes
      end

      # ============================================================================
      # EDGE OPERATIONS
      # ============================================================================

      def create_edge(source:, target:, relation_type:, **attrs)
        validate_relation_type!(relation_type)

        source_node = source.is_a?(Ai::KnowledgeGraphNode) ? source : find_node!(source)
        target_node = target.is_a?(Ai::KnowledgeGraphNode) ? target : find_node!(target)

        edge = Ai::KnowledgeGraphEdge.create!(
          account: account,
          source_node: source_node,
          target_node: target_node,
          relation_type: relation_type,
          label: attrs[:label],
          weight: attrs[:weight] || 1.0,
          confidence: attrs[:confidence] || 1.0,
          properties: attrs[:properties] || {},
          source_document_id: attrs[:source_document_id],
          bidirectional: attrs[:bidirectional] || false,
          metadata: attrs[:metadata] || {}
        )

        edge
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "[GraphService] Create edge failed: #{e.message}"
        raise GraphServiceError, "Failed to create edge: #{e.message}"
      end

      def delete_edge(edge_id)
        edge = account.ai_knowledge_graph_edges.find(edge_id)
        edge.destroy!
      rescue ActiveRecord::RecordNotFound
        raise GraphServiceError, "Edge not found: #{edge_id}"
      end

      def list_edges(filters = {})
        edges = account.ai_knowledge_graph_edges.active
        edges = edges.by_relation(filters[:relation_type]) if filters[:relation_type].present?
        edges = edges.for_node(filters[:node_id]) if filters[:node_id].present?
        edges = edges.order(created_at: :desc)
        edges
      end

      # ============================================================================
      # GRAPH TRAVERSAL
      # ============================================================================

      # Find neighbors of a node using recursive CTE for multi-hop traversal
      def find_neighbors(node:, depth: 1, relation_types: nil)
        node_record = node.is_a?(Ai::KnowledgeGraphNode) ? node : find_node!(node)
        depth = [depth.to_i, 5].min # Cap at 5 to prevent runaway queries

        relation_type_list = if relation_types.present?
          Array(relation_types).map { |t| Ai::KnowledgeGraphEdge.connection.quote(t) }.join(', ')
        end
        base_relation_filter = relation_type_list ? "AND e.relation_type IN (#{relation_type_list})" : ""
        recursive_relation_filter = relation_type_list ? "AND e2.relation_type IN (#{relation_type_list})" : ""

        sql = <<~SQL
          WITH RECURSIVE neighbors AS (
            SELECT
              n.id,
              n.name,
              n.node_type,
              n.entity_type,
              n.description,
              n.properties,
              n.confidence,
              n.status,
              1 AS depth,
              ARRAY[n.id] AS path
            FROM ai_knowledge_graph_nodes n
            INNER JOIN ai_knowledge_graph_edges e
              ON (e.target_node_id = n.id OR e.source_node_id = n.id)
              AND e.status = 'active'
              #{base_relation_filter}
            WHERE
              (e.source_node_id = :node_id OR e.target_node_id = :node_id)
              AND n.id != :node_id
              AND n.status = 'active'
              AND n.account_id = :account_id

            UNION

            SELECT
              n2.id,
              n2.name,
              n2.node_type,
              n2.entity_type,
              n2.description,
              n2.properties,
              n2.confidence,
              n2.status,
              nb.depth + 1 AS depth,
              nb.path || n2.id AS path
            FROM neighbors nb
            INNER JOIN ai_knowledge_graph_edges e2
              ON (e2.source_node_id = nb.id OR e2.target_node_id = nb.id)
              AND e2.status = 'active'
              #{recursive_relation_filter}
            INNER JOIN ai_knowledge_graph_nodes n2
              ON (n2.id = e2.target_node_id OR n2.id = e2.source_node_id)
              AND n2.id != nb.id
              AND n2.status = 'active'
              AND n2.account_id = :account_id
            WHERE
              nb.depth < :max_depth
              AND NOT (n2.id = ANY(nb.path))
          )
          SELECT DISTINCT ON (id) *
          FROM neighbors
          ORDER BY id, depth ASC
        SQL

        results = ActiveRecord::Base.connection.exec_query(
          ActiveRecord::Base.sanitize_sql([
            sql,
            node_id: node_record.id,
            account_id: account.id,
            max_depth: depth
          ])
        )

        results.map do |row|
          {
            id: row["id"],
            name: row["name"],
            node_type: row["node_type"],
            entity_type: row["entity_type"],
            description: row["description"],
            properties: row["properties"].is_a?(String) ? JSON.parse(row["properties"]) : row["properties"],
            confidence: row["confidence"]&.to_f,
            depth: row["depth"]
          }
        end
      end

      # Find shortest path between two nodes using BFS via recursive CTE
      def shortest_path(source:, target:, max_depth: 5)
        source_node = source.is_a?(Ai::KnowledgeGraphNode) ? source : find_node!(source)
        target_node = target.is_a?(Ai::KnowledgeGraphNode) ? target : find_node!(target)
        max_depth = [max_depth.to_i, 10].min

        sql = <<~SQL
          WITH RECURSIVE path_search AS (
            SELECT
              e.id AS edge_id,
              e.source_node_id,
              e.target_node_id,
              e.relation_type,
              e.weight,
              e.confidence,
              1 AS depth,
              ARRAY[e.source_node_id] AS visited_nodes,
              ARRAY[e.id] AS edge_path,
              CASE
                WHEN e.target_node_id = :target_id THEN true
                ELSE false
              END AS found
            FROM ai_knowledge_graph_edges e
            WHERE e.source_node_id = :source_id
              AND e.status = 'active'
              AND e.account_id = :account_id

            UNION ALL

            SELECT
              e2.id AS edge_id,
              e2.source_node_id,
              e2.target_node_id,
              e2.relation_type,
              e2.weight,
              e2.confidence,
              ps.depth + 1 AS depth,
              ps.visited_nodes || e2.source_node_id,
              ps.edge_path || e2.id,
              CASE
                WHEN e2.target_node_id = :target_id THEN true
                ELSE false
              END AS found
            FROM path_search ps
            INNER JOIN ai_knowledge_graph_edges e2
              ON e2.source_node_id = ps.target_node_id
              AND e2.status = 'active'
              AND e2.account_id = :account_id
            WHERE
              ps.depth < :max_depth
              AND NOT ps.found
              AND NOT (e2.target_node_id = ANY(ps.visited_nodes))
          )
          SELECT edge_path, depth
          FROM path_search
          WHERE found = true
          ORDER BY depth ASC
          LIMIT 1
        SQL

        result = ActiveRecord::Base.connection.exec_query(
          ActiveRecord::Base.sanitize_sql([
            sql,
            source_id: source_node.id,
            target_id: target_node.id,
            account_id: account.id,
            max_depth: max_depth
          ])
        )

        return nil if result.rows.empty?

        edge_ids = result.first["edge_path"]
        if edge_ids.is_a?(String)
          # Postgres array format: {uuid1,uuid2,...} — not JSON
          edge_ids = edge_ids.delete('{}').split(',')
        end

        edges = Ai::KnowledgeGraphEdge.where(id: edge_ids).includes(:source_node, :target_node)

        # Return edges in path order
        edge_ids.map { |eid| edges.find { |e| e.id == eid } }.compact
      end

      # Extract a subgraph with specific node IDs
      def subgraph(node_ids:, include_edges: true)
        nodes = account.ai_knowledge_graph_nodes.where(id: node_ids)

        result = { nodes: nodes.map { |n| serialize_node(n) } }

        if include_edges
          edges = account.ai_knowledge_graph_edges
            .where(source_node_id: node_ids, target_node_id: node_ids)
            .active
          result[:edges] = edges.map { |e| serialize_edge(e) }
        end

        result
      end

      # ============================================================================
      # NODE DEDUPLICATION
      # ============================================================================

      def merge_nodes(keep:, merge:, reason: nil)
        keep_node = keep.is_a?(Ai::KnowledgeGraphNode) ? keep : find_node!(keep)
        merge_node = merge.is_a?(Ai::KnowledgeGraphNode) ? merge : find_node!(merge)

        ActiveRecord::Base.transaction do
          # Reassign edges from merge_node to keep_node
          merge_node.outgoing_edges.each do |edge|
            next if edge.target_node_id == keep_node.id

            existing = Ai::KnowledgeGraphEdge.find_by(
              source_node_id: keep_node.id,
              target_node_id: edge.target_node_id,
              relation_type: edge.relation_type,
              status: "active"
            )

            if existing
              # Merge weights/confidence via average
              existing.update!(
                weight: [(existing.weight + edge.weight) / 2.0, 1.0].min,
                confidence: [(existing.confidence + edge.confidence) / 2.0, 1.0].min
              )
              edge.update!(status: "archived")
            else
              edge.update!(source_node_id: keep_node.id)
            end
          end

          merge_node.incoming_edges.each do |edge|
            next if edge.source_node_id == keep_node.id

            existing = Ai::KnowledgeGraphEdge.find_by(
              source_node_id: edge.source_node_id,
              target_node_id: keep_node.id,
              relation_type: edge.relation_type,
              status: "active"
            )

            if existing
              existing.update!(
                weight: [(existing.weight + edge.weight) / 2.0, 1.0].min,
                confidence: [(existing.confidence + edge.confidence) / 2.0, 1.0].min
              )
              edge.update!(status: "archived")
            else
              edge.update!(target_node_id: keep_node.id)
            end
          end

          # Update keep node stats
          keep_node.update!(
            mention_count: keep_node.mention_count + merge_node.mention_count,
            metadata: keep_node.metadata.merge(
              "merged_from" => (keep_node.metadata["merged_from"] || []) + [merge_node.id],
              "merge_reason" => reason
            )
          )

          # Mark merge node as merged
          merge_node.merge_into!(keep_node)
        end

        keep_node.reload
      end

      # ============================================================================
      # STATISTICS
      # ============================================================================

      def statistics
        nodes = account.ai_knowledge_graph_nodes.active
        edges = account.ai_knowledge_graph_edges.active

        node_count = nodes.count
        edge_count = edges.count

        {
          node_count: node_count,
          edge_count: edge_count,
          by_node_type: nodes.group(:node_type).count,
          by_entity_type: nodes.where.not(entity_type: nil).group(:entity_type).count,
          by_relation_type: edges.group(:relation_type).count,
          avg_confidence: nodes.average(:confidence)&.to_f&.round(4) || 0,
          avg_degree: node_count.positive? ? (edge_count * 2.0 / node_count).round(2) : 0,
          density: calculate_density(node_count, edge_count),
          nodes_with_embeddings: nodes.with_embeddings.count,
          top_connected_nodes: top_connected_nodes(5)
        }
      end

      private

      def validate_node_type!(type)
        return if Ai::KnowledgeGraphNode::NODE_TYPES.include?(type.to_s)

        raise GraphServiceError, "Invalid node_type: #{type}"
      end

      def validate_relation_type!(type)
        return if Ai::KnowledgeGraphEdge::RELATION_TYPES.include?(type.to_s)

        raise GraphServiceError, "Invalid relation_type: #{type}"
      end

      def embedding_service
        @embedding_service ||= Ai::Memory::EmbeddingService.new(account: account)
      end

      def calculate_density(node_count, edge_count)
        return 0 if node_count < 2

        max_edges = node_count * (node_count - 1)
        (edge_count.to_f / max_edges).round(6)
      end

      def top_connected_nodes(limit)
        sql = <<~SQL
          SELECT n.id, n.name, n.node_type,
            (SELECT COUNT(*) FROM ai_knowledge_graph_edges e
             WHERE (e.source_node_id = n.id OR e.target_node_id = n.id)
             AND e.status = 'active') AS degree
          FROM ai_knowledge_graph_nodes n
          WHERE n.account_id = :account_id
            AND n.status = 'active'
          ORDER BY degree DESC
          LIMIT :limit
        SQL

        ActiveRecord::Base.connection.exec_query(
          ActiveRecord::Base.sanitize_sql([sql, account_id: account.id, limit: limit])
        ).map do |row|
          { id: row["id"], name: row["name"], node_type: row["node_type"], degree: row["degree"] }
        end
      end

      def serialize_node(node)
        {
          id: node.id,
          name: node.name,
          node_type: node.node_type,
          entity_type: node.entity_type,
          description: node.description,
          properties: node.properties,
          confidence: node.confidence,
          mention_count: node.mention_count,
          status: node.status,
          created_at: node.created_at
        }
      end

      def serialize_edge(edge)
        {
          id: edge.id,
          source_node_id: edge.source_node_id,
          target_node_id: edge.target_node_id,
          relation_type: edge.relation_type,
          label: edge.label,
          weight: edge.weight,
          confidence: edge.confidence,
          bidirectional: edge.bidirectional,
          created_at: edge.created_at
        }
      end
    end
  end
end
