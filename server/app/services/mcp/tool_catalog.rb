# frozen_string_literal: true

module Mcp
  # THE ONE BUILDER of the MCP tool catalog entries (IMP-7e84ae0ccc91).
  #
  # Two surfaces read it and must never drift from each other:
  #
  #   * tools/list (Api::V1::Mcp::StreamableHttpController#handle_tools_list)
  #     — every entry with its `description` cut to ONE LINE (#list_entries);
  #   * platform.describe_tool (Ai::Tools::ToolCatalogTool) and the legacy
  #     ActionCable `tools/describe` path (Mcp::ProtocolService#describe_tool)
  #     — the SAME entry with the FULL description, plus `truncated` so a
  #     client knows whether the summary lost text (#describe).
  #
  # WHY the listing is one line per tool. Operator ruling R4 (amended
  # 2026-09-03): "drop descriptions and provide a mechanism to retrieve tool
  # details on-demand". Measured over one session on one checkout, full
  # registry, user principal, one page of 625 entries (616 platform + 9
  # introspection): with the long-form text the descriptions alone were
  # 120,227 B of a 1,109,260 B raw body — 248 of them longer than 160
  # characters, the longest 1,477 — and 110,483 B gzipped; with the one-line
  # listing they are 48,941 B of 1,037,808 B raw and 84,143 B gzipped. Those
  # paragraphs are the gating, envelope and side-effect notes most extension
  # verbs carry. A bare name would make tool selection impossible for a
  # client, so the first sentence stays and the paragraphs move behind
  # platform.describe_tool. The catalog generator
  # (docs/reference/auto/mcp-tools.md) keeps the full text: it is the operator
  # reference, not the wire, and reads the registry directly rather than this
  # builder. The ActionCable manifest (McpPlatformToolRegistrar#build_manifest)
  # does not share this builder and is untouched.
  #
  # The per-entry `outputSchema` is NOT shrunk here and must stay inline:
  # each entry is a STANDALONE JSON-Schema document on the MCP wire (no
  # cross-entry definitions store; the reference client compiles every entry
  # the moment tools/list returns — @modelcontextprotocol/sdk 1.29.0
  # Client#cacheToolMetadata -> AjvJsonSchemaValidator#getValidator ->
  # ajv.compile — so an unresolvable $ref drops the WHOLE catalog for that
  # client). structured_tool_output_spec.rb "outputSchema wire properties"
  # pins that, together with the deflated wire ceiling.
  class ToolCatalog
    # Hard cap on a tools/list `description`, in characters. The listing
    # carries the first sentence; anything longer is cut at a word boundary
    # and ends with ELLIPSIS. Operator-configurable through SiteSetting with
    # this constant as the fallback (see .list_description_limit).
    LIST_DESCRIPTION_LIMIT = 160
    LIST_DESCRIPTION_LIMIT_SETTING = "mcp.tools_list.description_limit"
    ELLIPSIS = "…"

    # The protocol revision #describe builds against: the newest this server
    # speaks, so the on-demand entry always carries every version-gated field
    # (annotations 2025-03-26, title + outputSchema 2025-06-18). It is a tool
    # RESULT, not tools/list metadata, so the per-request revision gate that
    # keeps those fields off an older client's listing does not apply to it.
    DESCRIBE_PROTOCOL_VERSION = ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.max

    # How many candidates an unknown name is answered with.
    NEAREST_MATCH_LIMIT = 5

    PLATFORM_PREFIX = "platform."

    # Conservative read-only heuristic for ToolAnnotations.readOnlyHint
    # (2025-03-26+). Annotations are untrusted hints per spec; only tools
    # whose action name is unambiguously read-only get the hint.
    READ_ONLY_ACTION_PREFIXES = %w[list get search query read describe check discover perceive measure recent].freeze
    READ_ONLY_ACTION_NAMES = %w[health metrics resources scoreboard].freeze

    # Fallback outputSchema for a family that declares no result shape of its
    # own — currently the introspection tools. Says only "a JSON object comes
    # back", which is all handle_tools_call guarantees for them (it wraps a
    # non-object result as {"result" => ...}).
    GENERIC_OBJECT_SCHEMA = { "type" => "object" }.freeze

    class << self
      # Operator-configured cap, with the constant as the fallback. A
      # non-positive configured value is ignored rather than honoured: a zero
      # would blank every description on the wire.
      def list_description_limit
        value = ::SiteSetting.get(LIST_DESCRIPTION_LIMIT_SETTING).to_i
        value.positive? ? value : LIST_DESCRIPTION_LIMIT
      end

      # One line for the listing: the FIRST SENTENCE of `text`, whitespace
      # collapsed, hard-capped at `limit` characters — cut at a word boundary
      # with ELLIPSIS when the sentence itself is longer than the cap.
      #
      # Returns [summary, truncated]; `truncated` is true whenever the summary
      # carries less text than `text` did, so a client can tell that
      # platform.describe_tool has more to say.
      #
      # A sentence ends at `.`, `!` or `?` followed by whitespace and an
      # upper-case letter, digit, quote or bracket. Requiring the upper-case
      # continuation keeps "e.g. foo" and "vs. bar" inside the sentence; a
      # description that ends its first sentence with a lower-case second one
      # simply keeps both until the cap applies.
      def summarize(text, limit: list_description_limit)
        full = text.to_s.strip.gsub(/\s+/, " ")
        return ["", false] if full.empty?

        first = full.split(/(?<=[.!?])\s+(?=[A-Z0-9"'(\[`])/, 2).first
        summary = first.length > limit ? cut_at_word_boundary(first, limit) : first

        [summary, summary != full]
      end

      private

      def cut_at_word_boundary(text, limit)
        room = limit - ELLIPSIS.length
        head = text[0, room]
        boundary = head.rindex(/\s/)
        head = head[0, boundary] if boundary && boundary.positive?
        head.rstrip.sub(/[,;:]+\z/, "") + ELLIPSIS
      end
    end

    # @param protocol_version [String] the MCP revision the entries are shaped
    #        for (fields never leak to revisions that predate them)
    # @param principal [Mcp::Principal, nil] restricted principals get their
    #        grant-scoped subset (Mcp::Principal#filter_tools); nil/users keep
    #        the full advertised set
    # @param agent [Ai::Agent, nil] forwarded to
    #        PlatformApiToolRegistry.tool_definitions (nil = availability only)
    def initialize(protocol_version:, principal: nil, agent: nil)
      @protocol_version = protocol_version.to_s
      @principal = principal
      @agent = agent
    end

    # Every advertised entry with its FULL description, principal-filtered and
    # in deterministic name order (2026-07-28 SHOULD — also keeps pagination
    # cursors stable across processes and deploys).
    #
    # This materializes the WHOLE catalog (~616 entries, each with a freshly
    # built 1,091 B outputSchema — about 1 MB of transient hashes), so it is
    # for the LISTING only. A single-name lookup goes through #entry_for and a
    # name-only question through #advertised_names; neither pays this.
    def entries
      @entries ||= begin
        all = platform_definitions.map { |defn| platform_entry(defn) } +
              introspection_definitions.map { |defn| introspection_entry(defn) }
        all = @principal.filter_tools(all) if @principal
        all.sort_by { |tool| tool["name"].to_s }
      end
    end

    # Advertised NAMES only, principal-filtered and name-sorted. No schema
    # conversion and no per-entry outputSchema: answering "what is near this
    # name?" must not cost a full catalog build.
    def advertised_names
      @advertised_names ||= begin
        names = platform_definitions.map { |defn| "#{PLATFORM_PREFIX}#{defn[:name]}" } +
                introspection_definitions.map { |defn| defn[:id].to_s }
        names = @principal.filter_tools(names) if @principal
        names.sort
      end
    end

    # The tools/list shape: #entries with each description cut to one line.
    def list_entries
      limit = self.class.list_description_limit
      entries.map do |tool|
        summary, _truncated = self.class.summarize(tool["description"], limit: limit)
        tool.merge("description" => summary)
      end
    end

    # The on-demand shape for one tool: the listing entry with the FULL
    # description, plus `summary` (what tools/list carried) and `truncated`.
    # nil for a name this catalog does not advertise — which, for a restricted
    # principal, INCLUDES every name outside its grant (see #entry_for).
    def describe(name)
      tool = entry_for(name.to_s)
      return nil unless tool

      summary, truncated = self.class.summarize(tool["description"])
      tool.merge("summary" => summary, "truncated" => truncated)
    end

    # Advertised names closest to an unknown `name`: prefix matches first,
    # then substring matches, both case-insensitive and tolerant of a missing
    # `platform.` prefix. Empty when nothing resembles it.
    #
    # Reads #advertised_names, so a restricted principal is answered only with
    # names inside its grant: an unknown-name error must not enumerate the
    # catalog it was denied.
    def nearest(name, limit: NEAREST_MATCH_LIMIT)
      needle = name.to_s.downcase.delete_prefix(PLATFORM_PREFIX)
      return [] if needle.empty?

      names = advertised_names
      bare = ->(candidate) { candidate.downcase.delete_prefix(PLATFORM_PREFIX) }

      prefixed = names.select { |candidate| bare.call(candidate).start_with?(needle) || needle.start_with?(bare.call(candidate)) }
      substring = names.select { |candidate| bare.call(candidate).include?(needle) || needle.include?(bare.call(candidate)) }

      (prefixed + substring).uniq.first(limit)
    end

    private

    # ONE entry by exact name, or nil. The principal check is the SAME
    # predicate #entries applies (Mcp::Principal#filter_tools, which accepts a
    # bare name), so the single-entry door cannot be wider than the listing.
    def entry_for(name)
      return nil unless advertised_names.include?(name)

      defn = platform_definitions.find { |d| "#{PLATFORM_PREFIX}#{d[:name]}" == name }
      return platform_entry(defn) if defn

      defn = introspection_definitions.find { |d| d[:id].to_s == name }
      defn && introspection_entry(defn)
    end

    def platform_definitions
      @platform_definitions ||= ::Ai::Tools::PlatformApiToolRegistry.tool_definitions(agent: @agent)
    end

    def introspection_definitions
      @introspection_definitions ||= ::Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS
    end

    def platform_entry(defn)
      decorate_tool_entry(
        {
          "name" => "#{PLATFORM_PREFIX}#{defn[:name]}",
          "description" => defn[:description],
          "inputSchema" => build_input_schema(defn[:parameters])
        },
        output_schema: platform_output_schema
      )
    end

    def introspection_entry(defn)
      decorate_tool_entry(
        {
          "name" => defn[:id],
          "description" => defn[:description],
          "inputSchema" => defn[:input_schema]
        },
          # NOT the platform envelope. Ai::Introspection::McpToolRegistrar
          # .execute_tool returns the metrics/health service hash DIRECTLY
          # (mcp_tool_registrar.rb #execute_tool `case tool_id`) with no
          # success/error/data wrapper, so advertising `required:
          # ["success"]` here would make a strict client reject every valid
          # introspection result. The generic object schema stays truthful
          # for these until they declare a shape of their own.
        output_schema: GENERIC_OBJECT_SCHEMA
      )
    end

    # Version-gated tool metadata for catalog entries. Fields never leak to
    # revisions that predate them: annotations (2025-03-26), title +
    # outputSchema (2025-06-18).
    #
    # `output_schema` is supplied by the CALLER because the two families
    # return different shapes — see #platform_output_schema and
    # GENERIC_OBJECT_SCHEMA.
    def decorate_tool_entry(tool, output_schema:)
      action = tool["name"].to_s.delete_prefix(PLATFORM_PREFIX)

      if protocol_at_least?("2025-03-26") && read_only_action?(action)
        tool["annotations"] = { "readOnlyHint" => true }
      end

      if protocol_at_least?("2025-06-18")
        tool["title"] = action.split("_").map(&:capitalize).join(" ")
        tool["outputSchema"] = output_schema
      end

      tool
    end

    # The DECLARED envelope every Ai::Tools::BaseTool subclass returns, not a
    # bare {"type" => "object"}. Read from the same source as the ActionCable
    # manifest so the two cannot drift (IMP-b92421fb7c59). Built fresh per
    # entry: sharing one hash across every entry in a page would make a
    # mutation of any one of them a mutation of all.
    #
    # ACCEPTED PAYLOAD COST: 615 x 1,091 B = 671,118 B of outputSchema per
    # full page (measured 2026-09-03), knowingly paid — the envelope's five
    # `description` strings ARE the schema's reason to exist. Instance and
    # federation principals do not pay it in practice — Mcp::Principal
    # #filter_tools trims their catalog to the granted patterns first. DO NOT
    # hoist it behind a shared $defs/$ref: see the class comment.
    def platform_output_schema
      ::Ai::Tools::McpPlatformToolRegistrar.default_output_schema
    end

    def read_only_action?(action)
      READ_ONLY_ACTION_NAMES.include?(action) ||
        READ_ONLY_ACTION_PREFIXES.include?(action.split("_").first)
    end

    # Shared with McpPlatformToolRegistrar's manifest/database schemas via one
    # converter so the two cannot drift (IMP-e809396f9eda).
    def build_input_schema(parameters)
      ::Ai::Tools::ParameterSchema.build(parameters)
    end

    def protocol_at_least?(version)
      @protocol_version >= version
    end
  end
end
