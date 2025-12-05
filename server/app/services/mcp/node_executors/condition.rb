# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Condition node executor - evaluates conditional expressions
    class Condition < Base
      protected

      def perform_execution
        log_info "Evaluating condition"

        # Get condition configuration
        condition_type = configuration['condition_type'] || 'expression'
        condition_expression = configuration['condition'] || configuration['expression']

        # Evaluate the condition
        condition_result = case condition_type
                          when 'expression'
                            evaluate_expression(condition_expression)
                          when 'comparison'
                            evaluate_comparison
                          when 'exists'
                            evaluate_exists
                          else
                            false
                          end

        # Store condition result
        if configuration['output_variable']
          set_variable(configuration['output_variable'], condition_result)
        end

        log_debug "Condition result: #{condition_result}"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: condition_result,              # Primary result (boolean)
          result: {                              # Computed evaluation details
            condition_met: condition_result,
            evaluated_branch: condition_result ? 'then' : 'else'
          },
          data: {
            condition_type: condition_type
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'condition',
            executed_at: Time.current.iso8601,
            condition_type: condition_type
          }
        }
      end

      private

      def evaluate_expression(expression)
        return false if expression.blank?

        # Replace variables in expression
        resolved_expression = resolve_variables(expression)

        # Simple expression evaluation
        # For production, use a safe expression evaluator
        case resolved_expression
        when /^true$/i
          true
        when /^false$/i
          false
        when /(\w+)\s*(==|!=|>|<|>=|<=)\s*(.+)/
          left = $1.strip
          operator = $2
          right = $3.strip.gsub(/['"]/, '')

          evaluate_comparison_operator(left, operator, right)
        else
          false
        end
      rescue StandardError => e
        @logger.error "[CONDITION_EXECUTOR] Expression evaluation failed: #{e.message}"
        false
      end

      def evaluate_comparison
        left_value = get_variable(configuration['left_variable']) || configuration['left_value']
        right_value = get_variable(configuration['right_variable']) || configuration['right_value']
        operator = configuration['operator'] || '=='

        evaluate_comparison_operator(left_value, operator, right_value)
      end

      def evaluate_exists
        variable_name = configuration['variable_name']
        value = get_variable(variable_name)
        value.present?
      end

      def evaluate_comparison_operator(left, operator, right)
        case operator
        when '=='
          left.to_s == right.to_s
        when '!='
          left.to_s != right.to_s
        when '>'
          left.to_f > right.to_f
        when '<'
          left.to_f < right.to_f
        when '>='
          left.to_f >= right.to_f
        when '<='
          left.to_f <= right.to_f
        else
          false
        end
      end

      def resolve_variables(expression)
        result = expression.dup

        # Find all {{variable}} patterns and replace with values
        result.gsub(/\{\{(\w+)\}\}/) do |match|
          variable_name = $1
          value = get_variable(variable_name)
          value.present? ? value.to_s : match
        end
      end
    end
  end
end
