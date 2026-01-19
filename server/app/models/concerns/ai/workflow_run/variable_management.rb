# frozen_string_literal: true

module Ai
  class WorkflowRun
    module VariableManagement
      extend ActiveSupport::Concern

      def get_variable(name)
        runtime_context.dig("variables", name.to_s) ||
        input_variables[name.to_s] ||
        input_variables[name.to_sym]
      end

      def set_variable(name, value)
        variables = runtime_context["variables"] || {}
        variables[name.to_s] = value

        update!(
          runtime_context: runtime_context.merge("variables" => variables)
        )
      end

      def merge_variables(new_variables)
        return if new_variables.blank?

        current_variables = runtime_context["variables"] || {}
        merged_variables = current_variables.merge(new_variables.stringify_keys)

        update!(
          runtime_context: runtime_context.merge("variables" => merged_variables)
        )
      end
    end
  end
end
