# frozen_string_literal: true

module Ai
  class WorkflowNodeExecution
    module DataManagement
      extend ActiveSupport::Concern

      def get_input(key)
        input_data[key.to_s] || input_data[key.to_sym]
      end

      def set_output(key, value)
        self.output_data = output_data.merge(key.to_s => value)
        save!
      end

      def merge_output(new_data)
        return if new_data.blank?

        self.output_data = output_data.merge(new_data.stringify_keys)
        save!
      end

      def get_variable(name)
        input_data[name.to_s] ||
        input_data[name.to_sym] ||
        workflow_run.get_variable(name)
      end

      def execution_summary
        {
          execution_id: execution_id,
          node_id: node_id,
          node_type: node_type,
          node_name: node.name,
          status: status,
          duration_seconds: execution_duration_seconds,
          cost: cost,
          retry_count: retry_count,
          max_retries: max_retries,
          timestamps: {
            created: created_at,
            started: started_at,
            completed: completed_at,
            cancelled: cancelled_at
          },
          has_error: error_details.present?,
          error_message: error_details["error_message"],
          input_keys: input_data.keys,
          output_keys: output_data.keys
        }
      end

      def node_configuration(key = nil)
        config = configuration_snapshot.present? ? configuration_snapshot : node.configuration
        key ? config[key.to_s] : config
      end

      def node_metadata(key = nil)
        node_meta = node.metadata
        key ? node_meta[key.to_s] : node_meta
      end
    end
  end
end
