# frozen_string_literal: true

module Ai
  module Tools
    class KnowledgeGraphTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "extract", mutating: true,
                                returns: "nodes_created, nodes_existing, edges_created, edges_existing, and the nodes and edges touched",
                                refuses: "text is blank, or extraction fails"
      declare_action "get_neighbors", mutating: false,
                                      returns: "count and neighbors (id, name, node_type, entity_type, description, properties, confidence, depth)",
                                      refuses: "node_id is blank, or the node is not in this account",
                                      see_also: { "get_subgraph" => "the edges among a set of nodes you already hold" }
      declare_action "get_node", mutating: false,
                                 returns: "the node's id, name, node_type, entity_type, description, properties, confidence, " \
                                          "mention_count, status and created_at",
                                 refuses: "node_id is blank, or the node is not in this account",
                                 see_also: { "get_graph_neighbors" => "the nodes linked to it" }
      declare_action "list_nodes", mutating: false,
                                   returns: "count and active nodes newest first; with page set, also page and total_pages",
                                   see_also: { "search_knowledge_graph" => "ranking nodes by meaning rather than name" }
      declare_action "reason", mutating: false,
                               returns: "answer_nodes, scored paths, reasoning_chain, confidence, seed_nodes_found and total_paths_explored",
                               refuses: "query is blank",
                               see_also: { "search_knowledge_graph" => "a ranked list of matches without path expansion" }
      declare_action "search", mutating: false, limit: 50,
                               returns: "fused results (id, type, content, score, source, metadata), per-mode result counts and the search id",
                               refuses: [ "query is blank", "mode is not hybrid, vector, keyword or graph" ],
                               see_also: {
                                 "search_knowledge" => "curated shared knowledge entries such as guidance",
                                 "query_learnings" => "lessons extracted from agent and team executions",
                                 "query_knowledge_base" => "document chunks in one named RAG knowledge base",
                                 "search_memory" => "one agent's short-term memory and learnings, by keyword"
                               }
      declare_action "statistics", mutating: false,
                                   returns: "node and edge counts, counts by node, entity and relation type, average confidence " \
                                            "and degree, density, nodes_with_embeddings and the five most connected nodes"
      declare_action "subgraph", mutating: false,
                                 returns: "the named nodes in this account and the active edges between them",
                                 refuses: "node_ids is empty",
                                 see_also: { "get_graph_neighbors" => "expanding outward from one node" }

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

      # Keys MUST match TOOLS hash (external names), not ACTION_ALIASES (internal names).
      # McpPlatformToolRegistrar.ACTION_ALIASES handles the mapping at execution time.
      def self.action_definitions
        {
          "search_knowledge_graph" => {
            description: "Search the knowledge graph and RAG document chunks by hybrid retrieval: vector, keyword and graph modes fused by rank. " \
                         "The graph holds this account's nodes (entities, concepts, code entities, pages and articles) and the edges between them. " \
                         "They are written by extract_to_knowledge_graph, the skill and agent graph sync, page and article linking, the data source " \
                         "bridge, the code index, learning promotion and the codebase knowledge-population scan. " \
                         "Vector and keyword modes match document chunks; graph mode matches embedded nodes and the chunks of their source documents. " \
                         "Each call records a hybrid search result row.",
            parameters: {
              query: { type: "string", required: true, description: "Search query" },
              mode: { type: "string", required: false, description: "Search mode: hybrid/vector/keyword/graph (default: hybrid)" },
              top_k: { type: "integer", required: false, description: "Max results (default 10)" },
              knowledge_base_id: { type: "string", required: false, description: "Filter by knowledge base" }
            }
          },
          "reason_knowledge_graph" => {
            description: "Answer a question by multi-hop reasoning over the knowledge graph. " \
                         "Seed nodes are found by embedding similarity (by name or description keywords when embeddings find none) and expanded along edges. " \
                         "The max_hops value is capped at 5 and top_k at 20.",
            parameters: {
              query: { type: "string", required: true, description: "Reasoning query" },
              max_hops: { type: "integer", required: false, description: "Max reasoning hops (default 3)" },
              top_k: { type: "integer", required: false, description: "Max results (default 5)" }
            }
          },
          "get_graph_node" => {
            description: "Get one knowledge graph node by id, in any status.",
            parameters: {
              node_id: { type: "string", required: true, description: "Node ID" }
            }
          },
          "list_graph_nodes" => {
            description: "List active knowledge graph nodes with optional type, entity type, name and knowledge base filters. " \
                         "The query filter matches node names by substring. The per_page value (default 20, max 50) applies only when page is set.",
            parameters: {
              node_type: { type: "string", required: false, description: "Filter by node type" },
              entity_type: { type: "string", required: false, description: "Filter by entity type" },
              query: { type: "string", required: false, description: "Search query" },
              knowledge_base_id: { type: "string", required: false, description: "Filter by knowledge base" },
              page: { type: "integer", required: false, description: "Page number" },
              per_page: { type: "integer", required: false, description: "Results per page (default 20)" }
            }
          },
          "get_graph_neighbors" => {
            description: "Get the nodes reachable from one knowledge graph node, up to depth hops away. " \
                         "Depth defaults to 1 and is capped at 5; relation_types limits which edges are followed.",
            parameters: {
              node_id: { type: "string", required: true, description: "Node ID" },
              depth: { type: "integer", required: false, description: "Traversal depth (default 1, max 5)" },
              relation_types: { type: "array", required: false, description: "Filter by relation types" }
            }
          },
          "graph_statistics" => {
            description: "Get statistics for this account's active knowledge graph nodes and edges.",
            parameters: {}
          },
          "get_subgraph" => {
            description: "Get the listed knowledge graph nodes and the edges that connect them to each other. " \
                         "Ids not in this account are skipped.",
            parameters: {
              node_ids: { type: "array", required: true, description: "Array of node IDs" }
            }
          },
          "extract_to_knowledge_graph" => {
            description: "Extract entities and relationships from text and add them to the knowledge graph. " \
                         "An active entity node with the same name is reused and its mention count raised. The source_label value is only written to the log.",
            parameters: {
              text: { type: "string", required: true, description: "Text to extract entities and relations from" },
              source_label: { type: "string", required: false, description: "Label for the extraction source" }
            }
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
        rescued_error_result(e)
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
        rescued_error_result(e)
      end

      def get_node(params)
        return { success: false, error: "node_id is required" } if params[:node_id].blank?

        node = graph_service.find_node!(params[:node_id])
        { success: true, node: serialize_node(node) }
      rescue Ai::KnowledgeGraph::GraphServiceError => e
        { success: false, error: e.message }
      rescue StandardError => e
        rescued_error_result(e)
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
        rescued_error_result(e)
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
        rescued_error_result(e)
      end

      def get_statistics
        stats = graph_service.statistics
        { success: true, **stats }
      rescue StandardError => e
        rescued_error_result(e)
      end

      def get_subgraph(params)
        node_ids = Array(params[:node_ids])
        return { success: false, error: "node_ids is required (array of node IDs)" } if node_ids.empty?

        result = graph_service.subgraph(node_ids: node_ids)
        { success: true, **result }
      rescue StandardError => e
        rescued_error_result(e)
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
        rescued_error_result(e)
      rescue StandardError => e
        rescued_error_result(e)
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
