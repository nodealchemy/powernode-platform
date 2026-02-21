# frozen_string_literal: true

module Ai
  module Tools
    class MemoryTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      def self.definition
        {
          name: "memory_management",
          description: "Read, write, search, consolidate shared memory, or get memory stats",
          parameters: {
            action: { type: "string", required: true, description: "Action: read_shared_memory, write_shared_memory, search_memory, consolidate_memory, memory_stats, list_pools" },
            pool_id: { type: "string", required: false, description: "Memory pool ID" },
            key: { type: "string", required: false, description: "Data key (dot-separated for nesting)" },
            value: { type: "object", required: false, description: "Value to write (for write action)" },
            query: { type: "string", required: false, description: "Search query (for search_memory)" },
            tier: { type: "string", required: false, description: "Memory tier filter" },
            agent_id: { type: "string", required: false, description: "Target agent ID" },
            limit: { type: "integer", required: false, description: "Result limit" }
          }
        }
      end

      def self.action_definitions
        {
          "write_shared_memory" => {
            description: "Write a value to shared memory in a specific pool",
            parameters: {
              pool_id: { type: "string", required: false, description: "Memory pool ID (default: 'default')" },
              key: { type: "string", required: true, description: "Data key (dot-separated for nesting)" },
              value: { type: "object", required: true, description: "Value to write" }
            }
          },
          "read_shared_memory" => {
            description: "Read a value from shared memory in a specific pool",
            parameters: {
              pool_id: { type: "string", required: false, description: "Memory pool ID (default: 'default')" },
              key: { type: "string", required: true, description: "Data key to read" }
            }
          },
          "search_memory" => {
            description: "Search across memory tiers by keyword query",
            parameters: {
              query: { type: "string", required: true, description: "Search query" },
              agent_id: { type: "string", required: false, description: "Target agent ID" },
              limit: { type: "integer", required: false, description: "Max results (default 10)" }
            }
          },
          "consolidate_memory" => {
            description: "Run memory consolidation pipeline for an agent (promotes across tiers)",
            parameters: {
              agent_id: { type: "string", required: false, description: "Target agent ID" }
            }
          },
          "memory_stats" => {
            description: "Get memory usage statistics across all tiers",
            parameters: {
              agent_id: { type: "string", required: false, description: "Agent ID (omit for account-wide stats)" }
            }
          },
          "list_pools" => {
            description: "List all memory pools in the current account",
            parameters: {}
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "read_shared_memory"
          pool = resolve_pool(params[:pool_id])
          data = pool.read_data(params[:key], agent_id: agent&.id)
          { success: true, key: params[:key], value: data }
        when "write_shared_memory"
          pool = resolve_pool(params[:pool_id])
          pool.write_data(params[:key], params[:value], agent_id: agent&.id)
          { success: true, key: params[:key], written: true }
        when "search_memory" then search_memory(params)
        when "consolidate_memory" then consolidate_memory(params)
        when "memory_stats" then memory_stats(params)
        when "list_pools" then list_pools(params)
        else
          { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Memory pool not found" }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      end

      private

      def resolve_pool(pool_id)
        return account.ai_memory_pools.find_by!(pool_id: pool_id) if pool_id.present? && pool_id != "default"

        # Find or create a default pool for the account
        account.ai_memory_pools.find_or_create_by!(pool_id: "default") do |pool|
          pool.name = "Default Memory Pool"
          pool.pool_type = "shared"
          pool.scope = "persistent"
          pool.data = {}
          pool.access_control = {}
          pool.metadata = {}
          pool.retention_policy = {}
          pool.version = 1
        end
      end

      def search_memory(params)
        return { success: false, error: "Query is required" } if params[:query].blank?

        target_agent = params[:agent_id].present? ? account.ai_agents.find_by(id: params[:agent_id]) : agent
        return { success: false, error: "Agent not found" } unless target_agent

        # RouterService.semantic_search requires a vector embedding, not raw text.
        # Fall back to keyword-based search across memory tiers.
        limit = (params[:limit] || 10).to_i
        query = params[:query]

        sanitized = ActiveRecord::Base.sanitize_sql_like(query)
        results = []
        # Search short-term memory (memory_key + memory_value jsonb)
        stm = Ai::AgentShortTermMemory.where(agent_id: target_agent.id)
                .where("memory_key ILIKE :q OR memory_value::text ILIKE :q", q: "%#{sanitized}%")
                .limit(limit)
        results += stm.map { |m| { tier: "short_term", key: m.memory_key, value: m.memory_value, created_at: m.created_at&.iso8601 } }

        # Search compound learnings (long-term)
        ltm = Ai::CompoundLearning.where(account: account)
                .where("content ILIKE ?", "%#{query}%")
                .active.limit(limit)
        results += ltm.map { |l| { tier: "long_term", content: l.content, category: l.category, created_at: l.created_at&.iso8601 } }

        { success: true, query: query, results: results, count: results.size }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def consolidate_memory(params)
        target_agent = params[:agent_id].present? ? account.ai_agents.find_by(id: params[:agent_id]) : agent
        return { success: false, error: "Agent not found" } unless target_agent

        # MaintenanceService handles tier promotion: short_term → long_term → shared
        maintenance = Ai::Memory::MaintenanceService.new(account: account)
        result = maintenance.run_consolidation_pipeline(agent: target_agent)
        { success: true, consolidated: result }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def memory_stats(params = {})
        target_agent = params[:agent_id].present? ? account.ai_agents.find_by(id: params[:agent_id]) : agent
        if target_agent
          router = Ai::Memory::RouterService.new(agent: target_agent, account: account)
          stats = router.stats
          { success: true, stats: stats }
        else
          # Return account-wide stats
          stm_count = Ai::AgentShortTermMemory.joins(:agent).where(ai_agents: { account_id: account.id }).count
          ltm_count = Ai::CompoundLearning.where(account: account).active.count
          shared_count = Ai::SharedKnowledge.where(account: account).count
          pools_count = Ai::MemoryPool.where(account_id: account.id).count

          { success: true, stats: { short_term: stm_count, long_term: ltm_count, shared: shared_count, pools: pools_count } }
        end
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def list_pools(params = {})
        pools = Ai::MemoryPool.where(account_id: account.id).limit(50)
        {
          success: true,
          pools: pools.map { |p| { id: p.id, pool_id: p.pool_id, name: p.name, pool_type: p.pool_type } }
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end
    end
  end
end
