# frozen_string_literal: true

module Ai
  module Tools
    class CodeMemoryTool < BaseTool
      include Concerns::CodebaseContextResolvable

      REQUIRED_PERMISSION = "ai.agents.read"

      CODE_ENTITY_TYPES = %w[file directory class module method function variable type_definition interface constant].freeze
      CODE_RELATION_TYPES = %w[imports calls defines inherits implements contains related_to depends_on uses].freeze

      def self.definition
        {
          name: "code_memory",
          description: "Code-aware memory graph operations: create/update code nodes, create relations, search the code graph, prune stale links, and trigger bulk indexing",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
            base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
            name: { type: "string", required: false, description: "Node name" },
            entity_type: { type: "string", required: false, description: "Entity type (class, method, function, etc.)" },
            file_path: { type: "string", required: false, description: "File path" },
            line_range: { type: "string", required: false, description: "Line range (e.g. '10-25')" },
            description: { type: "string", required: false, description: "Node description" },
            properties: { type: "object", required: false, description: "Additional properties" },
            source_node_id: { type: "string", required: false, description: "Source node ID (for create_relation)" },
            target_node_id: { type: "string", required: false, description: "Target node ID (for create_relation)" },
            relation_type: { type: "string", required: false, description: "Relation type" },
            weight: { type: "number", required: false, description: "Edge weight 0-1 (default 1.0)" },
            query: { type: "string", required: false, description: "Search query" },
            entity_types: { type: "array", required: false, description: "Filter by entity types" },
            max_depth: { type: "integer", required: false, description: "Graph traversal depth (default 2)" },
            top_k: { type: "integer", required: false, description: "Max results (default 10)" },
            dry_run: { type: "boolean", required: false, description: "Preview without executing (default true)" },
            path: { type: "string", required: false, description: "Subdirectory to index" },
            incremental: { type: "boolean", required: false, description: "Incremental indexing (default true)" }
          }
        }
      end

      def self.action_definitions
        {
          "code_upsert_node" => {
            description: "Create or update a code-aware knowledge graph node. Auto-generates embeddings for semantic search.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              name: { type: "string", required: true, description: "Qualified node name (e.g. 'User#full_name')" },
              entity_type: { type: "string", required: true, description: "Entity type: #{CODE_ENTITY_TYPES.join(', ')}" },
              file_path: { type: "string", required: false, description: "File path relative to codebase root" },
              line_range: { type: "string", required: false, description: "Line range (e.g. '10-25')" },
              description: { type: "string", required: false, description: "Human-readable description" },
              properties: { type: "object", required: false, description: "Additional metadata" }
            }
          },
          "code_create_relation" => {
            description: "Create a typed edge between two code nodes (e.g. imports, calls, inherits).",
            parameters: {
              source_node_id: { type: "string", required: true, description: "Source node ID" },
              target_node_id: { type: "string", required: true, description: "Target node ID" },
              relation_type: { type: "string", required: true, description: "Relation type: #{CODE_RELATION_TYPES.join(', ')}" },
              weight: { type: "number", required: false, description: "Edge weight 0-1 (default 1.0)" },
              properties: { type: "object", required: false, description: "Edge metadata" }
            }
          },
          "code_search_graph" => {
            description: "Search the code graph with optional multi-hop traversal. Combines name matching with graph expansion.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              query: { type: "string", required: true, description: "Search query" },
              entity_types: { type: "array", required: false, description: "Filter by entity types" },
              max_depth: { type: "integer", required: false, description: "Graph traversal depth (default 2)" },
              top_k: { type: "integer", required: false, description: "Max results (default 10)" }
            }
          },
          "code_prune_stale" => {
            description: "Find and remove/archive code nodes for files that no longer exist on disk. Use dry_run to preview.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              dry_run: { type: "boolean", required: false, description: "Preview without executing (default true)" }
            }
          },
          "code_bulk_index" => {
            description: "Trigger codebase indexing. Parses source files, creates knowledge graph nodes/edges, and generates embeddings.",
            parameters: {
              repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
              base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
              path: { type: "string", required: false, description: "Subdirectory to index (default: entire codebase)" },
              incremental: { type: "boolean", required: false, description: "Only re-index changed files (default true)" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "upsert_node" then upsert_node(params)
        when "create_relation" then create_relation(params)
        when "search_graph" then search_graph(params)
        when "prune_stale" then prune_stale(params)
        when "bulk_index" then bulk_index(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      end

      private

      # ─── Upsert Node ──────────────────────────────────────────────

      def upsert_node(params)
        return { success: false, error: "name is required" } if params[:name].blank?
        return { success: false, error: "entity_type is required" } if params[:entity_type].blank?

        unless CODE_ENTITY_TYPES.include?(params[:entity_type])
          return { success: false, error: "Invalid entity_type. Valid: #{CODE_ENTITY_TYPES.join(', ')}" }
        end

        _repo, kb, _bp = resolve_project_context(params)

        properties = (params[:properties] || {}).merge({})
        properties["file_path"] = params[:file_path] if params[:file_path].present?

        if params[:line_range].present?
          parts = params[:line_range].split("-")
          properties["line_start"] = parts[0].to_i
          properties["line_end"] = parts[1]&.to_i || parts[0].to_i
        end

        existing = kb.knowledge_graph_nodes.find_by(
          account: account, name: params[:name], node_type: "code_entity", status: "active"
        )

        if existing
          existing.update!(
            entity_type: params[:entity_type],
            description: params[:description] || existing.description,
            properties: existing.properties.merge(properties),
            last_seen_at: Time.current
          )
          existing.record_mention!

          # Regenerate embedding if description changed
          if params[:description].present?
            embedding = generate_embedding("#{existing.name} #{existing.description}")
            existing.set_embedding!(embedding) if embedding
          end

          { success: true, action: "updated", node: serialize_node(existing) }
        else
          node = kb.knowledge_graph_nodes.create!(
            account: account,
            name: params[:name],
            node_type: "code_entity",
            entity_type: params[:entity_type],
            description: params[:description],
            properties: properties,
            status: "active",
            confidence: 1.0,
            mention_count: 1,
            last_seen_at: Time.current
          )

          # Generate embedding
          if params[:description].present?
            embedding = generate_embedding("#{node.name} #{node.description}")
            node.set_embedding!(embedding) if embedding
          end

          { success: true, action: "created", node: serialize_node(node) }
        end
      end

      # ─── Create Relation ───────────────────────────────────────────

      def create_relation(params)
        return { success: false, error: "source_node_id is required" } if params[:source_node_id].blank?
        return { success: false, error: "target_node_id is required" } if params[:target_node_id].blank?
        return { success: false, error: "relation_type is required" } if params[:relation_type].blank?

        unless CODE_RELATION_TYPES.include?(params[:relation_type])
          return { success: false, error: "Invalid relation_type. Valid: #{CODE_RELATION_TYPES.join(', ')}" }
        end

        source = Ai::KnowledgeGraphNode.find_by(id: params[:source_node_id], account: account, status: "active")
        target = Ai::KnowledgeGraphNode.find_by(id: params[:target_node_id], account: account, status: "active")

        return { success: false, error: "Source node not found" } unless source
        return { success: false, error: "Target node not found" } unless target

        existing = Ai::KnowledgeGraphEdge.find_by(
          account: account, source_node: source, target_node: target,
          relation_type: params[:relation_type], status: "active"
        )

        if existing
          existing.update!(
            weight: params[:weight] || existing.weight,
            properties: existing.properties.merge(params[:properties] || {})
          )
          { success: true, action: "updated", edge: serialize_edge(existing) }
        else
          edge = Ai::KnowledgeGraphEdge.create!(
            account: account,
            source_node: source,
            target_node: target,
            relation_type: params[:relation_type],
            weight: params[:weight] || 1.0,
            confidence: 1.0,
            properties: params[:properties] || {},
            status: "active"
          )
          { success: true, action: "created", edge: serialize_edge(edge) }
        end
      end

      # ─── Search Graph ──────────────────────────────────────────────

      def search_graph(params)
        return { success: false, error: "query is required" } if params[:query].blank?

        _repo, kb, _bp = resolve_project_context(params)
        top_k = (params[:top_k] || 10).to_i
        max_depth = (params[:max_depth] || 2).to_i
        entity_types = Array(params[:entity_types]).presence

        query = ActiveRecord::Base.sanitize_sql_like(params[:query])

        scope = kb.knowledge_graph_nodes
                   .where(account: account, node_type: "code_entity", status: "active")

        scope = scope.where(entity_type: entity_types) if entity_types

        # Name + description search
        matches = scope.where("name ILIKE :q OR description ILIKE :q OR properties->>'simple_name' ILIKE :q",
                              q: "%#{query}%")
                       .order(mention_count: :desc)
                       .limit(top_k)

        graph_service = Ai::KnowledgeGraph::GraphService.new(account)

        results = matches.map do |node|
          entry = serialize_node(node)

          # Optionally expand neighbors
          if max_depth > 0
            neighbors = graph_service.find_neighbors(node: node.id, depth: [max_depth, 3].min)
            entry[:neighbors] = neighbors.first(10)
          end

          entry
        end

        { success: true, results: results, count: results.size, query: params[:query] }
      end

      # ─── Prune Stale ───────────────────────────────────────────────

      def prune_stale(params)
        _repo, kb, bp = resolve_project_context(params)
        dry_run = params[:dry_run] != false # default true

        file_nodes = kb.knowledge_graph_nodes
                        .where(account: account, node_type: "code_entity", entity_type: "file", status: "active")

        stale_nodes = []
        stale_edges = []

        file_nodes.find_each(batch_size: 100) do |node|
          full_path = File.join(bp, node.name)
          next if File.exist?(full_path)

          stale_nodes << { id: node.id, name: node.name, entity_type: node.entity_type }

          # Also collect child nodes (symbols defined in this file)
          children = kb.knowledge_graph_nodes
                        .where(account: account, node_type: "code_entity", status: "active")
                        .where("properties->>'file_path' = ?", node.name)

          children.each do |child|
            stale_nodes << { id: child.id, name: child.name, entity_type: child.entity_type }
          end

          # Collect edges
          edges = Ai::KnowledgeGraphEdge.where(account: account, status: "active")
                                         .where("source_node_id = :id OR target_node_id = :id", id: node.id)
          edges.each do |edge|
            stale_edges << { id: edge.id, relation_type: edge.relation_type }
          end
        end

        unless dry_run
          stale_node_ids = stale_nodes.map { |n| n[:id] }.uniq
          stale_edge_ids = stale_edges.map { |e| e[:id] }.uniq

          Ai::KnowledgeGraphEdge.where(id: stale_edge_ids).update_all(status: "archived") if stale_edge_ids.any?
          Ai::KnowledgeGraphNode.where(id: stale_node_ids).update_all(status: "archived") if stale_node_ids.any?
        end

        {
          success: true,
          dry_run: dry_run,
          pruned_nodes: stale_nodes.uniq { |n| n[:id] },
          pruned_edges: stale_edges.uniq { |e| e[:id] },
          summary: {
            nodes_affected: stale_nodes.uniq { |n| n[:id] }.size,
            edges_affected: stale_edges.uniq { |e| e[:id] }.size
          }
        }
      end

      # ─── Bulk Index ────────────────────────────────────────────────

      def bulk_index(params)
        _repo, kb, bp = resolve_project_context(params)
        incremental = params[:incremental] != false # default true

        service = Ai::Codebase::IndexingService.new(
          account: account,
          knowledge_base: kb,
          base_path: bp
        )

        service.index(path: params[:path], incremental: incremental)
      end

      # ─── Helpers ───────────────────────────────────────────────────

      def generate_embedding(text)
        embedding_service = Ai::Memory::EmbeddingService.new(account: account)
        embedding_service.generate(text)
      rescue => e
        Rails.logger.warn "[CodeMemoryTool] Embedding error: #{e.message}"
        nil
      end

      def serialize_node(node)
        {
          id: node.id,
          name: node.name,
          entity_type: node.entity_type,
          description: node.description,
          file_path: node.properties&.dig("file_path"),
          line_start: node.properties&.dig("line_start"),
          line_end: node.properties&.dig("line_end"),
          visibility: node.properties&.dig("visibility"),
          params: node.properties&.dig("params"),
          mention_count: node.mention_count,
          confidence: node.confidence
        }
      end

      def serialize_edge(edge)
        {
          id: edge.id,
          source_node_id: edge.source_node_id,
          target_node_id: edge.target_node_id,
          relation_type: edge.relation_type,
          weight: edge.weight,
          confidence: edge.confidence
        }
      end
    end
  end
end
