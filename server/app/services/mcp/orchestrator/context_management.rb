# frozen_string_literal: true

module Mcp
  module Orchestrator
    module ContextManagement
      def update_execution_context(node, output_data)
        @execution_context[:node_results][node.node_id] = output_data

        if output_data.is_a?(Hash)
          variable_mapping = node.configuration&.dig("output_variables") || {}

          variable_mapping.each do |var_name, output_path|
            value = extract_value_from_path(output_data, output_path)
            @execution_context[:variables][var_name] = value if value.present?
          end

          if output_data["variables"].is_a?(Hash)
            @execution_context[:variables].merge!(output_data["variables"])
          end
        end

        serializable_context = @execution_context.except(:node_results).deep_dup
        @workflow_run.update_column(:runtime_context, serializable_context)
      end

      def extract_value_from_path(data, path)
        return data if path.blank?

        path.to_s.split(".").reduce(data) do |current, key|
          break nil unless current.is_a?(Hash) || current.is_a?(Array)

          if current.is_a?(Array) && key =~ /\A\d+\z/
            current[key.to_i]
          else
            current[key.to_s] || current[key.to_sym]
          end
        end
      end

      def execution_context
        @execution_context
      end

      def set_variable(name, value)
        @execution_context[:variables][name] = value
        serializable_context = @execution_context.except(:node_results).deep_dup
        @workflow_run.update_column(:runtime_context, serializable_context)
      end

      def get_variable(name)
        @execution_context[:variables][name]
      end

      def build_output_for_context(result)
        output_data = {}

        if result[:output].present?
          output_data["output"] = result[:output]
        end

        if result[:data].present? && result[:data].is_a?(Hash)
          output_data.merge!(result[:data])
        end

        if result[:result].present?
          output_data["result"] = result[:result]
        end

        output_data
      end
    end
  end
end
