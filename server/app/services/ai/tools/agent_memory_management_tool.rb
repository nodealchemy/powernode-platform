# frozen_string_literal: true

module Ai
  module Tools
    class AgentMemoryManagementTool < BaseTool
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
              type: "object",
              required: ["key", "value"],
              properties: {
                key: { type: "string", description: "Memory key (dot-notation supported)" },
                value: { description: "Value to store (string, number, object, or array)" },
                ttl_seconds: { type: "integer", description: "Time-to-live in seconds (optional)" },
                importance: { type: "number", description: "Importance score 0-1 (default 0.5)" },
                tags: { type: "array", items: { type: "string" }, description: "Tags for categorization" }
              }
            }
          },
          "agent_forget" => {
            description: "Remove or soft-decay a memory key from the agent's private pool",
            parameters: {
              type: "object",
              required: ["key"],
              properties: {
                key: { type: "string", description: "Memory key to forget" },
                soft: { type: "boolean", description: "If true, decay importance instead of deleting (default false)" }
              }
            }
          },
          "agent_reflect" => {
            description: "Trigger on-demand STM consolidation and summary generation (rate-limited: 1 per 15 minutes)",
            parameters: {
              type: "object",
              properties: {}
            }
          },
          "agent_recall" => {
            description: "Semantic search across agent's private memory pool and optionally team_shared pools",
            parameters: {
              type: "object",
              required: ["query"],
              properties: {
                query: { type: "string", description: "Natural language search query" },
                include_team: { type: "boolean", description: "Also search team_shared pools (default false)" },
                limit: { type: "integer", description: "Maximum results to return (default 10)" }
              }
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
