# frozen_string_literal: true

module Ai
  module Tools
    class KnowledgeGraphTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      def self.definition
        {
          name: "knowledge_graph",
          description: "Search, reason over, explore, and extract to the knowledge graph: hybrid search (vector+keyword+graph), multi-hop reasoning, node operations, neighbor traversal, subgraph extraction, LLM extraction from text, and statistics",
          parameters: {
            action: { type: "string", required: true, description: "Action: search, reason, get_node, list_nodes, get_neighbors, statistics, subgraph, extract" },
            text: { type: "string", required: false, description: "Text to extract entities and relations from (for extract)" },
            source_label: { type: "string", required: false, description: "Optional label for the extraction source (for extract)" },
            query: { type: "string", required: false, description: "Search query (for search/reason/list_nodes)" },
            node_id: { type: "string", required: false, description: "Node ID (for get_node/get_neighbors)" },
            node_ids: { type: "array", required: false, description: "Array of node IDs (for subgraph)" },
            mode: { type: "string", required: false, description: "Search mode: hybrid/vector/keyword/graph (for search, default hybrid)" },
            top_k: { type: "integer", required: false, description: "Max results (for search/reason, default 10)" },
            max_hops: { type: "integer", required: false, description: "Max reasoning hops (for reason, default 3)" },
            depth: { type: "integer", required: false, description: "Traversal depth (for get_neighbors, default 1, max 5)" },
            relation_types: { type: "array", required: false, description: "Filter by relation types (for get_neighbors)" },
            node_type: { type: "string", required: false, description: "Filter by node type (for list_nodes)" },
            entity_type: { type: "string", required: false, description: "Filter by entity type (for list_nodes)" },
            knowledge_base_id: { type: "string", required: false, description: "Filter by knowledge base (for search/list_nodes)" },
            page: { type: "integer", required: false, description: "Page number (for list_nodes)" },
            per_page: { type: "integer", required: false, description: "Results per page (for list_nodes, default 20)" }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "search" then search(params)
        when "reason" then reason(params)
        when "get_node" then get_node(params)
        when "list_nodes" then list_nodes(params)
        when "get_neighbors" then get_neighbors(params)
        when "statistics" then get_statistics
        when "subgraph" then get_subgraph(params)
        when "extract" then extract(params)
        else { success: false, error: "Unknown action: #{params[:action]}. Valid actions: search, reason, get_node, list_nodes, get_neighbors, statistics, subgraph, extract" }
        end
      end

      private

      def search(params)
        return { success: false, error: "query is required" } if params[:query].blank?

        result = hybrid_search_service.search(
          query: params[:query],
          mode: (params[:mode] || "hybrid").to_sym,
          top_k: (params[:top_k] || 10).to_i,
          knowledge_base_id: params[:knowledge_base_id]
        )

        { success: true, **result }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def reason(params)
        return { success: false, error: "query is required" } if params[:query].blank?

        result = reasoning_service.reason(
          query: params[:query],
          max_hops: (params[:max_hops] || 3).to_i,
          top_k: (params[:top_k] || 5).to_i
        )

        { success: true, **result }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def get_node(params)
        return { success: false, error: "node_id is required" } if params[:node_id].blank?

        node = graph_service.find_node!(params[:node_id])
        { success: true, node: serialize_node(node) }
      rescue Ai::KnowledgeGraph::GraphServiceError => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def list_nodes(params)
        filters = {}
        filters[:node_type] = params[:node_type] if params[:node_type].present?
        filters[:entity_type] = params[:entity_type] if params[:entity_type].present?
        filters[:query] = params[:query] if params[:query].present?
        filters[:knowledge_base_id] = params[:knowledge_base_id] if params[:knowledge_base_id].present?
        filters[:page] = params[:page] if params[:page].present?
        filters[:per_page] = (params[:per_page] || 20).to_i.clamp(1, 50)

        nodes = graph_service.list_nodes(filters)

        result = { success: true }

        if nodes.respond_to?(:total_count)
          result[:count] = nodes.total_count
          result[:page] = filters[:page]
          result[:total_pages] = nodes.total_pages
        else
          result[:count] = nodes.size
        end

        result[:nodes] = nodes.map { |n| serialize_node(n) }
        result
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def get_neighbors(params)
        return { success: false, error: "node_id is required" } if params[:node_id].blank?

        neighbors = graph_service.find_neighbors(
          node: params[:node_id],
          depth: (params[:depth] || 1).to_i,
          relation_types: params[:relation_types]
        )

        { success: true, count: neighbors.size, neighbors: neighbors }
      rescue Ai::KnowledgeGraph::GraphServiceError => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def get_statistics
        stats = graph_service.statistics
        { success: true, **stats }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def get_subgraph(params)
        node_ids = Array(params[:node_ids])
        return { success: false, error: "node_ids is required (array of node IDs)" } if node_ids.empty?

        result = graph_service.subgraph(node_ids: node_ids)
        { success: true, **result }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def extract(params)
        return { success: false, error: "text is required" } if params[:text].blank?

        result = extraction_service.extract_from_text(
          text: params[:text],
          source_label: params[:source_label]
        )

        {
          success: true,
          **result[:stats],
          nodes: result[:nodes].map { |n| serialize_node(n) },
          edges: result[:edges].map { |e| { id: e.id, source: e.source_node_id, target: e.target_node_id, relation_type: e.relation_type } }
        }
      rescue Ai::KnowledgeGraph::ExtractionServiceError => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def graph_service
        @graph_service ||= Ai::KnowledgeGraph::GraphService.new(account)
      end

      def hybrid_search_service
        @hybrid_search_service ||= Ai::Rag::HybridSearchService.new(account)
      end

      def reasoning_service
        @reasoning_service ||= Ai::KnowledgeGraph::MultiHopReasoningService.new(account)
      end

      def extraction_service
        @extraction_service ||= Ai::KnowledgeGraph::ExtractionService.new(account)
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
          created_at: node.created_at&.iso8601
        }
      end
    end
  end
end
