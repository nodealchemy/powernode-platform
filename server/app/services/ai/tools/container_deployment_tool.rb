# frozen_string_literal: true

module Ai
  module Tools
    class ContainerDeploymentTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      def self.definition
        {
          name: "deploy_container_agent",
          description: "Deploy a containerized agent with MCP authentication. Launches an isolated container " \
                       "from a template with automatic OAuth credential provisioning and MCP session bootstrap.",
          parameters: {
            agent_id: { type: "string", required: true, description: "ID of the agent to deploy" },
            template_id: { type: "string", required: false, description: "Container template ID (auto-selected if omitted)" },
            template_slug: { type: "string", required: false, description: "Container template slug (alternative to template_id)" },
            conversation_id: { type: "string", required: false, description: "Conversation ID for chat-mode deployment" }
          }
        }
      end

      def self.action_definitions
        {
          "deploy_container_agent" => definition
        }
      end

      protected

      def call(params)
        agent = account.ai_agents.find(params[:agent_id])

        if params[:conversation_id].present?
          deploy_chat_session(agent, params)
        else
          deploy_sandbox(agent, params)
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: "Deployment failed: #{e.message}" }
      end

      private

      def deploy_chat_session(agent, params)
        template = resolve_template(params)

        service = Ai::ContainerAgentDeploymentService.new(account: account)
        instance = service.deploy_agent_session(
          agent: agent,
          conversation_id: params[:conversation_id],
          template: template,
          user: user
        )

        {
          success: true,
          execution_id: instance.execution_id,
          status: instance.status,
          mcp_session_info: {
            oauth_provisioned: instance.oauth_application_id.present?,
            mcp_bridge_port: instance.mcp_bridge_port
          }
        }
      end

      def deploy_sandbox(agent, params)
        template = resolve_template(params)

        service = Ai::Runtime::SandboxManagerService.new(account: account)
        instance = service.create_sandbox(
          agent: agent,
          config: template ? { image_name: template.image_name, image_tag: template.image_tag } : {}
        )

        {
          success: true,
          execution_id: instance.execution_id,
          status: instance.status,
          mcp_session_info: {
            oauth_provisioned: instance.oauth_application_id.present?,
            mcp_bridge_port: instance.mcp_bridge_port
          }
        }
      end

      def resolve_template(params)
        if params[:template_id].present?
          Devops::ContainerTemplate.accessible_by(account).find(params[:template_id])
        elsif params[:template_slug].present?
          Devops::ContainerTemplate.accessible_by(account).find_by!(slug: params[:template_slug])
        end
      end
    end
  end
end
