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

      protected

      def call(params)
        case params[:action]
        when "read_shared_memory"
          pool = account.ai_memory_pools.find_by!(pool_id: params[:pool_id])
          data = pool.read_data(params[:key], agent_id: agent&.id)
          { success: true, key: params[:key], value: data }
        when "write_shared_memory"
          pool = account.ai_memory_pools.find_by!(pool_id: params[:pool_id])
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
      rescue ArgumentError => e
        { success: false, error: e.message }
      end

      private

      def search_memory(params)
        return { success: false, error: "Query is required" } if params[:query].blank?

        target_agent = params[:agent_id].present? ? account.ai_agents.find_by(id: params[:agent_id]) : agent
        return { success: false, error: "Agent not found" } unless target_agent

        router = Ai::Memory::RouterService.new(agent: target_agent, account: account)
        results = router.semantic_search(params[:query], limit: (params[:limit] || 10).to_i)
        { success: true, results: results }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def consolidate_memory(params)
        target_agent = params[:agent_id].present? ? account.ai_agents.find_by(id: params[:agent_id]) : agent
        return { success: false, error: "Agent not found" } unless target_agent

        router = Ai::Memory::RouterService.new(agent: target_agent, account: account)
        result = router.consolidate
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
          pools_count = Ai::MemoryPool.joins("INNER JOIN ai_agent_teams ON ai_memory_pools.ai_agent_team_id = ai_agent_teams.id").where(ai_agent_teams: { account_id: account.id }).count

          { success: true, stats: { short_term: stm_count, long_term: ltm_count, shared: shared_count, pools: pools_count } }
        end
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def list_pools(params = {})
        pools = Ai::MemoryPool.joins("INNER JOIN ai_agent_teams ON ai_memory_pools.ai_agent_team_id = ai_agent_teams.id")
                              .where(ai_agent_teams: { account_id: account.id })
                              .limit(50)
        {
          success: true,
          pools: pools.map { |p| { id: p.id, pool_id: p.pool_id, team_id: p.ai_agent_team_id, entries_count: p.entries_count } }
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end
    end
  end
end
