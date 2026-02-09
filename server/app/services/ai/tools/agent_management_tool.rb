# frozen_string_literal: true

module Ai
  module Tools
    class AgentManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      def self.definition
        {
          name: "agent_management",
          description: "Create, list, or execute AI agents",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_agent, list_agents, execute_agent" },
            agent_id: { type: "string", required: false, description: "Agent ID (for execute)" },
            name: { type: "string", required: false, description: "Agent name (for create)" },
            description: { type: "string", required: false, description: "Agent description (for create)" },
            model: { type: "string", required: false, description: "Model name (for create)" },
            input: { type: "object", required: false, description: "Execution input (for execute)" }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "create_agent" then create_agent(params)
        when "list_agents" then list_agents
        when "execute_agent" then execute_agent(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def create_agent(params)
        agent = account.ai_agents.create!(
          name: params[:name],
          description: params[:description],
          model: params[:model] || "claude-sonnet-4",
          status: "active",
          agent_type: "assistant"
        )
        { success: true, agent_id: agent.id, name: agent.name }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def list_agents
        agents = account.ai_agents.where(status: "active").limit(50)
        { success: true, agents: agents.map { |a| { id: a.id, name: a.name, model: a.model, status: a.status } } }
      end

      def execute_agent(params)
        agent = account.ai_agents.find(params[:agent_id])
        { success: true, agent_id: agent.id, status: "execution_queued", message: "Agent execution queued" }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Agent not found" }
      end
    end
  end
end
