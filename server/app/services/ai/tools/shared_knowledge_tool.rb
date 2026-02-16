# frozen_string_literal: true

module Ai
  module Tools
    class SharedKnowledgeTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      def self.definition
        {
          name: "shared_knowledge",
          description: "Search, create, update, or promote shared knowledge entries",
          parameters: {
            action: { type: "string", required: true, description: "Action: search_knowledge, create_knowledge, update_knowledge, promote_knowledge" },
            entry_id: { type: "string", required: false, description: "Knowledge entry ID (for update/promote)" },
            query: { type: "string", required: false, description: "Search query" },
            title: { type: "string", required: false, description: "Entry title (for create/update)" },
            content: { type: "string", required: false, description: "Entry content (for create/update)" },
            content_type: { type: "string", required: false, description: "Content type: text/markdown/code/snippet/procedure/fact/definition" },
            access_level: { type: "string", required: false, description: "Access level: private/team/account/global (for create/promote)" },
            tags: { type: "array", required: false, description: "Tags array (for create/update)" },
            limit: { type: "integer", required: false, description: "Max results (default 10)" }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "search_knowledge" then search_knowledge(params)
        when "create_knowledge" then create_knowledge(params)
        when "update_knowledge" then update_knowledge(params)
        when "promote_knowledge" then promote_knowledge(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def knowledge_service
        @knowledge_service ||= Ai::Memory::SharedKnowledgeService.new(account: account)
      end

      def search_knowledge(params)
        return { success: false, error: "Query is required" } if params[:query].blank?

        result = knowledge_service.search(
          query: params[:query],
          content_type: params[:content_type],
          access_level: params[:access_level],
          limit: (params[:limit] || 10).to_i.clamp(1, 50)
        )

        result
      end

      def create_knowledge(params)
        result = knowledge_service.create(
          title: params[:title],
          content: params[:content],
          content_type: params[:content_type] || "text",
          access_level: params[:access_level] || "team",
          tags: Array(params[:tags]),
          source_type: "agent"
        )

        result
      end

      def update_knowledge(params)
        return { success: false, error: "entry_id is required" } if params[:entry_id].blank?

        attrs = {}
        attrs[:content] = params[:content] if params[:content].present?
        attrs[:tags] = Array(params[:tags]) if params[:tags].present?
        attrs[:access_level] = params[:access_level] if params[:access_level].present?

        result = knowledge_service.update(params[:entry_id], **attrs)
        result
      end

      def promote_knowledge(params)
        return { success: false, error: "entry_id is required" } if params[:entry_id].blank?

        new_level = params[:access_level] || next_access_level(params[:entry_id])
        return { success: false, error: "Could not determine promotion level" } unless new_level

        result = knowledge_service.promote(params[:entry_id], new_access_level: new_level)
        result
      end

      def next_access_level(entry_id)
        entry = Ai::SharedKnowledge.find_by(id: entry_id, account: account)
        return nil unless entry

        levels = %w[private team account global]
        current_index = levels.index(entry.access_level) || 0
        levels[current_index + 1]
      end
    end
  end
end
