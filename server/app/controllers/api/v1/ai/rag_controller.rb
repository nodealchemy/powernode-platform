# frozen_string_literal: true

module Api
  module V1
    module Ai
      class RagController < ApplicationController
        before_action :authenticate_request
        before_action :set_rag_service
        before_action :set_knowledge_base, only: %i[
          show_knowledge_base update_knowledge_base delete_knowledge_base
          list_documents create_document show_document delete_document process_document
          embed_chunks query query_history
          list_connectors create_connector sync_connector
          analytics
        ]

        # ============================================================================
        # KNOWLEDGE BASES
        # ============================================================================

        # GET /api/v1/ai/rag/knowledge_bases
        def index
          bases = @rag_service.list_knowledge_bases(filter_params)

          render_success(
            knowledge_bases: bases.map { |kb| serialize_knowledge_base(kb) },
            total_count: bases.total_count
          )
        end

        # GET /api/v1/ai/rag/knowledge_bases/:id
        def show_knowledge_base
          render_success(serialize_knowledge_base(@knowledge_base, detailed: true))
        end

        # POST /api/v1/ai/rag/knowledge_bases
        def create_knowledge_base
          kb = @rag_service.create_knowledge_base(knowledge_base_params, user: current_user)
          render_success(serialize_knowledge_base(kb), status: :created)
        end

        # PATCH /api/v1/ai/rag/knowledge_bases/:id
        def update_knowledge_base
          kb = @rag_service.update_knowledge_base(@knowledge_base.id, knowledge_base_params)
          render_success(serialize_knowledge_base(kb))
        end

        # DELETE /api/v1/ai/rag/knowledge_bases/:id
        def delete_knowledge_base
          @rag_service.delete_knowledge_base(@knowledge_base.id)
          render_success(success: true)
        end

        # ============================================================================
        # DOCUMENTS
        # ============================================================================

        # GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents
        def list_documents
          docs = @rag_service.list_documents(@knowledge_base.id, filter_params)

          render_success(
            documents: docs.map { |d| serialize_document(d) },
            total_count: docs.total_count
          )
        end

        # POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents
        def create_document
          doc = @rag_service.create_document(@knowledge_base.id, document_params, user: current_user)
          render_success(serialize_document(doc), status: :created)
        end

        # GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents/:id
        def show_document
          doc = @rag_service.get_document(@knowledge_base.id, params[:id])
          render_success(serialize_document(doc, detailed: true))
        end

        # DELETE /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents/:id
        def delete_document
          @rag_service.delete_document(@knowledge_base.id, params[:id])
          render_success(success: true)
        end

        # POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents/:id/process
        def process_document
          doc = @rag_service.process_document(@knowledge_base.id, params[:id])
          render_success(serialize_document(doc, detailed: true))
        end

        # ============================================================================
        # EMBEDDINGS
        # ============================================================================

        # POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/embed
        def embed_chunks
          result = @rag_service.embed_chunks(@knowledge_base.id, document_id: params[:document_id])
          render_success(result)
        end

        # ============================================================================
        # QUERIES
        # ============================================================================

        # POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/query
        def query
          result = @rag_service.query(@knowledge_base.id, query_params, user: current_user)
          render_success(result)
        end

        # GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/query_history
        def query_history
          queries = @rag_service.get_query_history(@knowledge_base.id, filter_params)

          render_success(
            queries: queries.map { |q| serialize_query(q) },
            total_count: queries.total_count
          )
        end

        # ============================================================================
        # DATA CONNECTORS
        # ============================================================================

        # GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/connectors
        def list_connectors
          connectors = @rag_service.list_connectors(@knowledge_base.id)
          render_success(connectors: connectors.map { |c| serialize_connector(c) })
        end

        # POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/connectors
        def create_connector
          connector = @rag_service.create_connector(@knowledge_base.id, connector_params, user: current_user)
          render_success(serialize_connector(connector), status: :created)
        end

        # POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/connectors/:id/sync
        def sync_connector
          result = @rag_service.sync_connector(@knowledge_base.id, params[:id])
          render_success(result)
        end

        # ============================================================================
        # ANALYTICS
        # ============================================================================

        # GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/analytics
        def analytics
          period_days = params[:period_days]&.to_i || 30
          analytics = @rag_service.get_analytics(@knowledge_base.id, period_days: period_days)
          render_success(analytics)
        end

        private

        def set_rag_service
          @rag_service = ::Ai::RagService.new(current_account)
        end

        def set_knowledge_base
          @knowledge_base = @rag_service.get_knowledge_base(params[:knowledge_base_id] || params[:id])
        end

        def filter_params
          params.permit(:status, :source_type, :is_public, :page, :per_page)
        end

        def knowledge_base_params
          params.permit(
            :name, :description, :embedding_model, :embedding_provider,
            :embedding_dimensions, :chunking_strategy, :chunk_size,
            :chunk_overlap, :is_public, metadata_schema: {}, settings: {}
          )
        end

        def document_params
          params.permit(
            :name, :source_type, :source_url, :content_type, :content,
            :expires_at, metadata: {}, extraction_config: {}
          )
        end

        def query_params
          params.permit(
            :query, :strategy, :top_k, :threshold,
            :workflow_run_id, :agent_execution_id, filters: {}
          )
        end

        def connector_params
          params.permit(
            :name, :connector_type, :sync_frequency,
            connection_config: {}, sync_config: {}
          )
        end

        def serialize_knowledge_base(kb, detailed: false)
          data = {
            id: kb.id,
            name: kb.name,
            description: kb.description,
            status: kb.status,
            embedding_model: kb.embedding_model,
            embedding_provider: kb.embedding_provider,
            chunking_strategy: kb.chunking_strategy,
            chunk_size: kb.chunk_size,
            chunk_overlap: kb.chunk_overlap,
            is_public: kb.is_public,
            document_count: kb.document_count,
            chunk_count: kb.chunk_count,
            total_tokens: kb.total_tokens,
            storage_bytes: kb.storage_bytes,
            last_indexed_at: kb.last_indexed_at,
            last_queried_at: kb.last_queried_at,
            created_at: kb.created_at
          }

          if detailed
            data[:metadata_schema] = kb.metadata_schema
            data[:settings] = kb.settings
            data[:embedding_dimensions] = kb.embedding_dimensions
          end

          data
        end

        def serialize_document(doc, detailed: false)
          data = {
            id: doc.id,
            name: doc.name,
            source_type: doc.source_type,
            source_url: doc.source_url,
            content_type: doc.content_type,
            status: doc.status,
            chunk_count: doc.chunk_count,
            token_count: doc.token_count,
            content_size_bytes: doc.content_size_bytes,
            processed_at: doc.processed_at,
            created_at: doc.created_at
          }

          if detailed
            data[:metadata] = doc.metadata
            data[:processing_errors] = doc.processing_errors
            data[:checksum] = doc.checksum
          end

          data
        end

        def serialize_query(query)
          {
            id: query.id,
            query_text: query.query_text,
            retrieval_strategy: query.retrieval_strategy,
            status: query.status,
            chunks_retrieved: query.chunks_retrieved,
            avg_similarity_score: query.avg_similarity_score,
            query_latency_ms: query.query_latency_ms,
            created_at: query.created_at
          }
        end

        def serialize_connector(connector)
          {
            id: connector.id,
            name: connector.name,
            connector_type: connector.connector_type,
            status: connector.status,
            sync_frequency: connector.sync_frequency,
            documents_synced: connector.documents_synced,
            sync_errors: connector.sync_errors,
            last_sync_at: connector.last_sync_at,
            next_sync_at: connector.next_sync_at,
            created_at: connector.created_at
          }
        end
      end
    end
  end
end
