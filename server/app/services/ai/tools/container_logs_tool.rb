# frozen_string_literal: true

module Ai
  module Tools
    class ContainerLogsTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      MAX_LOG_SIZE = 100_000
      DEFAULT_TAIL_SIZE = 50_000

      def self.definition
        {
          name: "container_logs",
          description: "Fetch logs from a container instance. Returns the execution logs, " \
                       "status, and any error messages. Logs are truncated to the requested tail size.",
          parameters: {
            execution_id: { type: "string", required: true, description: "The execution ID of the container instance" },
            tail: { type: "integer", required: false, description: "Number of characters from the end to return (default: 50000, max: 100000)" }
          }
        }
      end

      def self.action_definitions
        { "container_logs" => definition }
      end

      protected

      def call(params)
        instance = account.devops_container_instances.find_by!(execution_id: params[:execution_id])
        tail_size = (params[:tail] || DEFAULT_TAIL_SIZE).to_i.clamp(1, MAX_LOG_SIZE)

        logs = instance.logs
        logs = logs.last(tail_size) if logs.present?

        {
          success: true,
          execution_id: instance.execution_id,
          status: instance.status,
          logs: logs,
          error_message: instance.error_message
        }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Container instance not found: #{params[:execution_id]}" }
      end
    end
  end
end
