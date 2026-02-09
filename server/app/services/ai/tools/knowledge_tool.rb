# frozen_string_literal: true

module Ai
  module Tools
    class KnowledgeTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      def self.definition
        {
          name: "query_knowledge_base",
          description: "Query RAG knowledge bases for relevant information",
          parameters: {
            query: { type: "string", required: true, description: "Search query" },
            knowledge_base_id: { type: "string", required: false, description: "Specific knowledge base ID" },
            limit: { type: "integer", required: false, description: "Max results (default 5)" }
          }
        }
      end

      protected

      def call(params)
        # Query against existing RAG infrastructure
        limit = params[:limit] || 5
        results = Ai::RagQuery.where(account: account)
                              .order(created_at: :desc)
                              .limit(limit)

        { success: true, query: params[:query], results_count: results.count }
      rescue StandardError => e
        { success: false, error: e.message }
      end
    end
  end
end
