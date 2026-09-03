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
      declare_action "agent_forget", mutating: true
      declare_action "agent_recall", mutating: false
      declare_action "agent_reflect", mutating: true
      declare_action "agent_remember", mutating: true

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
            description: "Store a key-value pair in the agent's private memory pool with optional TTL, importance, and tags",
            parameters: {
              key: { type: "string", required: true, description: "Memory key (dot-notation supported)" },
              value: { type: "string", required: true, description: "Value to store (string, number, object, or array)" },
              ttl_seconds: { type: "integer", required: false, description: "Time-to-live in seconds (optional)" },
              importance: { type: "number", required: false, description: "Importance score 0-1 (default 0.5)" },
              tags: { type: "array", required: false, description: "Tags for categorization" }
            }
          },
          "agent_forget" => {
            description: "Remove or soft-decay a memory key from the agent's private pool",
            parameters: {
              key: { type: "string", required: true, description: "Memory key to forget" },
              soft: { type: "boolean", required: false, description: "If true, decay importance instead of deleting (default false)" }
            }
          },
          "agent_reflect" => {
            description: "Trigger on-demand STM consolidation and summary generation (rate-limited: 1 per 15 minutes)",
            parameters: {}
          },
          "agent_recall" => {
            description: "Semantic search across agent's private memory pool and optionally team_shared pools",
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
        error_result("Failed to remember: #{e.message}")
      end

      def agent_forget(params)
        service = memory_service
        result = service.forget(
          key: params["key"],
          soft: params["soft"] == true
        )

        success_result(result)
      rescue StandardError => e
        error_result("Failed to forget: #{e.message}")
      end

      def agent_reflect(params)
        service = memory_service
        result = service.reflect

        success_result(result)
      rescue StandardError => e
        error_result("Failed to reflect: #{e.message}")
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
        error_result("Failed to recall: #{e.message}")
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
