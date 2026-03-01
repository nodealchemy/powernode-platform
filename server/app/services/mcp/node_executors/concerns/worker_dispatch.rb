# frozen_string_literal: true

module Mcp
  module NodeExecutors
    module Concerns
      module WorkerDispatch
        extend ActiveSupport::Concern

        private

        def dispatch_to_worker(job_class, payload, queue: "mcp")
          execution = create_node_tool_execution(payload)

          WorkerApiClient.new.queue_job(
            job_class,
            [execution.id, payload.deep_stringify_keys],
            queue: queue
          )

          build_dispatched_result(execution)
        end

        def create_node_tool_execution(payload)
          tool_name = self.class.name.demodulize.underscore
          account = @orchestrator&.workflow_run&.account

          Ai::WorkflowNodeExecution.find(@node_execution.id).tap do |exec|
            exec.update!(
              metadata: (exec.metadata || {}).merge(
                "dispatch_tool" => tool_name,
                "dispatch_payload" => payload,
                "dispatched_at" => Time.current.iso8601,
                "dispatch_status" => "dispatched"
              )
            )
          end
        end

        def build_dispatched_result(execution)
          {
            output: {
              status: "dispatched",
              execution_id: execution.id,
              message: "Task dispatched to worker for async execution"
            },
            data: {
              execution_id: execution.id,
              dispatched_at: Time.current.iso8601,
              status: "dispatched"
            },
            metadata: {
              node_id: @node.node_id,
              node_type: @node.node_type,
              executed_at: Time.current.iso8601,
              workflow_state: "paused_for_worker"
            }
          }
        end
      end
    end
  end
end
