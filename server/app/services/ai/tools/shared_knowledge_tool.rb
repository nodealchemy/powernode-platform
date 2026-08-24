# frozen_string_literal: true

module Ai
  module Tools
    class SharedKnowledgeTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      # === Per-action permission gating (G4) ===
      #
      # This tool bundled WRITE and DESTRUCTIVE actions behind a single coarse
      # REQUIRED_PERMISSION of "ai.agents.read", and performed no check of its
      # own — so holding a READ permission was sufficient to run every one of
      # them. Proven by execution before the fix, with row oracles rather than
      # error strings.
      #
      # REST twin: TieredMemoryController gates the SharedKnowledge reads
      # (`shared_knowledge`) on ai.memory.read and every write arm
      # (`shared_maintenance`, `consolidate_entry`) on ai.memory.write
      # (tiered_memory_controller.rb:186-193).
      #
      # Keyed on the action that RUNS, never on the invoked NAME: a user
      # principal is deliberately not pinned to the tool name
      # (McpPlatformToolRegistrar#action_pinned_to_name?), so a name-keyed check
      # is bypassable by supplying a sibling :action.
      ACTION_PERMISSIONS = {
        "create_knowledge" => "ai.memory.write",
        "update_knowledge" => "ai.memory.write",
        "promote_knowledge" => "ai.memory.write",
        "delete_knowledge" => "ai.memory.write"
      }.freeze


      def self.definition
        {
          name: "shared_knowledge",
          description: "Search, create, update, promote, or delete shared knowledge entries",
          parameters: {
            action: { type: "string", required: true, description: "Action: search_knowledge, create_knowledge, update_knowledge, promote_knowledge, delete_knowledge" },
            entry_id: { type: "string", required: false, description: "Knowledge entry ID (for update/promote/delete)" },
            query: { type: "string", required: false, description: "Search query" },
            title: { type: "string", required: false, description: "Entry title (for create/update)" },
            content: { type: "string", required: false, description: "Entry content (for create/update)" },
            content_type: { type: "string", required: false, description: "Content type: text/markdown/code/snippet/procedure/reference/fact/definition/guide (default: text)" },
            access_level: { type: "string", required: false, description: "Access level: private/team/account/global (for create/promote)" },
            tags: { type: "array", required: false, description: "Tags array (for create/update, or as a filter for search_knowledge)" },
            limit: { type: "integer", required: false, description: "Max results (default 10)" }
          }
        }
      end

      def self.action_definitions
        {
          "search_knowledge" => {
            description: "Search shared knowledge entries using semantic and keyword search",
            parameters: {
              query: { type: "string", required: true, description: "Search query" },
              content_type: { type: "string", required: false, description: "Filter by content type" },
              access_level: { type: "string", required: false, description: "Filter by access level" },
              tags: { type: "array", required: false, description: "Filter by tags (matches any of the given tags)" },
              limit: { type: "integer", required: false, description: "Max results (default 10)" }
            }
          },
          "create_knowledge" => {
            description: "Create a new shared knowledge entry",
            parameters: {
              title: { type: "string", required: true, description: "Entry title" },
              content: { type: "string", required: true, description: "Entry content" },
              content_type: { type: "string", required: false, description: "Content type: text/markdown/code/snippet/procedure/reference/fact/definition/guide (default: text)" },
              access_level: { type: "string", required: false, description: "Access level (default: team)" },
              tags: { type: "array", required: false, description: "Tags array" }
            }
          },
          "update_knowledge" => {
            description: "Update an existing shared knowledge entry",
            parameters: {
              entry_id: { type: "string", required: true, description: "Knowledge entry ID" },
              content: { type: "string", required: false, description: "Updated content" },
              access_level: { type: "string", required: false, description: "Updated access level" },
              tags: { type: "array", required: false, description: "Updated tags" }
            }
          },
          "promote_knowledge" => {
            description: "Promote a shared knowledge entry to a higher access level",
            parameters: {
              entry_id: { type: "string", required: true, description: "Knowledge entry ID to promote" },
              access_level: { type: "string", required: false, description: "Target access level (auto-determined if omitted)" }
            }
          },
          "delete_knowledge" => {
            description: "Delete (archive) a shared knowledge entry. Soft-deletes by default; use hard_delete: true to permanently remove.",
            parameters: {
              entry_id: { type: "string", required: true, description: "Knowledge entry ID to delete" },
              hard_delete: { type: "boolean", required: false, description: "Permanently destroy instead of archiving (default: false)" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[SharedKnowledgeTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case params[:action]
        when "search_knowledge" then search_knowledge(params)
        when "create_knowledge" then create_knowledge(params)
        when "update_knowledge" then update_knowledge(params)
        when "promote_knowledge" then promote_knowledge(params)
        when "delete_knowledge" then delete_knowledge(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def knowledge_service
        @knowledge_service ||= Ai::Memory::SharedKnowledgeService.new(account: account)
      end

      # Coerce a tags parameter into a real Array of tag strings.
      #
      # The schema declares `tags` as an array, but over MCP the value arrives
      # as a JSON-encoded STRING. `Array("[\"alpha\"]")` yields the literal text
      # as ONE element, which silently matches nothing on search — and on
      # create/update PERSISTS that bogus single tag. Found in production
      # 2026-08-02: the filter worked in-process and was inert over MCP, which
      # is the only path the guidance actually tells callers to use.
      #
      # A bare string that is not JSON is treated as a single tag, so
      # `tags: "guidance-backend-patterns"` behaves the way a caller expects.
      def normalize_tags(raw)
        case raw
        when Array
          raw.map { |t| t.to_s.strip }.reject(&:blank?)
        when String
          text = raw.strip
          return [] if text.blank?

          if text.start_with?("[")
            begin
              return Array(JSON.parse(text)).map { |t| t.to_s.strip }.reject(&:blank?)
            rescue JSON::ParserError
              # Not valid JSON after all — fall through and treat it as one tag.
            end
          end
          [ text ]
        else
          Array(raw).map { |t| t.to_s.strip }.reject(&:blank?)
        end
      end

      def search_knowledge(params)
        return { success: false, error: "Query is required" } if params[:query].blank?

        result = knowledge_service.search(
          query: params[:query],
          content_type: params[:content_type],
          access_level: params[:access_level],
          tags: normalize_tags(params[:tags]),
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
          tags: normalize_tags(params[:tags]),
          source_type: "agent"
        )

        result
      end

      def update_knowledge(params)
        return { success: false, error: "entry_id is required" } if params[:entry_id].blank?

        attrs = {}
        attrs[:content] = params[:content] if params[:content].present?
        attrs[:tags] = normalize_tags(params[:tags]) if params[:tags].present?
        attrs[:access_level] = params[:access_level] if params[:access_level].present?

        result = knowledge_service.update(entry_id: params[:entry_id], **attrs)
        result
      end

      def promote_knowledge(params)
        return { success: false, error: "entry_id is required" } if params[:entry_id].blank?

        new_level = params[:access_level] || next_access_level(params[:entry_id])
        return { success: false, error: "Could not determine promotion level" } unless new_level

        result = knowledge_service.promote(entry_id: params[:entry_id], new_access_level: new_level)
        result
      end

      def delete_knowledge(params)
        return { success: false, error: "entry_id is required" } if params[:entry_id].blank?

        if params[:hard_delete] == true
          entry = Ai::SharedKnowledge.find_by(id: params[:entry_id], account: account)
          return { success: false, error: "Knowledge entry not found: #{params[:entry_id]}" } unless entry

          entry.destroy!
          Rails.logger.info("[SharedKnowledge] Hard-deleted entry #{params[:entry_id]}")
          { success: true, entry_id: params[:entry_id], deleted: true, method: "hard_delete" }
        else
          result = knowledge_service.archive(entry_id: params[:entry_id])
          result[:method] = "archived" if result[:success]
          result
        end
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Knowledge entry not found: #{params[:entry_id]}" }
      end

      def next_access_level(entry_id)
        entry = Ai::SharedKnowledge.find_by(id: entry_id, account: account)
        return nil unless entry

        levels = %w[private team account global]
        current_index = levels.index(entry.access_level) || 0
        levels[current_index + 1]
      end

      # Falls back to the class floor for read actions, which the registrar has
      # already enforced by the time this runs.
      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two explicit bypasses, matching the sibling tools' ladder: in-process
      # callers that opted in with `internal: true`, and an mTLS node principal
      # whose specific tool name already cleared Mcp::Principal#may_invoke?.
      # Never inferred from a nil user.
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the
        # MCP path coerces a permission answer.
        user.has_permission?(required_perm_for(action)) == true
      end

    end
  end
end
