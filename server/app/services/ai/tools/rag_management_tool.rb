# frozen_string_literal: true

module Ai
  module Tools
    class RagManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.knowledge.manage"

      def self.definition
        {
          name: "rag_management",
          description: "Manage RAG knowledge bases, documents, and search. Actions: list_knowledge_bases, create_knowledge_base, add_document, process_document, search_documents, delete_document",
          parameters: {
            action: { type: "string", required: true, description: "Action: list_knowledge_bases, create_knowledge_base, add_document, process_document, search_documents, delete_document" },
            knowledge_base_id: { type: "string", required: false, description: "Knowledge base ID" },
            name: { type: "string", required: false, description: "Name for KB or document" },
            description: { type: "string", required: false, description: "Description for KB" },
            content: { type: "string", required: false, description: "Document content" },
            content_type: { type: "string", required: false, description: "Document content type (default: text/plain)" },
            source_url: { type: "string", required: false, description: "Source URL for document" },
            document_id: { type: "string", required: false, description: "Document ID" },
            query: { type: "string", required: false, description: "Search query" },
            mode: { type: "string", required: false, description: "Search mode: hybrid, vector, keyword, graph (default: hybrid)" },
            top_k: { type: "integer", required: false, description: "Max results (default 5)" }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "list_knowledge_bases" then list_knowledge_bases
        when "create_knowledge_base" then create_knowledge_base(params)
        when "add_document" then add_document(params)
        when "process_document" then process_document(params)
        when "search_documents" then search_documents(params)
        when "delete_document" then delete_document(params)
        else
          {
            success: false,
            error: "Unknown action: #{params[:action]}. Valid actions: list_knowledge_bases, create_knowledge_base, add_document, process_document, search_documents, delete_document"
          }
        end
      end

      private

      def list_knowledge_bases
        bases = account.ai_knowledge_bases.order(created_at: :desc)

        {
          success: true,
          count: bases.size,
          knowledge_bases: bases.map { |kb| serialize_kb(kb) }
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def create_knowledge_base(params)
        return { success: false, error: "name is required" } if params[:name].blank?

        rag_service = Ai::RagService.new(account)
        kb = rag_service.create_knowledge_base(
          {
            name: params[:name],
            description: params[:description],
            embedding_model: "text-embedding-3-small",
            embedding_provider: "openai",
            embedding_dimensions: 1536,
            chunking_strategy: "recursive",
            chunk_size: 1000,
            chunk_overlap: 200
          },
          user: user
        )

        { success: true, knowledge_base: serialize_kb(kb) }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def add_document(params)
        return { success: false, error: "knowledge_base_id is required" } if params[:knowledge_base_id].blank?
        return { success: false, error: "name is required" } if params[:name].blank?
        return { success: false, error: "content is required" } if params[:content].blank?

        rag_service = Ai::RagService.new(account)
        doc = rag_service.create_document(
          params[:knowledge_base_id],
          {
            name: params[:name],
            source_type: params[:source_url].present? ? "url" : "upload",
            source_url: params[:source_url],
            content_type: params[:content_type] || "text/plain",
            content: params[:content]
          },
          user: user
        )

        { success: true, document: serialize_document(doc) }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Knowledge base not found: #{params[:knowledge_base_id]}" }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def process_document(params)
        return { success: false, error: "knowledge_base_id is required" } if params[:knowledge_base_id].blank?
        return { success: false, error: "document_id is required" } if params[:document_id].blank?

        rag_service = Ai::RagService.new(account)

        # Process: chunk the document
        doc = rag_service.process_document(params[:knowledge_base_id], params[:document_id])

        # Embed the chunks
        embed_result = rag_service.embed_chunks(params[:knowledge_base_id], document_id: params[:document_id])

        {
          success: true,
          document: serialize_document(doc.reload),
          chunks_created: doc.chunk_count,
          chunks_embedded: embed_result[:embedded_count]
        }
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: "Record not found: #{e.message}" }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def search_documents(params)
        return { success: false, error: "query is required" } if params[:query].blank?

        top_k = (params[:top_k] || 5).to_i.clamp(1, 20)
        mode = params[:mode] || "hybrid"

        unless %w[hybrid vector keyword graph].include?(mode)
          return { success: false, error: "Invalid mode '#{mode}'. Valid: hybrid, vector, keyword, graph" }
        end

        kb_id = params[:knowledge_base_id]
        unless kb_id.present?
          kb = account.ai_knowledge_bases.active.order(created_at: :desc).first
          return { success: false, error: "No active knowledge bases found" } unless kb
          kb_id = kb.id
        end

        search_service = Ai::Rag::HybridSearchService.new(account)
        result = search_service.search(
          query: params[:query],
          mode: mode,
          top_k: top_k,
          knowledge_base_id: kb_id
        )

        formatted = (result[:results] || []).map do |r|
          doc = r[:document_id] ? Ai::Document.find_by(id: r[:document_id]) : nil
          {
            chunk_id: r[:id],
            content: r[:content].to_s.truncate(1000),
            score: r[:score],
            source: r[:source],
            document_name: doc&.name,
            document_id: r[:document_id]
          }
        end

        {
          success: true,
          query: params[:query],
          results_count: formatted.size,
          results: formatted,
          search_mode: mode
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def delete_document(params)
        return { success: false, error: "knowledge_base_id is required" } if params[:knowledge_base_id].blank?
        return { success: false, error: "document_id is required" } if params[:document_id].blank?

        rag_service = Ai::RagService.new(account)
        rag_service.delete_document(params[:knowledge_base_id], params[:document_id])

        { success: true, message: "Document deleted successfully" }
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: "Record not found: #{e.message}" }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def serialize_kb(kb)
        {
          id: kb.id,
          name: kb.name,
          description: kb.description,
          status: kb.status,
          document_count: kb.document_count,
          chunk_count: kb.chunk_count,
          total_tokens: kb.total_tokens,
          embedding_model: kb.embedding_model,
          chunking_strategy: kb.chunking_strategy,
          created_at: kb.created_at&.iso8601
        }
      end

      def serialize_document(doc)
        {
          id: doc.id,
          name: doc.name,
          knowledge_base_id: doc.knowledge_base_id,
          source_type: doc.source_type,
          content_type: doc.content_type,
          status: doc.status,
          chunk_count: doc.chunk_count,
          token_count: doc.token_count,
          content_size_bytes: doc.content_size_bytes,
          created_at: doc.created_at&.iso8601
        }
      end
    end
  end
end
