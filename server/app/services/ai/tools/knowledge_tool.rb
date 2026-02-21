# frozen_string_literal: true

module Ai
  module Tools
    class KnowledgeTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      def self.definition
        {
          name: "query_knowledge_base",
          description: "Search RAG knowledge bases for relevant documents using hybrid semantic + keyword search",
          parameters: {
            query: { type: "string", required: true, description: "Search query" },
            knowledge_base_id: { type: "string", required: false, description: "Specific knowledge base ID (searches first available if omitted)" },
            mode: { type: "string", required: false, description: "Search mode: hybrid (default), vector, keyword, graph" },
            top_k: { type: "integer", required: false, description: "Max results (default 5, max 20)" }
          }
        }
      end

      protected

      def call(params)
        query = params[:query]
        top_k = (params[:top_k] || 5).to_i.clamp(1, 20)
        mode = params[:mode] || "hybrid"

        unless %w[hybrid vector keyword graph].include?(mode)
          return { success: false, error: "Invalid mode '#{mode}'. Valid: hybrid, vector, keyword, graph" }
        end

        # Resolve knowledge base
        kb = resolve_knowledge_base(params[:knowledge_base_id])
        return kb if kb.is_a?(Hash) && kb[:success] == false

        # Perform hybrid search
        search_service = Ai::Rag::HybridSearchService.new(account)
        result = search_service.search(
          query: query,
          mode: mode,
          top_k: top_k,
          knowledge_base_id: kb.id
        )

        # Log the query for analytics
        log_rag_query(kb, query, result)

        # Format results for agent consumption
        formatted_results = (result[:results] || []).map do |r|
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
          query: query,
          knowledge_base: { id: kb.id, name: kb.name },
          results_count: formatted_results.size,
          results: formatted_results,
          search_mode: mode,
          metadata: result[:metadata]
        }
      rescue StandardError => e
        Rails.logger.error "[KnowledgeTool] Search failed: #{e.message}"
        { success: false, error: e.message }
      end

      private

      def resolve_knowledge_base(kb_id)
        if kb_id.present?
          kb = account.ai_knowledge_bases.active.find_by(id: kb_id)
          return { success: false, error: "Knowledge base not found: #{kb_id}" } unless kb
          kb
        else
          kb = account.ai_knowledge_bases.active.order(created_at: :desc).first
          unless kb
            return {
              success: false,
              error: "No active knowledge bases found. Create one first using the 'create_knowledge_base' tool."
            }
          end
          kb
        end
      end

      def log_rag_query(kb, query, result)
        Ai::RagQuery.create!(
          account: account,
          knowledge_base: kb,
          user: user,
          query_text: query,
          retrieval_strategy: "hybrid",
          top_k: result[:results]&.size || 0,
          status: "completed",
          chunks_retrieved: result[:results]&.size || 0,
          query_latency_ms: result.dig(:metadata, :latency_ms)
        )
      rescue StandardError => e
        Rails.logger.warn "[KnowledgeTool] Failed to log query: #{e.message}"
      end
    end
  end
end
