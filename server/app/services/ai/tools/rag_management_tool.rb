# frozen_string_literal: true

module Ai
  module Tools
    class RagManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.knowledge.manage"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "add_document", mutating: true,
                                     returns: "the document's id, name, knowledge_base_id, source_type, content_type, status, " \
                                              "chunk_count, token_count, content_size_bytes and created_at",
                                     refuses: [ "knowledge_base_id, name or content is blank",
                                                "the knowledge base is not owned by this account" ],
                                     see_also: { "process_document" => "chunking and embedding the stored document" }
      declare_action "create_knowledge_base", mutating: true,
                                              returns: "the knowledge base's id, name, description, status, counts, embedding_model, " \
                                                       "chunking_strategy and created_at",
                                              refuses: [ "name is blank, or the record fails validation",
                                                         "no active provider in the account lists a text_embedding model in its catalog" ]
      declare_action "delete_document", mutating: true, destructive: true,
                                        returns: "a confirmation message",
                                        refuses: [ "knowledge_base_id or document_id is blank",
                                                   "the document is not in that knowledge base, or the knowledge base is not owned by this account" ]
      declare_action "list_knowledge_bases", mutating: false,
                                             returns: "count and knowledge bases newest first (id, name, description, status, " \
                                                      "document, chunk and token counts, embedding_model, chunking_strategy, created_at)",
                                             see_also: { "query_knowledge_base" => "searching the documents in one knowledge base" }
      declare_action "process_document", mutating: true,
                                         returns: "the reloaded document, chunks_created and chunks_embedded",
                                         refuses: [ "knowledge_base_id or document_id is blank",
                                                    "the document is not in that knowledge base, or the knowledge base is not owned by this account",
                                                    "no embedding provider is available" ]

      def self.definition
        {
          name: "rag_management",
          description: "Manage RAG knowledge bases and documents. Actions: list_knowledge_bases, create_knowledge_base, add_document, process_document, delete_document. To search a knowledge base, use query_knowledge_base.",
          parameters: {
            action: { type: "string", required: true, description: "Action: list_knowledge_bases, create_knowledge_base, add_document, process_document, delete_document" },
            knowledge_base_id: { type: "string", required: false, description: "Knowledge base ID" },
            name: { type: "string", required: false, description: "Name for KB or document" },
            description: { type: "string", required: false, description: "Description for KB" },
            content: { type: "string", required: false, description: "Document content" },
            content_type: { type: "string", required: false, description: "Document content type (default: text/plain)" },
            source_url: { type: "string", required: false, description: "Source URL for document" },
            document_id: { type: "string", required: false, description: "Document ID" }
          }
        }
      end

      def self.action_definitions
        {
          "list_knowledge_bases" => {
            description: "List all RAG knowledge bases in the current account.",
            parameters: {}
          },
          "create_knowledge_base" => {
            description: "Create a new RAG knowledge base for document storage and retrieval. " \
                         "It is created with recursive chunking, chunk_size 1000 and chunk_overlap 200. " \
                         "Its embedding model is the first text_embedding model in the catalog of the " \
                         "account's highest-priority active embedding provider.",
            parameters: {
              name: { type: "string", required: true, description: "Knowledge base name" },
              description: { type: "string", required: false, description: "Knowledge base description" }
            }
          },
          "add_document" => {
            description: "Add a document to a RAG knowledge base. " \
                         "The document is stored without chunks, and searches read chunks, so it is not searchable until process_document runs.",
            parameters: {
              knowledge_base_id: { type: "string", required: true, description: "Knowledge base ID" },
              name: { type: "string", required: true, description: "Document name" },
              content: { type: "string", required: true, description: "Document content" },
              content_type: { type: "string", required: false, description: "Content type (default: text/plain)" },
              source_url: { type: "string", required: false, description: "Source URL for the document" }
            }
          },
          "process_document" => {
            description: "Process a document: chunk and embed it for RAG retrieval. " \
                         "It uses the knowledge base's chunking settings and embeds only chunks that have no embedding yet. " \
                         "Processing a document again replaces its chunks.",
            parameters: {
              knowledge_base_id: { type: "string", required: true, description: "Knowledge base ID" },
              document_id: { type: "string", required: true, description: "Document ID to process" }
            }
          },
          "delete_document" => {
            description: "Delete a document from a RAG knowledge base",
            parameters: {
              knowledge_base_id: { type: "string", required: true, description: "Knowledge base ID" },
              document_id: { type: "string", required: true, description: "Document ID to delete" }
            }
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
        when "delete_document" then delete_document(params)
        else
          {
            success: false,
            error: "Unknown action: #{params[:action]}. Valid actions: list_knowledge_bases, create_knowledge_base, add_document, process_document, delete_document"
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
        rescued_error_result(e)
      end

      def create_knowledge_base(params)
        return { success: false, error: "name is required" } if params[:name].blank?

        rag_service = Ai::RagService.new(account)
        kb = rag_service.create_knowledge_base(
          {
            name: params[:name],
            description: params[:description],
            **rag_service.resolve_embedding_config,
            chunking_strategy: "recursive",
            chunk_size: 1000,
            chunk_overlap: 200
          },
          user: user
        )

        { success: true, knowledge_base: serialize_kb(kb) }
      rescue ActiveRecord::RecordInvalid, Ai::RagServiceError => e
        { success: false, error: e.message }
      rescue StandardError => e
        rescued_error_result(e)
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
        rescued_error_result(e)
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
        rescued_error_result(e, message: "Record not found")
      rescue StandardError => e
        rescued_error_result(e)
      end


      def delete_document(params)
        return { success: false, error: "knowledge_base_id is required" } if params[:knowledge_base_id].blank?
        return { success: false, error: "document_id is required" } if params[:document_id].blank?

        rag_service = Ai::RagService.new(account)
        rag_service.delete_document(params[:knowledge_base_id], params[:document_id])

        { success: true, message: "Document deleted successfully" }
      rescue ActiveRecord::RecordNotFound => e
        rescued_error_result(e, message: "Record not found")
      rescue StandardError => e
        rescued_error_result(e)
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
