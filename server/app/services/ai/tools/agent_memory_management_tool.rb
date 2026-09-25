# frozen_string_literal: true

module Ai
  module Tools
    class AgentMemoryManagementTool < BaseTool
      # SECURITY (IMP-6fbfeff384fa): REQUIRED_PERMISSION was inherited as nil
      # from BaseTool, and McpPlatformToolRegistrar#enforce_permission! opens
      # with `return if required.nil?` — ABOVE the authentication raise and the
      # has_permission? raise. So these four actions ran without either.
      #
      # Unlike its four siblings in that sweep this tool gets ONE constant and
      # deliberately NO ACTION_PERMISSIONS map, because there is one decision
      # here rather than four: every action is structurally self-scoped. No
      # action takes an agent_id or pool parameter, and
      # Ai::Memory::AgentManagedMemoryService#find_private_pool resolves the pool
      # from the CALLING agent identity — which an MCP caller cannot choose
      # (StreamableHttpController#mcp_client_agent binds it to the session, and
      # the agent loop passes the agent itself). agent_recall's team search is
      # likewise clamped to pools whose access_control lists that same agent.
      # Splitting reads from writes would invent a distinction the surface does
      # not have.
      #
      # The floor is what the sibling MCP surface over the SAME Ai::MemoryPool
      # model asks — Ai::Tools::MemoryTool::REQUIRED_PERMISSION, which gates
      # write_shared_memory/read_shared_memory/search_memory and friends. The
      # spec asserts the two are equal so they cannot drift apart.
      #
      # Two nearby controllers are deliberately NOT treated as the twin:
      #
      #   Api::V1::Ai::MemoryPoolsController (read_data → ai.memory_pools.read,
      #     write_data/delete_data → ai.memory_pools.manage) operates on the same
      #     Ai::MemoryPool model but addresses ARBITRARY pools by :id, including
      #     other agents' — a cross-pool administrative surface these four
      #     actions structurally cannot reach. Adopting its manage bar would take
      #     an agent's own memory away from every member-tier account without
      #     closing anything this tool can actually do.
      #
      #   Api::V1::Ai::AgentMemoryController (ai.memory.read / ai.memory.write)
      #     is the closer-sounding one and is named here so the next reader does
      #     not have to re-derive why it was passed over: it drives
      #     Ai::PersistentContext through ContextPersistenceService — a different
      #     store from the Ai::MemoryPool rows AgentManagedMemoryService writes —
      #     and it too addresses arbitrary agents by :agent_id.
      REQUIRED_PERMISSION = "ai.agents.read"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "agent_forget", mutating: true,
                                     returns: "the key, forgotten true or false, and mode (hard_delete or soft_decay) or a reason (no_pool, key_not_found)"
      declare_action "agent_recall", mutating: false,
                                     returns: "results (key, value, importance, relevance, tags, pool_id, pool_type), highest relevance first, and count",
                                     see_also: {
                                       "search_memory" => "keyword search of an agent's short-term memory and the account's compound learnings",
                                       "query_learnings" => "compound learnings recorded across the account",
                                       "search_knowledge" => "account shared knowledge entries",
                                       "query_knowledge_base" => "documents ingested into a RAG knowledge base",
                                       "search_knowledge_graph" => "knowledge graph nodes and relations"
                                     }
      declare_action "agent_reflect", mutating: true,
                                      returns: "reflected true with entries_reviewed and up to 10 summary lines, or reflected false with a reason (no_pool, cooldown with retry_after, no_entries_to_consolidate)"
      declare_action "agent_remember", mutating: true,
                                       returns: "the key, stored: true and the private pool's pool_id"

      def self.definition
        {
          name: "agent_memory_management",
          description: "Agent-managed memory operations: remember, forget, reflect, recall",
          parameters: { type: "object", properties: {} }
        }
      end

      def self.action_definitions
        {
          "agent_remember" => {
            description: "Store a key-value pair in the calling agent's private memory pool, with optional TTL, importance and tags. " \
                         "The pool is created on first use and holds at most 500 keys; past that, the least recently updated keys are evicted. " \
                         "An embedding of the key and value, when one can be generated, is stored for agent_recall.",
            parameters: {
              key: { type: "string", required: true, description: "Memory key (dot-notation supported)" },
              value: { type: "string", required: true, description: "Value to store (string, number, object, or array)" },
              ttl_seconds: { type: "integer", required: false, description: "Time-to-live in seconds (optional)" },
              importance: { type: "number", required: false, description: "Importance score 0-1 (default 0.5)" },
              tags: { type: "array", required: false, description: "Tags for categorization" }
            }
          },
          "agent_forget" => {
            description: "Remove or soft-decay a memory key in the calling agent's private pool. " \
                         "soft: true multiplies the key's importance by 0.1 (floor 0.01) instead of deleting it.",
            parameters: {
              key: { type: "string", required: true, description: "Memory key to forget" },
              soft: { type: "boolean", required: false, description: "If true, decay importance instead of deleting (default false)" }
            }
          },
          "agent_reflect" => {
            description: "Review the calling agent's private pool and summarise its frequently recalled entries. " \
                         "It lists entries recalled at least twice as text lines and records the reflection time; it does not call a model or move data between tiers. " \
                         "Rate-limited to once per 15 minutes per pool.",
            parameters: {}
          },
          "agent_recall" => {
            description: "Search the calling agent's private memory pool, the entries it stored with agent_remember. " \
                         "Ranks by embedding similarity, falling back to keyword overlap when an embedding is missing, and drops results below 0.5 relevance. " \
                         "include_team also searches team_shared pools the agent is listed on or that are public; each hit's access count is incremented.",
            parameters: {
              query: { type: "string", required: true, description: "Natural language search query" },
              include_team: { type: "boolean", required: false, description: "Also search team_shared pools (default false)" },
              limit: { type: "integer", required: false, description: "Maximum results to return (default 10)" }
            }
          }
        }
      end

      def call(params)
        case params[:action]
        when "agent_remember" then agent_remember(params)
        when "agent_forget" then agent_forget(params)
        when "agent_reflect" then agent_reflect(params)
        when "agent_recall" then agent_recall(params)
        else
          error_result("Unknown action: #{params[:action]}")
        end
      end

      private

      def agent_remember(params)
        service = memory_service
        ttl = params["ttl_seconds"] ? params["ttl_seconds"].to_i.seconds : nil

        result = service.remember(
          key: params["key"],
          value: params["value"],
          ttl: ttl,
          importance: (params["importance"] || 0.5).to_f,
          tags: params["tags"] || []
        )

        success_result(result)
      rescue StandardError => e
        rescued_error_result(e, message: "Failed to remember")
      end

      def agent_forget(params)
        service = memory_service
        result = service.forget(
          key: params["key"],
          soft: params["soft"] == true
        )

        success_result(result)
      rescue StandardError => e
        rescued_error_result(e, message: "Failed to forget")
      end

      def agent_reflect(params)
        service = memory_service
        result = service.reflect

        success_result(result)
      rescue StandardError => e
        rescued_error_result(e, message: "Failed to reflect")
      end

      def agent_recall(params)
        service = memory_service
        results = service.recall(
          query: params["query"],
          include_team: params["include_team"] == true,
          limit: (params["limit"] || 10).to_i
        )

        success_result({ results: results, count: results.size })
      rescue StandardError => e
        rescued_error_result(e, message: "Failed to recall")
      end

      def memory_service
        Ai::Memory::AgentManagedMemoryService.new(
          account: account,
          agent: agent
        )
      end
    end
  end
end
