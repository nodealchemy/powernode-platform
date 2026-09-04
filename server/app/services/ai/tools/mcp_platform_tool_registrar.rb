# frozen_string_literal: true

module Ai
  module Tools
    class McpPlatformToolRegistrar
      TOOL_ID_PREFIX = "platform"

      # Maps MCP registry keys to internal tool action names where they differ.
      # Most tools use identical registry/action names; only KnowledgeGraphTool
      # uses shortened internal names (e.g. "search" instead of "search_knowledge_graph").
      ACTION_ALIASES = {
        "search_knowledge_graph" => "search",
        "reason_knowledge_graph" => "reason",
        "get_graph_node" => "get_node",
        "list_graph_nodes" => "list_nodes",
        "get_graph_neighbors" => "get_neighbors",
        "graph_statistics" => "statistics",
        "get_subgraph" => "subgraph",
        "extract_to_knowledge_graph" => "extract",
        # Codebase Intelligence
        "code_context_tree" => "context_tree",
        "code_file_skeleton" => "file_skeleton",
        "code_semantic_search" => "semantic_search",
        "code_identifier_search" => "identifier_search",
        "code_semantic_navigate" => "semantic_navigate",
        "code_feature_hub" => "feature_hub",
        "code_blast_radius" => "blast_radius",
        "code_static_analysis" => "static_analysis",
        "code_index_status" => "index_status",
        "code_dead_code" => "dead_code",
        "code_find_duplicates" => "find_duplicates",
        "code_analyze_section" => "analyze_section",
        "code_upsert_node" => "upsert_node",
        "code_create_relation" => "create_relation",
        "code_search_graph" => "search_graph",
        "code_prune_stale" => "prune_stale",
        "code_bulk_index" => "bulk_index"
      }.freeze

      class << self
        # The permission that ACTUALLY gates `action_name` on `tool_class`.
        #
        # Dispatch resolves `ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION`
        # (Ai::Tools::SystemFleetTool#required_perm_for and its 25 siblings), so
        # publishing only the class floor understates the real bar on 339 of the
        # registry's 606 advertised actions — storing "system.nodes.read" for
        # system_deploy_platform and system_terminate_instance alike.
        #
        # NOT A PRIVILEGE ESCALATION, and the fix is not framed as closing one.
        # Every consumer of the published value runs BEFORE the tool's own
        # per-action check, so the composition fails closed: a weaker published
        # permission never admits a call the tool would refuse. What it corrupts
        # is what the platform SAYS. There are exactly TWO live consumers, both
        # on the MCP wire path, and this list is deliberately exhaustive because
        # a comment claiming a wider reach than it has is how the next false
        # citation gets written:
        #   * Mcp::PermissionValidator — returns "authorized" for a verb the tool
        #     then refuses, so the refusal arrives from a gate the validator
        #     reported wasn't there (protocol_service.rb:195).
        #   * Mcp::ProtocolService#tool_visible_to? (:454-470) — advertises the
        #     tool on the same value.
        # NOT a consumer, contrary to what the sibling catalog fix's reasoning
        # assumed: the frontend MCP browser. Api::V1::McpToolsController
        # #serialize_mcp_tool omits required_permissions from both the summary
        # and the include_details payload, and no MCP type in frontend/src
        # carries the field — the operator's grant-sizing surface is the
        # generated catalog (fixed in IMP-a63365dc0f41), not this column.
        #
        # A privilege understatement is still the direction that makes a
        # dangerous verb look safe (IMP-bab07f770c0e).
        #
        # KEYED ON THE ACTION THAT RUNS, NOT ON THE NAME INVOKED. A ladder is
        # consulted with the :action the registrar dispatches, which for 25 of
        # the registry's names is an ALIAS of the registry key (ACTION_ALIASES,
        # applied in #execute_tool where it injects execution_params[:action]).
        # Looking the ladder up by registry key silently misses
        # CodeMemoryTool's four entries — it keys on "upsert_node", not
        # "code_upsert_node" — leaving four knowledge-graph write/destructive
        # verbs at the "ai.agents.read" floor. That is the defect that survived
        # inside its own fix in IMP-a63365dc0f41's first cut (333 of 337);
        # code_memory_tool.rb:22-25 states the rule.
        #
        # A ladder entry keyed by the REGISTRY name of an aliased action would be
        # dead at dispatch, so falling back to the floor for it is correct, not a
        # miss. No class currently declares both forms.
        #
        # SINGLE COPY BY CONSTRUCTION. This is the only implementation; the
        # catalog rake (lib/tasks/mcp_tool_catalog.rake) and both write sites in
        # this file call it. A second copy is a second place to get the alias hop
        # wrong, which is exactly how those four verbs survived last time.
        #
        # `const_defined?` WITH inheritance: a subclass that inherits both the map
        # and #required_perm_for is really gated by the parent's ladder, because
        # the constant in that method body resolves lexically to the defining
        # class. (The one shape this reads wrong is a subclass declaring its own
        # map but inheriting the parent's resolver, where dispatch uses the
        # parent's. Inert today — every registry tool class is a direct
        # Ai::Tools::BaseTool subclass, and BaseTool has no map.)
        # `action_name` is normalized with #to_s, which makes this marginally
        # MORE forgiving than dispatch — a tool's own `ACTION_PERMISSIONS[action]`
        # does no normalization, so a Symbol action would fall to the floor there
        # while resolving up here. Both call sites pass Strings (registry keys,
        # and `definition[:name]`), and dispatch itself only ever sees Strings
        # (execution_params is a HashWithIndifferentAccess), so the two agree in
        # practice; the #to_s is there so a Symbol definition name cannot produce
        # a silently wrong lookup rather than as a claimed dispatch equivalence.
        def resolved_permission_for(tool_class, action_name)
          name = action_name.to_s
          dispatched_action = ACTION_ALIASES.fetch(name, name)

          ladder = tool_constant(tool_class, :ACTION_PERMISSIONS) || {}
          floor  = tool_constant(tool_class, :REQUIRED_PERMISSION)

          ladder[dispatched_action] || floor
        end

        def register_all!(account:)
          registry = ::Mcp::RegistryService.new(account: account)

          # ADVERTISEMENT surface (IMP-5039d026da0d): publishes one manifest per
          # tool class into Mcp::RegistryService, so it asks the registry's
          # advertisement predicate rather than walking the raw map. NOT
          # `tool_classes` — that one is also a RESOLUTION set; see
          # #advertised_tool_classes, which also states the one INVOCATION
          # consequence this filter has (the McpChannel/ProtocolService path).
          advertised_tool_classes.each do |tool_class|
            definition = tool_class.definition
            tool_id = "#{TOOL_ID_PREFIX}.#{definition[:name]}"
            manifest = build_manifest(tool_class)

            begin
              registry.register_tool(tool_id, manifest)
            rescue ::Mcp::RegistryService::ToolConflictError
              # Already registered, skip
            rescue => e
              Rails.logger.warn "[McpPlatformToolRegistrar] Failed to register #{tool_id}: #{e.message}"
            end
          end
        end

        # Sync all platform tools to the mcp_tools database table so the
        # frontend MCP browser page can display them. Also syncs introspection
        # tools from Ai::Introspection::McpToolRegistrar.
        def sync_to_database!(account:)
          mcp_server = account.mcp_servers.find_by(name: "Powernode MCP")
          unless mcp_server
            Rails.logger.warn "[McpPlatformToolRegistrar] Powernode MCP server not found for account #{account.id}"
            return 0
          end

          synced_names = Set.new

          # Sync platform tools from PlatformApiToolRegistry.all_tools.
          #
          # ADVERTISEMENT surface (IMP-5039d026da0d): these rows ARE the catalog
          # the frontend MCP browser lists, so an action the registry refuses to
          # advertise must not get one. Before the predicate call below, this
          # loop walked the raw map and kept writing rows for actions
          # .available_tools had already dropped from tools/list — e.g. the
          # docker-runtime actions in core mode after IMP-2836d290f99a.
          #
          # The stale-row delete at the bottom of this method is what makes the
          # filter take effect on an EXISTING database rather than only on a
          # fresh one: a de-advertised action drops out of `synced_names`, so its
          # row is removed on the next sync — and is written back by the sync
          # after the backing extension loads. No agent is in scope here (this is
          # one account-wide catalog), so the predicate runs with `agent: nil`,
          # which asks availability only. See
          # PlatformApiToolRegistry.advertised_class?.
          PlatformApiToolRegistry.all_tools.each do |action_name, class_name|
            tool_class = class_name.constantize
            next unless PlatformApiToolRegistry.advertised_action?(action_name, tool_class)

            action_defs = tool_class.action_definitions
            action_def = action_defs[action_name] || {}

            description = action_def[:description] || tool_class.definition[:description]
            parameters = action_def[:parameters] || {}
            input_schema = convert_to_json_schema(parameters)
            # Per-ACTION, not the class floor: this loop writes one mcp_tools row
            # per registry action, so each row can and must carry the permission
            # that action really resolves to. See .resolved_permission_for.
            required_permission = resolved_permission_for(tool_class, action_name)

            upsert_mcp_tool!(mcp_server, action_name, description, input_schema, "account", [required_permission].compact)
            synced_names << action_name
          rescue NameError => e
            Rails.logger.warn "[McpPlatformToolRegistrar] Skipping #{action_name}: #{e.message}"
          end

          # Sync introspection tools
          if defined?(Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS)
            Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS.each do |tool_def|
              name = tool_def[:name]
              upsert_mcp_tool!(
                mcp_server, name, tool_def[:description],
                tool_def[:input_schema]&.deep_stringify_keys || {},
                "account", tool_def[:required_permissions] || []
              )
              synced_names << name
            end
          end

          # Remove tools no longer in the registry.
          #
          # destroy_all, NOT delete_all (IMP-5039d026da0d). `mcp_tool_executions`
          # carries a NO-ACTION foreign key on `mcp_tools` (schema.rb:
          # `add_foreign_key "mcp_tool_executions", "mcp_tools"`, no `on_delete:`)
          # and `mcp_tool_id` is `null: false`, so a bare DELETE raises
          # ActiveRecord::InvalidForeignKey for any row that has ever been
          # executed — relation#delete_all issues that DELETE directly and
          # bypasses McpTool's `has_many :mcp_tool_executions, dependent:
          # :destroy`. Execution rows on THESE rows are reachable today via
          # Api::V1::McpToolsController#execute -> McpTool#execute and via
          # Ai::AgentToolBridgeService#dispatch_external_mcp_tool, neither of
          # which excludes the "Powernode MCP" server. The hazard was latent
          # while these rows were never stale; the advertisement filter above
          # makes it reachable, because a de-advertised action now drops out of
          # `synced_names` on an EXISTING database. Neither non-spec caller
          # (db/seeds/ai_skills_seed.rb, lib/tasks/mcp_tool_catalog.rake)
          # rescues, so the raise would abort the whole catalog sync.
          #
          # Removal, not `enabled: false`: Api::V1::McpToolsController#index
          # lists every row by default and only filters on `enabled` when the
          # caller passes the param, so disabling would leave a de-advertised
          # action visible in the frontend MCP browser.
          stale_count = mcp_server.mcp_tools.where.not(name: synced_names.to_a).destroy_all.size

          # Update server capabilities with tool count
          mcp_server.update_columns(
            capabilities: mcp_server.capabilities.merge("tool_count" => synced_names.size),
            last_health_check: Time.current
          )

          Rails.logger.info "[McpPlatformToolRegistrar] Synced #{synced_names.size} tools to database (removed #{stale_count} stale)"
          synced_names.size
        end

        def execute_tool(tool_id, params:, account:, user: nil, agent_id: nil, mcp_agent: nil, instance_authorized: false, node_instance: nil)
          tool_name = tool_id.delete_prefix("#{TOOL_ID_PREFIX}.")
          tool_class = find_tool_class(tool_name)
          raise ArgumentError, "Unknown platform tool: #{tool_name}" unless tool_class

          # SECURITY: Enforce permission at execution time (defense-in-depth)
          enforce_permission!(user: user, tool_class: tool_class, tool_id: tool_id, instance_authorized: instance_authorized)

          # Rate limiting per agent
          if agent_id
            Ai::Introspection::RateLimiter.check!(
              agent_id: agent_id,
              max_calls: Ai::Tools::BaseTool::MAX_CALLS_PER_EXECUTION,
              window: 60
            )
          end

          # Audit log
          Rails.logger.info(
            "[McpPlatformTool] Executing #{tool_id} " \
            "user=#{user&.id} account=#{account.id} agent=#{agent_id}"
          )

          execution_params = params.with_indifferent_access

          # Multi-action tools use an :action param to route internally.
          # Auto-inject the registry key as the action when the tool class
          # handles multiple registry entries (e.g. create_agent, list_agents
          # all map to AgentManagementTool). A caller-supplied action wins, so
          # for a caller with nothing downstream bounding what it runs, it must
          # first be shown to agree with the name authorization cleared.
          if execution_params.key?(:action)
            if action_pinned_to_name?(user: user, mcp_agent: mcp_agent, instance_authorized: instance_authorized)
              enforce_action_scope!(tool_name: tool_name, tool_id: tool_id, tool_class: tool_class,
                                    supplied_action: execution_params[:action],
                                    principal: instance_authorized ? "instance" : "none")
            end
          elsif action_dispatched?(tool_class)
            execution_params[:action] = ACTION_ALIASES.fetch(tool_name, tool_name)
          end

          # THE INVOCATION HALF of the advertisement predicate (IMP-128fe17fd8c8).
          #
          # #find_tool_class resolves off PlatformApiToolRegistry.all_tools RAW
          # and stays that way on purpose (see .tool_classes below), so before
          # this check the four advertisement surfaces unified by
          # IMP-5039d026da0d had no counterpart here: an action absent from
          # tools/list was still dispatched into the tool by any client that
          # knew its name. Mcp::ProtocolService#invoke_tool did not diverge that
          # way — but NOT for the reason recorded here until IMP-8e3bd13d0136.
          # It is not that its catalog and its dispatch table are one filtered
          # Mcp::Registry; it is that #register_all! discards the registry it
          # fills (see .unavailable_action_refusal), so that path resolves no
          # platform manifest at all and refuses de-advertised and advertised
          # names alike. Its de-advertised half is now answered by
          # .unavailable_action_refusal, with this same envelope. This check
          # closes the gap on HTTP.
          #
          # AVAILABILITY, NOT AUTHORIZATION, in three respects. (1) The
          # predicate is asked with the default `agent: nil`, under which
          # BaseTool.permitted? short-circuits before any permission lookup and
          # the question degenerates to "is the backing extension loaded?" — the
          # same question the account-wide advertisement surfaces ask. (2) It is
          # placed AFTER enforce_permission! and the rate limiter, so every
          # authorization gate still runs first and unchanged; this adds a
          # refusal, it never grants. (3) It answers with a RESULT envelope
          # rather than raising, which is what the operator direction asked for
          # and what keeps a refusal distinguishable from the -32001 permission
          # denial and from the "Unknown platform tool" ArgumentError that the
          # streamable controller re-routes to the introspection registrar.
          #
          # BOTH NAMES are checked, because there are two doors to the same
          # action. The registry key is the advertised name; `execution_params
          # [:action]` is what will actually run, and for a caller that is not
          # action-pinned (see #action_pinned_to_name?) a supplied action wins
          # over the key — so an advertised name could otherwise carry a
          # de-advertised sibling action into an :action-dispatched class.
          if (refusal = unadvertised_refusal(tool_name: tool_name, tool_class: tool_class,
                                             effective_action: execution_params[:action]))
            Rails.logger.warn("[McpPlatformTool] Refused #{tool_id}: #{refusal[:error]}")
            return refusal
          end

          tool_instance = tool_class.new(account: account, user: user, agent: mcp_agent)
          # Instance principals (mTLS node cert; user/agent both nil) need their
          # node_instance so DevLoopTool#claimant_ref can scope claims as
          # "instance:<id>" — otherwise claimant_ref is nil and every dev-loop
          # action hard-refuses. Guarded so the .new signature and the user/agent
          # paths (node_instance nil) stay byte-for-byte unchanged. (BUG-S)
          tool_instance.node_instance = node_instance if node_instance
          # ...and tell the tool this call already cleared the per-tool grant
          # gate (streamable_http_controller.rb may_invoke?), so a tool's own
          # per-action check can recognise a grant-gated instance principal
          # instead of inferring "internal caller" from the nil user — which
          # handed instances every per-action permission. Guarded so the
          # user/agent paths stay byte-for-byte unchanged. (IMP-9030413bc292)
          tool_instance.instance_authorized = true if instance_authorized
          tool_instance.execute(params: execution_params)
        end

        # The envelope EVERY platform tool returns (Ai::Tools::BaseTool
        # #success_result / #error_result), including the third outcome that used
        # to be undeclared: an approval-gated action that the autonomy gate PARKED
        # returns success: true with a `data.pending` body and nothing applied
        # (BaseTool#execute). With only {success, error} advertised, "done" and
        # "parked, awaiting an operator" were distinguishable to a client solely
        # by reading a sentence in `data.message` (IMP-e809396f9eda).
        #
        # `data` is declared WITHOUT a `type`: tools return objects, arrays and
        # scalars there, and pinning it to "object" would make a strict client
        # reject list-returning actions. `properties` and `additionalProperties`
        # apply only when it IS an object, which is exactly the gated case.
        #
        # PUBLIC because it is the ONE source of the advertised envelope for
        # both surfaces: #build_manifest here (the ActionCable catalog) and
        # Mcp::ToolCatalog#decorate_tool_entry (tools/list and
        # platform.describe_tool; it lived on the streamable controller until
        # IMP-7e84ae0ccc91), which used to hard-code a bare {"type" =>
        # "object"} on the transport real agents use (IMP-b92421fb7c59).
        # Rebuilt per call, so a caller that assigns it into a tool entry
        # gets its own hash.
        def default_output_schema
          {
            "type" => "object",
            "properties" => {
              "success" => {
                "type" => "boolean",
                "description" => "False on refusal or failure; see `error`."
              },
              "error" => {
                "type" => "string",
                "description" => "Failure message. Present only when success is false."
              },
              # HIER-P2I. A refusal ABOUT THE CALLER, not about the action, is
              # otherwise distinguishable only by reading `error` prose — the
              # exact defect IMP-e809396f9eda records for the pending envelope.
              "refusal" => {
                "type" => "string",
                "description" => "Refusal discriminator. Present only when success is false and the " \
                                 "call was refused for WHO is calling rather than what was asked. " \
                                 "\"canonical_principal\": the acting agent is a global canonical " \
                                 "(a template, never an executing principal) — clone it into an " \
                                 "account and run the clone."
              },
              "canonical_slug" => {
                "type" => "string",
                "description" => "The refused canonical's slug. Present only with " \
                                 "refusal=\"canonical_principal\"; it is the canonical_slug to pass " \
                                 "to agent_management create_agent."
              },
              "data" => {
                "description" => "Action payload on success. For an approval-gated action " \
                                 "parked by the autonomy gate it is the pending envelope below " \
                                 "and NOTHING has been applied yet.",
                "additionalProperties" => true,
                "properties" => ::Ai::Tools::BaseTool::PENDING_RESULT_PROPERTIES.deep_dup
              }
            },
            "required" => ["success"]
          }
        end

        # THE ONE PRODUCER of the availability refusal, exposed for the OTHER
        # transport (IMP-8e3bd13d0136).
        #
        # #execute_tool refuses a de-advertised action inline (the streamable-HTTP
        # tools/call path for a "platform."-prefixed name). The OTHER caller —
        # Mcp::ProtocolService#invoke_tool, which serves the ActionCable channel
        # and the HTTP else-branch for an unprefixed name — never reaches
        # #execute_tool for such a name at all: it dispatches off a manifest read
        # from a Mcp::RegistryService, the lookup misses, and the call used to
        # die as a JSON-RPC ToolNotFoundError (-32601). Operator ruling
        # 2026-09-02 (D15): both transports answer a de-advertised action with
        # the RESULT envelope; ToolNotFoundError is reserved for names the
        # platform has never registered.
        #
        # WHY that lookup misses, stated precisely because the obvious reading
        # ("the registry carries only the ADVERTISED manifests") is FALSE:
        # #register_all! constructs a ::Mcp::RegistryService of its own on its
        # first line and DISCARDS it, while ProtocolService queries the instance
        # built in its own #initialize. RegistryService keeps `@tools` per
        # instance, rehydrates only AI-agent manifests (#load_existing_tools),
        # and never reads its Redis mirror back in #get_tool. So NO platform
        # manifest is visible on that path — advertised or not — which is why
        # this seam RESOLVES the name itself rather than trusting the miss to
        # mean "de-advertised". The residual gap that leaves (an ADVERTISED
        # platform action is un-invocable there too, for that same plumbing
        # reason) is pre-existing, out of this change's scope, and NOT what this
        # method decides: it returns nil for an advertised name.
        #
        # BYTE-EQUALITY IS THE POINT, and it is structural rather than asserted:
        # this method resolves through the same #find_tool_class, gates through
        # the same #enforce_permission!, and answers through the same
        # #unadvertised_refusal that #execute_tool uses, so the two transports
        # cannot drift into two sentences that mean the same thing. Pinned by
        # spec/services/mcp/protocol_service_advertisement_parity_spec.rb.
        #
        # ORDERING PARITY, and the reason this takes a `user:`. #execute_tool
        # gates on the caller's permission BEFORE it refuses on availability, so
        # a caller who may not run the action is answered PermissionDeniedError
        # there and learns nothing about which extensions this control plane has
        # loaded. Without the same gate here the other transport would answer
        # that caller the availability envelope — a NEW divergence in place of
        # the one being closed. The availability answer is computed first only
        # because it is pure; it is returned only after #enforce_permission! has
        # been cleared, so a caller of this method must be ready for
        # PermissionDeniedError.
        #
        # Returns nil for a name that RESOLVES to no tool class — that is the
        # "never registered" case, and the caller must keep raising there — and
        # nil for an action that IS advertised, which leaves the caller's
        # pre-existing ToolNotFoundError untouched.
        def unavailable_action_refusal(tool_id, supplied_action: nil, user: nil)
          tool_name = tool_id.to_s.delete_prefix("#{TOOL_ID_PREFIX}.")
          tool_class = find_tool_class(tool_name)
          return nil unless tool_class

          refusal = unadvertised_refusal(tool_name: tool_name, tool_class: tool_class,
                                         effective_action: supplied_action)
          return nil unless refusal

          # Normalized to the PREFIXED id so the denial sentence is byte-equal
          # across transports: #execute_tool is only ever handed the prefixed
          # form, while this seam is reachable under either.
          enforce_permission!(user: user, tool_class: tool_class,
                              tool_id: "#{TOOL_ID_PREFIX}.#{tool_name}")
          refusal
        end

        private

        # True when the tool routes on an :action param — one tool class serving
        # several registry keys, or declaring :action in its own schema. For
        # these the action, not the tool name, decides what actually runs.
        def action_dispatched?(tool_class)
          tool_class.definition[:parameters]&.key?(:action) ||
            tool_class.action_definitions.size > 1
        end

        # Which callers must have the action they run pinned to the tool name
        # they invoked. Derived from what the call CARRIES rather than from a
        # flag the call site remembered to set: instance_authorized is opt-in,
        # and the second entry point into execute_tool (Mcp::ProtocolService's
        # platform_tool branch, reached for any tool name that is not
        # "platform."-prefixed) passes no principal at all, so an opt-in fence
        # simply never ran there. Keyed on the principal, an omitted flag now
        # tightens instead of opening a door. (IMP-3024cfb1d850)
        #
        #   user present     unpinned, and byte-for-byte unchanged. The original
        #                    reasoning was that authorization here is per-CLASS —
        #                    one REQUIRED_PERMISSION covering every sibling action,
        #                    so smuggling a sibling is isomorphic to invoking it by
        #                    name and gains no privilege. That is no longer true in
        #                    general: tools carrying an ACTION_PERMISSIONS map
        #                    (every one in extensions/system, and in core
        #                    Ai::Tools::AgentAutonomyTool since IMP-e8adfcfcab9b)
        #                    price their actions differently, so a smuggled sibling
        #                    CAN be the more privileged one. Those tools are
        #                    therefore responsible for gating on the action that
        #                    RUNS, which is what their maps do — this pin is not
        #                    what protects them, and adding one here would break
        #                    the legitimate multi-action user call.
        #   mcp_agent        the LLM tool-calling path, where an agent legitimately
        #                    supplies :action for a class that declares one
        #                    (AgentAutonomyTool, ProvisioningTool) — unpinned.
        #   neither          nothing bounds the action: enforce_permission! returns
        #                    without a check whenever REQUIRED_PERMISSION is nil, and
        #                    for an instance principal the name is all may_invoke?
        #                    ever saw. The invoked name is the only bound left, so
        #                    hold the action to it.
        def action_pinned_to_name?(user:, mcp_agent:, instance_authorized:)
          instance_authorized || (user.nil? && mcp_agent.nil?)
        end

        # SECURITY (IMP-e8138c2714fb): make the action that RUNS agree with the
        # tool name the caller's grant was checked against.
        #
        # An instance principal is authorized by NAME: the streamable controller
        # runs Mcp::Principal#may_invoke?(tool_name) — grant globs plus the
        # destructive deny overlay — and everything downstream trusts that one
        # verdict (enforce_permission! returns early below, and a grant-gated
        # instance skips the tool's own per-action permission map). A
        # multi-action tool then ran whatever :action the caller supplied, so a
        # benign grant reached a destroy-shaped sibling on the same class:
        # platform.read_shared_memory carrying action "delete_shared_memory" is
        # a delete the overlay would never have granted by name.
        #
        # The flattened MCP surface advertises one tool name PER ACTION
        # (PlatformApiToolRegistry.tool_definitions), so a legitimate caller
        # never needs to disagree — it invokes the action's own name and the
        # branch above injects it. Requiring agreement is therefore the whole
        # fix: the executed action is, by construction, the name may_invoke?
        # already cleared.
        #
        # The same reasoning covers a call carrying no principal at all, which is
        # how Mcp::ProtocolService reaches this method (its platform_tool branch
        # passes none). That branch is INERT at runtime today — invoke_tool
        # hard-denies user.nil? before it, so nothing principal-less arrives here.
        # This is insurance for the next call site, not a live hole being closed:
        # if that deny is ever relaxed, the classes whose REQUIRED_PERMISSION is
        # nil would run a caller-supplied action with no check at all. See
        # action_pinned_to_name? for which callers are held to this, and why a
        # user principal is not.
        # principal: is for the operator reading the log — "instance" (grant-gated
        # mTLS node) or "none" (a call carrying no principal). It stays OUT of the
        # exception message on purpose: both entry points must refuse identically,
        # and mcp_protocol_service_action_scope_spec.rb asserts that equality.
        def enforce_action_scope!(tool_name:, tool_id:, tool_class:, supplied_action:, principal: "none")
          return unless action_dispatched?(tool_class)

          expected = ACTION_ALIASES.fetch(tool_name, tool_name)
          return if supplied_action.to_s == expected

          Rails.logger.warn(
            "[McpPlatformTool] Refused out-of-scope action: principal=#{principal} " \
            "tool=#{tool_id} supplied_action=#{supplied_action} expected=#{expected}"
          )
          raise ::Mcp::ProtocolService::PermissionDeniedError,
                "Action '#{supplied_action}' is not permitted for #{tool_id}: this caller is " \
                "authorized per tool name, so #{tool_id} may only run '#{expected}'"
        end

        # SCOPE OF THIS METHOD — deliberately stated narrowly, because a comment
        # that claims more coverage than it has is how the next false citation
        # gets written. This method enforces exactly ONE check: the
        # REQUIRED_PERMISSION floor, against the User. It carries TWO exemptions
        # that skip that check outright — `required.nil?` (a tool class declaring
        # no floor is waved through entirely; that wave-through is the defect the
        # SECURITY comments on ProvisioningTool, GovernanceTool, CoordinationTool,
        # SelfImprovementTool, AgentAutonomyTool and AgentMemoryManagementTool
        # exist to warn about) and `instance_authorized`.
        #
        # It is NOT the whole authorization ladder and must not be cited as one.
        # The other rungs live elsewhere:
        #   * Mcp::Principal#may_invoke? — grant globs + DESTRUCTIVE_TOOL_PATTERNS,
        #     applied at streamable_http_controller.rb:604
        #   * enforce_action_scope! — this file, called from #execute_tool's
        #     action_pinned_to_name? branch
        #   * Mcp::PermissionValidator — the ActionCable arm, protocol_service.rb:195
        #   * per-action ACTION_PERMISSIONS maps in the tool classes themselves
        #   * BaseTool#enforce_instance_deny_overlay!, re-applied at nested hops
        #
        # THERE IS NO TOKEN-LEVEL NARROWING, and nothing downstream should be
        # written as though there were. This method used to carry a third check —
        # a "token permission intersection" reading a `token:` kwarg — that no
        # caller ever passed: all four call sites (streamable_http_controller,
        # agent_tool_bridge_service, skill_recipe_runner, protocol_service)
        # omitted it, so the branch was dead on every path while reading as a
        # control. Deleted in IMP-a18f5a8ed393; it was the second instance of that
        # shape after `capability_scope`.
        #
        # It was dead on THIS path regardless. The only class that would have
        # SATISFIED the branch is UserToken (it has both #permissions and
        # #has_permission?), and no UserToken reaches this method. The only arm
        # that authenticates one ON A PATH LEADING HERE is
        # application_cable/connection.rb#authenticate_legacy_user (:155), whose
        # first act is a [DEPRECATED] warning, and it builds its execution_options
        # WITHOUT any token (mcp_channel.rb:121-126). Other arms authenticate a
        # UserToken elsewhere in the app; none of them reach the registrar.
        #
        # CORRECTION. An earlier revision of this comment also claimed
        # `create_token_for_user` "has no production callers" and that UserToken is
        # "never minted in production". BOTH WERE FALSE, and neither was ever load
        # bearing for this path. An extension mints impersonation UserTokens on a
        # live path and reads them back through UserToken.authenticate /
        # .find_by_token. What is true is narrower and is the only part to rely on:
        # no UserToken is passed to THIS method. Do not restate the mint as dead.
        #
        # UserToken#has_permission? itself no longer carries a snapshot
        # short-circuit either — it resolves live from the user (IMP-f86b6be57e74),
        # so its `permissions` column is not an authorization input on any path.
        #
        # Building a real one is a NEW authorization layer, not a rewiring: the
        # token the MCP path resolves is a Doorkeeper::AccessToken, which carries
        # OAuth `scopes` and responds to neither #permissions nor
        # #has_permission?. Any scope→permission mapping must cover all EIGHT
        # scopes Doorkeeper ACCEPTS — read, write, admin, billing, users,
        # webhooks, workflows, files (config/initializers/doorkeeper.rb:124;
        # default `:read` at :121) — NOT the four ADVERTISED at
        # well_known_controller.rb:48 (read, write, workflows, files). That gap is
        # the trap: a token minted with `admin` falls straight through a map built
        # from the advertised list. A genuine intersection therefore needs that
        # mapping plus a mint-time surface to narrow a token, neither of which
        # exists. Do not re-add the branch without both.

        # Nil when every name that could run is advertised; otherwise the
        # refusal envelope for the first one that is not. Blank names are
        # dropped (a single-action tool carries no :action), and the two names
        # collapse when they agree, which is the common case.
        #
        # THE MESSAGE SAYS ONLY WHAT THIS PREDICATE ESTABLISHES: that the
        # platform does not offer the action, and that tools/list is filtered by
        # the same predicate (PlatformApiToolRegistry.available_tools ->
        # .advertised_action?, the identical call this method makes), so the
        # caller can reconcile the two surfaces. It deliberately does NOT tell
        # the wire WHY an action is de-advertised. Today every .permitted? /
        # .action_advertised? override on the tree is a bare `true` or a
        # `defined?(::Const)` probe, so "de-advertised" and "backing extension
        # absent" happen to coincide — but nothing in the suite pins that shape,
        # and the first override to gate on a flag or a tier would turn a
        # sentence shipped to MCP clients into a false one with no failing test.
        #
        # THE SEAM IS NOT THE ONLY DOOR, and the per-class guards inside
        # DockerProvisioningTool#call / DiskImageOperatorTool#call are retained
        # as defence in depth (pinned by
        # spec/services/ai/tools/extension_backed_tool_body_guard_spec.rb) for
        # the three live paths that construct a platform tool without passing
        # through here:
        #
        #   * Api::V1::System::Platform::StorageMigrationsController
        #     #call_mcp_action (extensions/system) — resolves via
        #     PlatformApiToolRegistry.find_tool off the RAW map, then constructs.
        #   * System::Ai::Skills::BaseSkillExecutor#tool (extensions/system) —
        #     nests a platform tool directly.
        #   Both are inert as availability doors only because they SHIP INSIDE
        #   extensions/system: wherever they are reachable, ::System is defined,
        #   so the class-level guard is satisfied by construction. That is a
        #   property of where they live, not a check they perform.
        #   * McpTool#execute (server/app/models/mcp_tool.rb), the mcp_tools ROW
        #     path behind Api::V1::McpToolsController — dispatches off a stored
        #     row, so a row written before the platform dropped into core mode
        #     survives until the next .sync_to_database! deletes it as stale.
        def unadvertised_refusal(tool_name:, tool_class:, effective_action: nil)
          names = [tool_name, effective_action].map(&:to_s).reject(&:blank?).uniq
          unavailable = names.reject { |name| PlatformApiToolRegistry.advertised_action?(name, tool_class) }
          return nil if unavailable.empty?

          { success: false,
            error: "Tool not available: #{unavailable.first} is not offered by this control plane. " \
                   "tools/list is filtered by the same advertisement predicate, which is why the " \
                   "action is absent there too." }
        end

        def enforce_permission!(user:, tool_class:, tool_id:, instance_authorized: false)
          required = tool_class::REQUIRED_PERMISSION
          return if required.nil?

          # An instance principal (mTLS node cert, no User) that reached here was
          # ALREADY grant-gated by the streamable controller's may_invoke? check
          # (see streamable_http_controller.rb:604): that grant is what stands in
          # for its authorization. The grant is NAME-scoped, and enforce_action_scope!
          # above now holds the executed action to that same name, so what the
          # grant bounds is what runs. The intended downstream user:nil path is the
          # internal-caller bypass. Without this it was hard-denied -32001 for
          # every dev_next_task/dev_complete_task. (BUG-R — sibling of BUG-Q.)
          return if instance_authorized

          unless user
            raise ::Mcp::ProtocolService::PermissionDeniedError,
                  "Authentication required for #{tool_id}"
          end

          unless user.has_permission?(required)
            raise ::Mcp::ProtocolService::PermissionDeniedError,
                  "Permission denied for #{tool_id}: requires '#{required}'"
          end
        end

        # The permission a CLASS-level manifest publishes. register_all! registers
        # one manifest per tool class (tool_id "platform.#{definition[:name]}"),
        # not one per action, so the per-action resolver is only the right
        # question for a class that has exactly one action.
        #
        # For an :action-dispatched class, definition[:name] is an UMBRELLA
        # ("code_memory", "agent_management") covering several differently-priced
        # verbs, and asking "what gates this action?" of an umbrella is a category
        # error. It happens to return the floor for all 66 registry classes today
        # — no umbrella name is one of its own ladder keys, so the guard below
        # moves nothing at present — but if one ever were, resolving it would
        # publish that single verb's entry as the bar for REACHING the whole
        # class. required_permissions is CONJUNCTIVE
        # (Mcp::PermissionValidator#missing_required_permissions subtracts it from
        # the user's set), so that would deny — and via #tool_visible_to? hide —
        # the class from a caller legitimately entitled to its read siblings.
        # That is the same harm as publishing the union of the ladder, arrived at
        # by accident, which is why this is a guard and not a comment.
        #
        # The floor is the minimum needed to REACH a multi-action class; the
        # tool's own ACTION_PERMISSIONS check supplies the per-action bar after
        # that, and the mcp_tools rows carry the per-action value.
        #
        # Reuses #action_dispatched? — the same predicate execute_tool uses to
        # decide whether the tool routes on :action — so the two cannot drift.
        def manifest_permission_for(tool_class)
          return tool_constant(tool_class, :REQUIRED_PERMISSION) if action_dispatched?(tool_class)

          resolved_permission_for(tool_class, tool_class.definition[:name])
        end

        # Read a tool class's permission constant, or nil.
        #
        # `const_defined?` and `Klass::CONST` are NOT equivalent, and the gap is
        # not academic here: const_defined? answers true for a `private_constant`
        # and for a same-named TOP-LEVEL constant (Object is in every class's
        # ancestry), where `::` raises NameError. A bare
        # `const_defined? ? Klass::CONST : nil` therefore clears its own guard and
        # then raises on the next token — and in sync_to_database! that NameError
        # is caught by the per-action `rescue`, which skips the action, leaves it
        # out of `synced_names`, and lets the stale sweep DELETE its row. One
        # stray top-level ACTION_PERMISSIONS (a spec file assigning a constant
        # inside an RSpec block is enough) would empty the platform server's
        # mcp_tools table, visible only as a wall of log warnings.
        #
        # Nothing in the registry trips this today — no class has a private or
        # inherited permission constant — so this is insurance, and it also keeps
        # the pre-existing `tool_class::REQUIRED_PERMISSION rescue nil` behavior
        # this method replaced: an unreadable constant reads as absent, it does
        # not take the row down with it.
        #
        # Inheritance stays ENABLED (see .resolved_permission_for) — but only up
        # the tool class's OWN ancestry. Object is skipped explicitly: it is an
        # ancestor of every class, so including it is exactly the top-level
        # contamination described above, and `Klass::CONST` does not reach it
        # either (Ruby dropped top-level lookup through `::`). Matching the `::`
        # semantics this replaced is the point.
        def tool_constant(tool_class, const_name)
          owner = tool_class.ancestors.find do |mod|
            mod != Object && mod.const_defined?(const_name, false)
          end
          return nil unless owner

          owner.const_get(const_name, false)
        rescue NameError
          nil
        end

        def upsert_mcp_tool!(mcp_server, name, description, input_schema, permission_level, required_permissions)
          tool = mcp_server.mcp_tools.find_or_initialize_by(name: name)
          tool.assign_attributes(
            description: description,
            input_schema: input_schema,
            enabled: true,
            permission_level: permission_level,
            required_permissions: required_permissions
          )
          tool.save!
        end

        def build_manifest(tool_class)
          definition = tool_class.definition
          {
            "name" => definition[:name],
            "description" => definition[:description],
            "type" => "platform_tool",
            "version" => "1.0.0",
            "category" => "platform",
            "permission_level" => "account",
            "required_permissions" => [manifest_permission_for(tool_class)].compact,
            "inputSchema" => convert_to_json_schema(definition[:parameters]),
            "outputSchema" => default_output_schema,
            "metadata" => { "tool_class" => tool_class.name },
            "rate_limited" => true,
            "rate_limit" => { "max_calls" => 20, "window_seconds" => 60 }
          }
        end

        # Delegated to Ai::Tools::ParameterSchema so this and the streamable-HTTP
        # controller's tools/list schema cannot drift. The local copy this
        # replaced kept only `type` and `description`, dropping every `enum`,
        # `items`, `default` and nested `properties` a tool declared
        # (IMP-e809396f9eda).
        def convert_to_json_schema(parameters)
          ::Ai::Tools::ParameterSchema.build(parameters)
        end

        # THE RESOLUTION SET, deliberately UNFILTERED (IMP-5039d026da0d).
        #
        # #find_tool_class falls back to this list to resolve a tools/call.
        # Filtering it here would make a de-advertised action fail RESOLUTION,
        # which #execute_tool reports as an ArgumentError "Unknown platform
        # tool" — and the streamable controller re-routes that message to the
        # INTROSPECTION registrar, so the caller would end up with whatever that
        # says about a name it has never heard of. Availability is refused a
        # step later instead, by #unadvertised_refusal, which names the action
        # and the reason. Advertisement filtering for the ActionCable catalog
        # lives in #advertised_tool_classes.
        def tool_classes
          @tool_classes ||= PlatformApiToolRegistry.all_tools.values.uniq.filter_map do |class_name|
            class_name.constantize
          rescue NameError => e
            Rails.logger.warn "[McpPlatformToolRegistrar] Tool class not found: #{class_name} - #{e.message}"
            nil
          end
        end

        # The subset of #tool_classes the platform may ADVERTISE. Per-CLASS, not
        # per-action: #register_all! publishes one manifest per class keyed on
        # `definition[:name]`, so a mixed class like
        # Ai::Tools::DiskImageOperatorTool (some actions extension-backed, one
        # core-only) must keep its manifest — its per-action hook is applied on
        # the surfaces that are per-action (tools/list, the mcp_tools rows).
        # Not memoized: #tool_classes caches constant RESOLUTION, which is
        # stable, while availability is not — an extension engine can register
        # after boot, and a memo here would freeze a core-mode answer.
        #
        # NO INVOCATION CONSEQUENCE ON THE CABLE PATH — corrected under
        # IMP-8e3bd13d0136, because what stood here was false. This filter was
        # described as making an unavailable tool un-invocable on the
        # ActionCable channel. #register_all! is indeed the only thing that
        # would publish platform manifests into a Mcp::RegistryService —
        # `command grep -rn "McpPlatformToolRegistrar.register_all!"
        # <repo>/server/app <repo>/server/db <repo>/server/lib <repo>/worker
        # <repo>/extensions` finds two call sites outside spec/:
        # app/channels/mcp_channel.rb and a seeded KB article's sample code —
        # but it BUILDS that RegistryService itself and discards it, while
        # Mcp::ProtocolService#invoke_tool reads the instance it built in its
        # own #initialize. So this filter does not reach that path at all: every
        # platform name misses there, advertised or not. The de-advertised half
        # is answered by .unavailable_action_refusal with the same envelope the
        # HTTP seam returns; the advertised half is a separate, pre-existing
        # plumbing gap that still raises ToolNotFoundError. The streamable-HTTP
        # tools/call path is where this filter DOES have an invocation
        # counterpart, since IMP-128fe17fd8c8: it RESOLVES through the
        # unfiltered #find_tool_class, then refuses in #execute_tool via
        # #unadvertised_refusal — a result envelope rather than a raise, and per
        # ACTION rather than per class.
        def advertised_tool_classes
          tool_classes.select { |tool_class| PlatformApiToolRegistry.advertised_class?(tool_class) }
        end

        def find_tool_class(tool_name)
          # Look up via the registry hash first (handles multi-action tools
          # where multiple registry keys map to one tool class)
          class_name = PlatformApiToolRegistry.all_tools[tool_name]
          if class_name
            return class_name.constantize rescue nil
          end

          # Fall back to matching by definition name (single-action tools)
          tool_classes.find { |klass| klass.definition[:name] == tool_name }
        end
      end
    end
  end
end
