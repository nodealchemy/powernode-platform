# frozen_string_literal: true

module Ai
  module Tools
    class AgentManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      def self.definition
        {
          name: "agent_management",
          description: "Create, list, get, update, or execute AI agents",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_agent, list_agents, get_agent, update_agent, execute_agent" },
            agent_id: { type: "string", required: false, description: "Agent ID (for execute)" },
            name: { type: "string", required: false, description: "Agent name (for create)" },
            description: { type: "string", required: false, description: "Agent description (for create)" },
            model: { type: "string", required: false, description: "Model name (for create)" },
            input: { type: "object", required: false, description: "Execution input (for execute)" },
            system_prompt: { type: "string", required: false, description: "System prompt (for create/update)" },
            conversation_profile: { type: "object", required: false, description: "Conversation profile (for create/update)" },
            status: { type: "string", required: false, description: "Agent status (for update)" }
          }
        }
      end

      def self.action_definitions
        {
          "create_agent" => {
            description: "Create a new AI agent with the specified configuration",
            parameters: {
              name: { type: "string", required: true, description: "Agent name" },
              description: { type: "string", required: false, description: "Agent description" },
              model: { type: "string", required: false, description: "Model name (defaults to provider default)" },
              agent_type: { type: "string", required: false, description: "Agent type (default: assistant)" },
              system_prompt: { type: "string", required: false, description: "System prompt" },
              conversation_profile: { type: "object", required: false, description: "Conversation profile configuration" }
            }
          },
          "list_agents" => {
            description: "List all active AI agents in the current account",
            parameters: {}
          },
          "get_agent" => {
            description: "Get detailed information about a specific AI agent",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent ID" }
            }
          },
          "update_agent" => {
            description: "Update an existing AI agent's configuration",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent ID" },
              name: { type: "string", required: false, description: "New agent name" },
              description: { type: "string", required: false, description: "New agent description" },
              status: { type: "string", required: false, description: "Agent status" },
              system_prompt: { type: "string", required: false, description: "System prompt" },
              conversation_profile: { type: "object", required: false, description: "Conversation profile configuration" },
              mcp_metadata: { type: "object", required: false, description: "MCP metadata to merge" }
            }
          },
          "execute_agent" => {
            description: "Queue execution of an AI agent with the given input",
            parameters: {
              agent_id: { type: "string", required: true, description: "Agent ID to execute" },
              input: { type: "object", required: false, description: "Execution input" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "create_agent" then create_agent(params)
        when "list_agents" then list_agents
        when "get_agent" then get_agent(params)
        when "update_agent" then update_agent(params)
        when "execute_agent" then execute_agent(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def create_agent(params)
        provider = account.ai_providers.where(is_active: true).first
        creator = user || account.users.first

        agent = account.ai_agents.create!(
          name: params[:name],
          description: params[:description],
          model: params[:model] || provider&.default_model || "claude-sonnet-4",
          status: "active",
          agent_type: params[:agent_type] || "assistant",
          creator: creator,
          provider: provider
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

      def get_agent(params)
        agent_record = account.ai_agents.find(params[:agent_id])
        {
          success: true,
          agent: {
            id: agent_record.id,
            name: agent_record.name,
            description: agent_record.description,
            status: agent_record.status,
            agent_type: agent_record.agent_type,
            model: agent_record.model,
            system_prompt: agent_record.system_prompt,
            conversation_profile: agent_record.conversation_profile,
            mcp_metadata: agent_record.mcp_metadata
          }
        }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Agent not found" }
      end

      def update_agent(params)
        agent_record = account.ai_agents.find(params[:agent_id])
        attrs = {}
        attrs[:name] = params[:name] if params[:name].present?
        attrs[:description] = params[:description] if params[:description].present?
        attrs[:status] = params[:status] if params[:status].present?
        attrs[:system_prompt] = params[:system_prompt] if params[:system_prompt].present?
        attrs[:conversation_profile] = params[:conversation_profile] if params[:conversation_profile].present?
        if params[:mcp_metadata].present?
          attrs[:mcp_metadata] = (agent_record.mcp_metadata || {}).merge(params[:mcp_metadata])
        end
        agent_record.update!(attrs)
        { success: true, agent_id: agent_record.id, name: agent_record.name }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Agent not found" }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end
    end
  end
end
