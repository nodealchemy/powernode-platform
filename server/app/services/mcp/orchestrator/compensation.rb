# frozen_string_literal: true

module Mcp
  module Orchestrator
    module Compensation
      def should_compensate_on_failure?
        compensation_strategy = @workflow.mcp_orchestration_config&.dig("compensation_strategy")
        compensation_strategy == "automatic" || @compensation_stack.any?
      end

      def trigger_compensation(original_error)
        @logger.warn "[MCP_ORCHESTRATOR] Triggering compensation due to failure"

        @event_store.record_event(
          event_type: "workflow.compensation.started",
          event_data: {
            original_error: original_error.message,
            compensation_handlers: @compensation_stack.count
          }
        )

        compensation_errors = []

        @compensation_stack.reverse.each do |compensation|
          begin
            execute_compensation_handler(compensation)
          rescue StandardError => e
            @logger.error "[MCP_ORCHESTRATOR] Compensation failed for node #{compensation[:node_id]}: #{e.message}"
            compensation_errors << {
              node_id: compensation[:node_id],
              error: e.message
            }
          end
        end

        if compensation_errors.any?
          @event_store.record_event(
            event_type: "workflow.compensation.partial_failure",
            event_data: { errors: compensation_errors }
          )
        else
          @event_store.record_event(
            event_type: "workflow.compensation.completed",
            event_data: { handlers_executed: @compensation_stack.count }
          )
        end
      end

      def execute_compensation_handler(compensation)
        @logger.info "[MCP_ORCHESTRATOR] Executing compensation for node: #{compensation[:node_id]}"

        handler = compensation[:handler]
        handler.call(compensation[:context]) if handler.respond_to?(:call)
      end
    end
  end
end
