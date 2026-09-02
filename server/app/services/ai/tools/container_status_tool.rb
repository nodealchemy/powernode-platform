# frozen_string_literal: true

module Ai
  module Tools
    class ContainerStatusTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "agent_container_status", mutating: false

      def self.definition
        {
          name: "agent_container_status",
          description: "Get the current status and details of a container instance by execution ID. " \
                       "Returns status, resource usage, duration, and any error information.",
          parameters: {
            execution_id: { type: "string", required: true, description: "The execution ID of the container instance" }
          }
        }
      end

      def self.action_definitions
        { "agent_container_status" => definition }
      end

      protected

      def call(params)
        instance = account.devops_container_instances.find_by!(execution_id: params[:execution_id])

        {
          success: true,
          instance: instance.instance_details
        }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Container instance not found: #{params[:execution_id]}" }
      end
    end
  end
end
