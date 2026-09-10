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

    # ── SAFETY ANNOTATIONS (2025-03-26+) ────────────────────────────────────
    #
    # GROUND TRUTH FIRST, HEURISTIC ONLY AS A FALLBACK (increment E2).
    #
    # Every action `Ai::Tools::PlatformApiToolRegistry` advertises carries a
    # `declare_action(mutating:)` record, and since E2 a `destructive:` one
    # too. That is what an entry's annotations are built from. The name-prefix
    # heuristic below survives ONLY for an action with no declaration to read —
    # the introspection family, and a registry entry whose class will not load.
    #
    # It survives as a fallback rather than being deleted because "no
    # declaration" and "declared read-only" are different statements and the
    # catalog must not conflate them; `annotationSource` is what keeps them
    # apart on the wire.
    #
    # WHY THE HEURISTIC COULD NOT STAY PRIMARY. It tests the FIRST
    # underscore-token of the registry name, so:
    #   * 194 declared read-only actions got no hint at all, because their
    #     names lead with a noun (`data_source_get`, `campaign_status`,
    #     `agent_introspect`, …);
    #   * three declared-MUTATING actions were advertised `readOnlyHint: true`,
    #     because `perceive` and `measure` are in the prefix list
    #     (`Ai::Tools::CoordinationTool`'s `measure_pressure`,
    #     `perceive_pressure`, `perceive_signals` — all three additionally
    #     require `ai.manage`). That is worse than a missing hint: a client
    #     trusting it treats three privileged writes as safe reads.
    READ_ONLY_ACTION_PREFIXES = %w[list get search query read describe check discover perceive measure recent].freeze
    READ_ONLY_ACTION_NAMES = %w[health metrics resources scoreboard].freeze

    # Where an entry's annotations came from, published beside them so the
    # remaining gap is VISIBLE rather than indistinguishable from ground truth.
    # An operator reading the catalog, and a client deciding how much to trust
    # a hint, both need to know which of the two produced it.
    #
    # camelCase to match its neighbours (`readOnlyHint`, `destructiveHint`)
    # inside the same wire object; it is the only field here that is not part
    # of the MCP ToolAnnotations schema, and it rides in `annotations` because
    # that is the object it describes. Annotations are untrusted hints by spec,
    # so a client that ignores an unknown key loses nothing.
    ANNOTATION_SOURCE_KEY = "annotationSource"
    ANNOTATION_SOURCE_DECLARED = "declared"
    ANNOTATION_SOURCE_INFERRED = "inferred"

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
        output_schema: platform_output_schema,
        declaration: declaration_for(defn[:name])
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
        output_schema: GENERIC_OBJECT_SCHEMA,
        # The introspection family is not Ai::Tools::BaseTool-backed and has
        # no declare_action record to read, so its annotations are inferred
        # and say so. That is the honest answer, not a gap to paper over:
        # giving them a manufactured `declared` source would put the one
        # family with no ground truth on the same footing as the 640 that
        # have it.
        declaration: nil
      )
    end

    # Version-gated tool metadata for catalog entries. Fields never leak to
    # revisions that predate them: annotations (2025-03-26), title +
    # outputSchema (2025-06-18).
    #
    # `output_schema` is supplied by the CALLER because the two families
    # return different shapes — see #platform_output_schema and
    # GENERIC_OBJECT_SCHEMA.
    def decorate_tool_entry(tool, output_schema:, declaration: nil)
      action = tool["name"].to_s.delete_prefix(PLATFORM_PREFIX)

      if protocol_at_least?("2025-03-26")
        tool["annotations"] = annotations_for(action, declaration)
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

    # THE ANNOTATIONS OBJECT for one entry. Always present from 2025-03-26 on,
    # always carrying ANNOTATION_SOURCE_KEY, so "this catalog has no ground
    # truth for that action" is a thing a reader can SEE instead of an absence
    # they have to infer.
    #
    #   declared, read-only   {readOnlyHint: true,  annotationSource: "declared"}
    #   declared, write       {readOnlyHint: false, destructiveHint: <bool>,
    #                          annotationSource: "declared"}
    #   inferred, destroy-shaped {readOnlyHint: false, destructiveHint: true,
    #                             annotationSource: "inferred"}
    #   inferred, read-shaped {readOnlyHint: true,  annotationSource: "inferred"}
    #   inferred, otherwise   {annotationSource: "inferred"}
    #
    # `destructiveHint` is emitted EXPLICITLY on every declared write and on no
    # read. Both halves are deliberate:
    #
    #   * the MCP default for `destructiveHint` is TRUE, so a mutating tool
    #     that omits it reads to a client as "may destroy". Publishing `false`
    #     on the ~300 mutating-but-reversible verbs is the informative half of
    #     this change — the `true` on the destructive ones is the half people
    #     expect, but it is the correction to the other 300 that changes what a
    #     client does;
    #   * the spec says `destructiveHint` is meaningful only when
    #     `readOnlyHint` is false, so emitting it on a read would publish a
    #     field with no defined reading.
    #
    # `idempotentHint` is NOT emitted. The declaration vocabulary has no
    # idempotency record and inventing one from a description's prose would be
    # a second name-shaped guess of exactly the kind E2 removes. Adding it is a
    # declaration-vocabulary change plus a pass over every declare_action call site, and an
    # option nothing sets is worse than no option.
    #
    # ANNOTATION_SOURCE_KEY reports where the READ/WRITE classification came
    # from — the field that was wrong before E2 — not every field in the
    # object. See #destructive? for the one place a second input contributes.
    def annotations_for(action, declaration)
      return inferred_annotations(action) if declaration.nil?

      read_only = declaration[:mutating] != true
      hints = { "readOnlyHint" => read_only }
      hints["destructiveHint"] = destructive?(action, declaration) unless read_only
      hints[ANNOTATION_SOURCE_KEY] = ANNOTATION_SOURCE_DECLARED
      hints
    end

    # THE DECLARATION, OR THE DENY OVERLAY AS A FLOOR THAT CAN ONLY TIGHTEN.
    #
    # `destructive:` is opt-in and E2 marks the CORE surface only — the
    # extension tool files are another lane's partition. Publishing the bare
    # declaration would therefore advertise `destructiveHint: false` on ~40
    # extension verbs including `system_terminate_instance` and
    # `system_destroy_instance`: not a missing hint but a FALSE one, which is
    # strictly worse than the pre-E2 silence and is the same failure this
    # increment exists to remove, moved one field over.
    #
    # So an action the instance deny overlay refuses as destroy-shaped reports
    # `destructiveHint: true` even with nothing declared. Note the DIRECTION:
    # the floor can only ever make a verb look more dangerous, never less, so
    # the worst it can do is overstate — and this is not the glob becoming the
    # source of truth, which is what #declare_action's own comment rejects. A
    # declaration is never overridden downward by it, because a declaration
    # that said `false` where the overlay says `true` is a disagreement the
    # lint refuses to let exist in core.
    #
    # It retires for the extension surface the moment those declarations land;
    # for core it is already a no-op, asserted by the lint's set equality.
    def destructive?(action, declaration)
      return true if declaration[:destructive] == true

      ::Mcp::Principal.destructive_tool?(action)
    end

    # THE FLOOR HOLDS HERE TOO (E2 review L4). Before this, the inferred path
    # never consulted the overlay: #destructive? is reached only from a
    # declared write, so an action with NO declaration — its class would not
    # load, #declaration_for rescued, or it is an introspection tool, which
    # never has one — published no destructiveHint even when destroy-shaped.
    # MCP reads an absent destructiveHint as true, so that was safe by
    # accident. It is safe by construction now, and a destroy-shaped name is
    # never advertised read-only on the strength of a prefix match: the overlay
    # is checked FIRST.
    def inferred_annotations(action)
      hints = {}
      if ::Mcp::Principal.destructive_tool?(action)
        hints["readOnlyHint"] = false
        hints["destructiveHint"] = true
      elsif read_only_action?(action)
        hints["readOnlyHint"] = true
      end
      hints[ANNOTATION_SOURCE_KEY] = ANNOTATION_SOURCE_INFERRED
      hints
    end

    # The declare_action record behind a registry key, or nil.
    #
    # THE ALIAS HOP IS LOAD-BEARING. Ai::Tools::BaseTool#execute resolves a
    # declaration by #routed_action_name, which is NOT the registry key for the
    # 25 keys McpPlatformToolRegistrar aliases (the code_* family, the
    # knowledge-graph tools): `code_upsert_node` runs as `upsert_node`. A
    # lookup keyed on the registry key would find nothing for those, quietly
    # drop them onto the inferred path, and publish a heuristic guess for
    # actions whose ground truth is right there. The same trap already cost
    # this codebase four verbs inside the permission-publishing change's first
    # cut (see McpPlatformToolRegistrar.resolved_permission_for).
    #
    # `action_dispatched?` is CALLED on the registrar rather than
    # reimplemented, so the two cannot drift — the same reasoning, and the same
    # `send`, that spec/support/tool_declaration_coverage.rb documents. It is
    # private there; promoting it to a public seam is a tidier follow-up owned
    # by whoever owns the registrar.
    def declaration_for(registry_key)
      key = registry_key.to_s
      class_name = registry_map[key]
      return nil if class_name.blank?

      klass = class_name.safe_constantize
      return nil unless klass.respond_to?(:declared_action)

      klass.declared_action(routed_action_name(key, klass))
    rescue StandardError => e
      # A catalog entry must still render when one class misbehaves; it simply
      # renders as inferred. Logged, never swallowed silently.
      Rails.logger.warn(
        "[Mcp::ToolCatalog] declaration lookup failed for #{registry_key}: #{e.class}: #{e.message}"
      )
      nil
    end

    # Memoized per catalog INSTANCE (one request), not per class. The registrar
    # deliberately does not memoize .all_tools — a class-level memo would
    # freeze the extension half at whatever was registered on first use — and
    # that reasoning does not apply to a per-request object, which would
    # otherwise re-merge the whole registry hash once per entry.
    def registry_map
      @registry_map ||= ::Ai::Tools::PlatformApiToolRegistry.all_tools
    end

    def routed_action_name(registry_key, klass)
      if action_dispatched?(klass)
        ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.fetch(registry_key, registry_key)
      else
        klass.definition[:name].to_s
      end
    end

    # Memoized per class: .action_definitions builds a fresh hash on every
    # call, and a full listing asks it once per entry.
    def action_dispatched?(klass)
      @action_dispatched ||= {}
      name = klass.name
      return @action_dispatched[name] if @action_dispatched.key?(name)

      @action_dispatched[name] = ::Ai::Tools::McpPlatformToolRegistrar.send(:action_dispatched?, klass)
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
