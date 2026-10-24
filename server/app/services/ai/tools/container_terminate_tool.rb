# frozen_string_literal: true

module Ai
  module Tools
    class ContainerTerminateTool < BaseTool
      tool_family "agents"

      REQUIRED_PERMISSION = "ai.agents.execute"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "agent_container_terminate", mutating: true, destructive: true,
                                                  action_category: "ai.container.terminate",
                                                  executor_class: "Ai::Executors::DeferredToolCall",
                                                  gate_context: :deferred_tool_call_context,
                                                  on_proceed: :deferred_tool_call_result

      def self.definition
        {
          name: "agent_container_terminate",
          description: "Gracefully terminate a running container instance. Respects execution gate " \
                       "governance checks. The container will be cancelled with the provided reason.",
          parameters: {
            execution_id: { type: "string", required: true, description: "The execution ID of the container to terminate" },
            reason: { type: "string", required: false, description: "Reason for termination (default: 'Terminated via MCP tool')" }
          }
        }
      end

      def self.action_definitions
        { "agent_container_terminate" => definition }
      end

      protected

      # A gated action returns from BaseTool#execute before #call, and this tool
      # has no per-action check of its own (only the class floor the registrar
      # applies). Enforced here so a caller without it parks nothing, and again at
      # replay (c13-2 batch C-C).
      def authorization_error(_params)
        return nil if internal? || instance_authorized?
        return nil if user.respond_to?(:has_permission?) && user.has_permission?(REQUIRED_PERMISSION) == true

        error_result("permission denied: #{REQUIRED_PERMISSION} required")
      end

      def call(params)
        instance = account.devops_container_instances.find_by!(execution_id: params[:execution_id])

        unless instance.active? || instance.paused?
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
        rescued_error_result(e, message: "Termination failed")
      end
    end
  end
end
