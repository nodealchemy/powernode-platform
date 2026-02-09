# frozen_string_literal: true

module Ai
  module Tools
    class MemoryTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      def self.definition
        {
          name: "memory_management",
          description: "Read or write shared memory pools",
          parameters: {
            action: { type: "string", required: true, description: "Action: write_shared_memory, read_shared_memory" },
            pool_id: { type: "string", required: true, description: "Memory pool ID" },
            key: { type: "string", required: true, description: "Data key (dot-separated for nesting)" },
            value: { type: "object", required: false, description: "Value to write (for write action)" }
          }
        }
      end

      protected

      def call(params)
        pool = account.ai_memory_pools.find_by!(pool_id: params[:pool_id])

        case params[:action]
        when "read_shared_memory"
          data = pool.read_data(params[:key], agent_id: agent&.id)
          { success: true, key: params[:key], value: data }
        when "write_shared_memory"
          pool.write_data(params[:key], params[:value], agent_id: agent&.id)
          { success: true, key: params[:key], written: true }
        else
          { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Memory pool not found" }
      rescue ArgumentError => e
        { success: false, error: e.message }
      end
    end
  end
end
