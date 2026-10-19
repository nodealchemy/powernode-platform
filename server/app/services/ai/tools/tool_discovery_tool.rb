# frozen_string_literal: true

module Ai
  module Tools
    # platform.discover_tools — tier 1 of the progressive-disclosure protocol
    # (C3-3): find a verb by intent, then platform.describe_tool only the one
    # about to be called. Ranks with SemanticToolDiscoveryService (embeddings,
    # keyword fallback when none are available) and answers from the SAME
    # Mcp::ToolCatalog tools/list and describe_tool read, so names, summaries
    # and read/write hints are exactly what a client sees, scoped to the
    # caller's catalog. Read-only: it ranks the catalog and touches nothing.
    class ToolDiscoveryTool < BaseTool
      tool_family "discovery"
      include Concerns::CatalogPrincipal

      REQUIRED_PERMISSION = "ai.agents.read"
      DEFAULT_LIMIT = 10
      MAX_LIMIT = 25

      declare_action "discover_tools", mutating: false, limit: MAX_LIMIT,
                                       returns: "ranked tools, each with its listed name, one-line summary, " \
                                                "family and read-only/destructive hints",
                                       see_also: { "describe_tool" => "the full schema of one tool found here" }

      def self.definition
        {
          name: "discover_tools",
          # Self-contained first sentence under Mcp::ToolCatalog's listing cap,
          # like describe_tool's: it is all tools/list shows for this verb.
          description: "Find platform tools by intent: ranked exact tool names with one-line summaries, " \
                       "family and read-only/destructive hints. Ranking is semantic when embeddings are " \
                       "available and keyword-based otherwise. Narrow with `family` (a declared tool " \
                       "family) and `read_only`, then call platform.describe_tool on the one name you " \
                       "will call for its full inputSchema.",
          parameters: {
            query: { type: "string", required: true,
                     description: "What you want to do, in plain words, e.g. \"rotate a peer's WireGuard key\"" },
            family: { type: "string", required: false, enum: ToolFamilies.all.keys,
                      description: "Only tools declared in this family" },
            read_only: { type: "boolean", required: false,
                         description: "true for read-only tools only, false for tools that write" },
            limit: { type: "integer", required: false,
                     description: "Maximum tools returned (default #{DEFAULT_LIMIT}, max #{MAX_LIMIT})" }
          }
        }
      end

      protected

      def call(params)
        query = params[:query].to_s.strip
        return error_result("Missing required parameter: query") if query.empty?

        family = params[:family].to_s.strip.presence
        if family && !ToolFamilies.known?(family)
          return error_result("Unknown family '#{family}'. Known families: #{ToolFamilies.all.keys.join(', ')}")
        end

        read_only = params[:read_only].to_s.strip.presence && ActiveModel::Type::Boolean.new.cast(params[:read_only])
        limit = params[:limit].to_i.positive? ? [ params[:limit].to_i, MAX_LIMIT ].min : DEFAULT_LIMIT

        tools = matches(query, family: family, read_only: read_only).first(limit)
        success_result(
          query: query,
          family: family,
          read_only: read_only,
          count: tools.size,
          tools: tools,
          describe_with: "Call platform.describe_tool with name: <one of these names> for its full description " \
                         "and inputSchema before calling it."
        )
      end

      private

      # Lazily walks the ranking, so the catalog builds an entry only for
      # candidates that survive the cheaper filters.
      def matches(query, family:, read_only:)
        catalog = ::Mcp::ToolCatalog.new(
          protocol_version: ::Mcp::ToolCatalog::DESCRIBE_PROTOCOL_VERSION,
          principal: catalog_principal
        )
        visible = catalog.advertised_names.to_set

        SemanticToolDiscoveryService.new(account: account).discover(query: query, limit: nil).lazy.filter_map do |hit|
          # Agents, MCP-server rows and dynamic tools are not callable as platform.<name>.
          next unless hit[:source] == "platform"

          name = "#{::Mcp::ToolCatalog::PLATFORM_PREFIX}#{hit[:name]}"
          next unless visible.include?(name)

          tool_family = PlatformApiToolRegistry.family_for(hit[:name])
          next if family && tool_family != family

          entry = catalog.describe(name)
          next unless entry

          hints = entry["annotations"] || {}
          next if !read_only.nil? && (hints["readOnlyHint"] == true) != read_only

          {
            name: name,
            summary: entry["summary"],
            family: tool_family,
            read_only: hints["readOnlyHint"] == true,
            destructive: hints["destructiveHint"] == true,
            relevance: hit[:relevance_score].to_f.round(3)
          }
        end
      end
    end
  end
end
