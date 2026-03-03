# frozen_string_literal: true

module Ai
  module Tools
    class ContainerStatusTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      def self.definition
        {
          name: "container_status",
          description: "Get the current status and details of a container instance by execution ID. " \
                       "Returns status, resource usage, duration, and any error information.",
          parameters: {
            execution_id: { type: "string", required: true, description: "The execution ID of the container instance" }
          }
        }
      end

      def self.action_definitions
        { "container_status" => definition }
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
