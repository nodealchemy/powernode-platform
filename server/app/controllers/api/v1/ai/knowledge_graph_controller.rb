# frozen_string_literal: true

module Api
  module V1
    module Ai
      class KnowledgeGraphController < ApplicationController
        before_action :authenticate_request

        # ============================================================================
        # NODES
        # ============================================================================

        # GET /api/v1/ai/knowledge_graph/nodes
        def nodes
          service = graph_service
          nodes = service.list_nodes(node_filter_params)

          render_success(
            nodes: nodes.map { |n| serialize_node(n) },
            total_count: nodes.respond_to?(:total_count) ? nodes.total_count : nodes.size
          )
        end

        # GET /api/v1/ai/knowledge_graph/nodes/:id
        def show_node
          node = graph_service.find_node!(params[:id])
          render_success(node: serialize_node(node, detailed: true))
        rescue ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :not_found)
        end

        # POST /api/v1/ai/knowledge_graph/nodes
        def create_node
          node = graph_service.create_node(**node_params.to_h.symbolize_keys)
          render_success(node: serialize_node(node), status: :created)
        rescue ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH /api/v1/ai/knowledge_graph/nodes/:id
        def update_node
          node = graph_service.update_node(params[:id], **node_update_params.to_h.symbolize_keys)
          render_success(node: serialize_node(node))
        rescue ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/knowledge_graph/nodes/:id
        def destroy_node
          graph_service.delete_node(params[:id])
          render_success(deleted: true)
        rescue ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :not_found)
        end

        # ============================================================================
        # EDGES
        # ============================================================================

        # GET /api/v1/ai/knowledge_graph/edges
        def edges
          edge_list = graph_service.list_edges(edge_filter_params)
          render_success(
            edges: edge_list.map { |e| serialize_edge(e) }
          )
        end

        # POST /api/v1/ai/knowledge_graph/edges
        def create_edge
          edge = graph_service.create_edge(**edge_params.to_h.symbolize_keys)
          render_success(edge: serialize_edge(edge), status: :created)
        rescue ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/knowledge_graph/edges/:id
        def destroy_edge
          graph_service.delete_edge(params[:id])
          render_success(deleted: true)
        rescue ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :not_found)
        end

        # ============================================================================
        # GRAPH TRAVERSAL
        # ============================================================================

        # GET /api/v1/ai/knowledge_graph/nodes/:id/neighbors
        def neighbors
          depth = params[:depth]&.to_i || 1
          relation_types = params[:relation_types]

          result = graph_service.find_neighbors(
            node: params[:id],
            depth: depth,
            relation_types: relation_types
          )

          render_success(neighbors: result, count: result.size)
        rescue ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :not_found)
        end

        # GET /api/v1/ai/knowledge_graph/shortest_path
        def shortest_path
          path = graph_service.shortest_path(
            source: params[:source_id],
            target: params[:target_id],
            max_depth: params[:max_depth]&.to_i || 5
          )

          if path
            render_success(
              path: path.map { |e| serialize_edge(e) },
              length: path.size
            )
          else
            render_success(path: [], length: 0, message: "No path found")
          end
        rescue ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :not_found)
        end

        # POST /api/v1/ai/knowledge_graph/subgraph
        def subgraph
          node_ids = params[:node_ids]
          return render_error("node_ids required", status: :bad_request) if node_ids.blank?

          result = graph_service.subgraph(
            node_ids: node_ids,
            include_edges: params.fetch(:include_edges, true)
          )

          render_success(result)
        end

        # ============================================================================
        # EXTRACTION & REASONING
        # ============================================================================

        # POST /api/v1/ai/knowledge_graph/extract
        def extract
          document_id = params[:document_id]
          return render_error("document_id required", status: :bad_request) if document_id.blank?

          document = ::Ai::Document.find(document_id)
          extraction_service = ::Ai::KnowledgeGraph::ExtractionService.new(current_account)
          result = extraction_service.extract_from_document(document: document)

          render_success(
            nodes_created: result[:stats][:nodes_created],
            nodes_existing: result[:stats][:nodes_existing],
            edges_created: result[:stats][:edges_created],
            edges_existing: result[:stats][:edges_existing],
            nodes: result[:nodes].map { |n| serialize_node(n) },
            edges: result[:edges].map { |e| serialize_edge(e) }
          )
        rescue ActiveRecord::RecordNotFound
          render_error("Document not found", status: :not_found)
        rescue ::Ai::KnowledgeGraph::ExtractionServiceError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/ai/knowledge_graph/statistics
        def statistics
          stats = graph_service.statistics
          render_success(stats)
        end

        # POST /api/v1/ai/knowledge_graph/reason
        def multi_hop_reason
          query = params[:query]
          return render_error("query required", status: :bad_request) if query.blank?

          reasoning_service = ::Ai::KnowledgeGraph::MultiHopReasoningService.new(current_account)
          result = reasoning_service.reason(
            query: query,
            max_hops: params[:max_hops]&.to_i || 3,
            top_k: params[:top_k]&.to_i || 5
          )

          render_success(result)
        end

        # POST /api/v1/ai/knowledge_graph/search
        def hybrid_search
          query = params[:query]
          return render_error("query required", status: :bad_request) if query.blank?

          hybrid_service = ::Ai::Rag::HybridSearchService.new(current_account)
          result = hybrid_service.search(
            query: query,
            mode: params[:mode] || :hybrid,
            top_k: params[:top_k]&.to_i || 10,
            knowledge_base_id: params[:knowledge_base_id],
            fusion_method: params[:fusion_method]
          )

          # Optionally rerank
          if params[:rerank]
            reranking_service = ::Ai::Rag::RerankingService.new(current_account)
            result[:results] = reranking_service.rerank(
              query: query,
              results: result[:results],
              top_k: params[:top_k]&.to_i
            )
          end

          render_success(result)
        rescue ::Ai::Rag::HybridSearchServiceError => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def graph_service
          @graph_service ||= ::Ai::KnowledgeGraph::GraphService.new(current_account)
        end

        def node_filter_params
          params.permit(:node_type, :entity_type, :query, :knowledge_base_id, :page, :per_page)
        end

        def node_params
          params.permit(:name, :node_type, :entity_type, :description, :confidence,
                        :knowledge_base_id, :source_document_id, properties: {}, metadata: {})
        end

        def node_update_params
          params.permit(:name, :description, :entity_type, :confidence, :status,
                        properties: {}, metadata: {})
        end

        def edge_params
          permitted = params.permit(:relation_type, :label, :weight, :confidence,
                                    :bidirectional, :source_document_id, properties: {}, metadata: {})
          # Map source/target from request params
          permitted[:source] = params[:source_node_id] if params[:source_node_id]
          permitted[:target] = params[:target_node_id] if params[:target_node_id]
          permitted
        end

        def edge_filter_params
          params.permit(:relation_type, :node_id)
        end

        def serialize_node(node, detailed: false)
          data = {
            id: node.id,
            name: node.name,
            node_type: node.node_type,
            entity_type: node.entity_type,
            description: node.description,
            confidence: node.confidence,
            mention_count: node.mention_count,
            status: node.status,
            created_at: node.created_at
          }

          if detailed
            data[:properties] = node.properties
            data[:metadata] = node.metadata
            data[:knowledge_base_id] = node.knowledge_base_id
            data[:source_document_id] = node.source_document_id
            data[:last_seen_at] = node.last_seen_at
            data[:merged_into_id] = node.merged_into_id
            data[:degree] = node.degree
          end

          data
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
            status: edge.status,
            created_at: edge.created_at
          }
        end
      end
    end
  end
end
