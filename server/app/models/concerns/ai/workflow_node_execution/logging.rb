# frozen_string_literal: true

module Ai
  class WorkflowNodeExecution
    module Logging
      extend ActiveSupport::Concern

      def log_info(event_type, message, context = {})
        workflow_run.log(
          "info",
          event_type,
          message,
          context.merge("node_id" => node_id, "execution_id" => execution_id),
          self
        )
      end

      def log_error(event_type, message, context = {})
        workflow_run.log(
          "error",
          event_type,
          message,
          context.merge("node_id" => node_id, "execution_id" => execution_id),
          self
        )
      end

      def log_warning(event_type, message, context = {})
        workflow_run.log(
          "warn",
          event_type,
          message,
          context.merge("node_id" => node_id, "execution_id" => execution_id),
          self
        )
      end
    end
  end
end
