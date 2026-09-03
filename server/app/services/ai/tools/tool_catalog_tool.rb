# frozen_string_literal: true

module Ai
  module Tools
    # platform.describe_tool — the on-demand half of the one-line tools/list
    # (IMP-7e84ae0ccc91, operator ruling R4 amended 2026-09-03).
    #
    # tools/list carries the first sentence of every description, capped at
    # Mcp::ToolCatalog::LIST_DESCRIPTION_LIMIT; this returns the FULL entry
    # for one tool, built by the SAME Mcp::ToolCatalog the listing uses, so
    # the two can never drift. Read-only: it inspects the advertised catalog
    # and touches nothing.
    class ToolCatalogTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      declare_action "describe_tool", mutating: false

      def self.definition
        {
          name: "describe_tool",
          # KEEP THE FIRST SENTENCE SELF-CONTAINED AND UNDER
          # Mcp::ToolCatalog::LIST_DESCRIPTION_LIMIT. It is the only text a
          # client sees for the verb the whole one-line-listing design depends
          # on, and Mcp::ToolCatalog.summarize would otherwise word-cut it
          # mid-clause. Every later sentence must start upper-case, or the
          # sentence splitter runs them into the first one.
          # (tool_catalog_spec.rb "keeps its own listed summary self-contained
          # under the cap" pins both properties.)
          description: "Return the full tools/list entry for one tool by its exact listed name: complete " \
                       "description, inputSchema, outputSchema, title and annotations. Listings carry only " \
                       "the first sentence of each description, so call this for the long-form gating, " \
                       "envelope and side-effect notes; `summary` repeats the one-line text and `truncated` " \
                       "is true when that summary lost text. An unknown name is answered with the nearest " \
                       "advertised names (prefix and substring matches).",
          parameters: {
            name: { type: "string", required: true,
                    description: "Exact tools/list name, e.g. platform.list_agents or platform.health" }
          }
        }
      end

      protected

      def call(params)
        name = params[:name].to_s.strip
        return error_result("Missing required parameter: name") if name.empty?

        catalog = ::Mcp::ToolCatalog.new(
          protocol_version: ::Mcp::ToolCatalog::DESCRIBE_PROTOCOL_VERSION,
          principal: catalog_principal
        )
        entry = catalog.describe(name)
        return success_result(entry) if entry

        nearest = catalog.nearest(name)
        message = "Unknown tool '#{name}'."
        message += " Nearest matches: #{nearest.join(', ')}." if nearest.any?
        { success: false, error: message, nearest_matches: nearest }
      end

      private

      # The principal whose catalog this call may read, or nil for a user/agent
      # caller (unrestricted, exactly like tools/list).
      #
      # WHY THIS EXISTS. Restricted principals — instance (mTLS node cert) and
      # federation — are DEFAULT-DENY (Mcp::Principal#restricted?): tools/list
      # advertises only their granted patterns. Grants are globs in practice
      # ("platform.*", "platform.system_*_read"), so one of them can easily
      # match `platform.describe_tool` itself. Without this scoping, that one
      # grant would read the full entry — description, schemas, annotations —
      # of every tool the principal was NOT granted, and #nearest would
      # enumerate their names. The controller's may_invoke? gate authorizes the
      # CALL; only this scopes the RESULT.
      #
      # `instance_authorized` is set by McpPlatformToolRegistrar for EVERY
      # restricted principal (streamable_http_controller.rb passes
      # `current_mcp_principal&.restricted?`), while `node_instance` arrives
      # only for the instance kind. A restricted caller we cannot resolve a
      # grant for (federation, whose partner row never reaches the tool) gets a
      # principal that grants nothing — fail closed, never the full catalog.
      def catalog_principal
        return nil unless instance_authorized?

        if node_instance
          ::Mcp::Principal.new(kind: :instance, account: account,
                               node_instance: node_instance, subject_id: node_instance.id)
        else
          ::Mcp::Principal.new(kind: :federation, account: account, subject_id: nil)
        end
      end
    end
  end
end
