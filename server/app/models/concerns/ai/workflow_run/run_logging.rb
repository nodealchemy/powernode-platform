# frozen_string_literal: true

module Ai
  class WorkflowRun
    module RunLogging
      extend ActiveSupport::Concern

      def log(level, event_type, message, context = {}, node_execution = nil)
        run_logs.create!(
          node_execution: node_execution,
          log_level: level.to_s,
          event_type: event_type.to_s,
          message: message,
          context_data: context,
          node_id: node_execution&.node_id,
          source: "workflow_run",
          logged_at: Time.current
        )
      end

      def log_info(event_type, message, context = {})
        log("info", event_type, message, context)
      end

      def log_error(event_type, message, context = {})
        log("error", event_type, message, context)
      end

      def log_warning(event_type, message, context = {})
        log("warn", event_type, message, context)
      end
    end
  end
end
