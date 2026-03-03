# frozen_string_literal: true

module Ai
  module Tools
    class ContainerTerminateTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      def self.definition
        {
          name: "container_terminate",
          description: "Gracefully terminate a running container instance. Respects execution gate " \
                       "governance checks. The container will be cancelled with the provided reason.",
          parameters: {
            execution_id: { type: "string", required: true, description: "The execution ID of the container to terminate" },
            reason: { type: "string", required: false, description: "Reason for termination (default: 'Terminated via MCP tool')" }
          }
        }
      end

      def self.action_definitions
        { "container_terminate" => definition }
      end

      protected

      def call(params)
        instance = account.devops_container_instances.find_by!(execution_id: params[:execution_id])

        unless instance.active?
          return { success: false, error: "Container is not active (status: #{instance.status})" }
        end

        reason = params[:reason] || "Terminated via MCP tool"

        service = ::Devops::ContainerOrchestrationService.new(account: account, user: user)
        service.cancel(instance.execution_id, reason: reason)

        {
          success: true,
          execution_id: instance.execution_id,
          status: instance.reload.status,
          message: "Container terminated: #{reason}"
        }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Container instance not found: #{params[:execution_id]}" }
      rescue StandardError => e
        { success: false, error: "Termination failed: #{e.message}" }
      end
    end
  end
end
