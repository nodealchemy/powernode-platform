# frozen_string_literal: true

module Mcp
  # Mcp::ConditionalEvaluator
  #
  # Evaluates conditional expressions for workflow edge conditions.
  # Supports simple comparison expressions like "score > threshold".
  #
  # Usage:
  #   evaluator = Mcp::ConditionalEvaluator.new(
  #     condition: { expression: 'score > threshold' },
  #     context: { threshold: 0.8 },
  #     node_result: { score: 0.9 }
  #   )
  #   evaluator.evaluate # => true
  #
  class ConditionalEvaluator
    # Supported comparison operators
    OPERATORS = {
      ">" => ->(a, b) { a > b },
      "<" => ->(a, b) { a < b },
      ">=" => ->(a, b) { a >= b },
      "<=" => ->(a, b) { a <= b },
      "==" => ->(a, b) { a == b },
      "!=" => ->(a, b) { a != b }
    }.freeze

    # Operator precedence for parsing (longest first to avoid partial matches)
    OPERATOR_REGEX = /(>=|<=|==|!=|>|<)/.freeze

    attr_reader :condition, :context, :node_result

    # Initialize the conditional evaluator
    #
    # @param condition [Hash] Condition hash with 'expression' key
    # @param context [Hash] Execution context containing workflow variables
    # @param node_result [Hash] Result from the node execution
    def initialize(condition:, context:, node_result:)
      @condition = condition
      @context = context || {}
      @node_result = node_result || {}
    end

    # Evaluate the conditional expression
    #
    # @return [Boolean] Result of the expression evaluation
    # @raise [ArgumentError] if expression is missing or invalid
    def evaluate
      expression = extract_expression
      raise ArgumentError, "Expression cannot be blank" if expression.blank?

      # Parse expression into components
      left_operand, operator, right_operand = parse_expression(expression)

      # Resolve variable values
      left_value = resolve_value(left_operand)
      right_value = resolve_value(right_operand)

      # Perform comparison
      perform_comparison(left_value, operator, right_value)
    end

    private

    # Extract expression string from condition hash
    #
    # @return [String] The expression string
    def extract_expression
      # Handle both string and symbol keys
      @condition["expression"] || @condition[:expression] || ""
    end

    # Parse expression into left operand, operator, and right operand
    #
    # @param expression [String] Expression like 'score > threshold'
    # @return [Array<String, String, String>] [left_operand, operator, right_operand]
    # @raise [ArgumentError] if expression format is invalid
    def parse_expression(expression)
      # Split on operator while preserving the operator
      parts = expression.split(OPERATOR_REGEX).map(&:strip)

      if parts.length != 3
        raise ArgumentError, "Invalid expression format: '#{expression}'. Expected format: 'operand operator operand'"
      end

      left_operand = parts[0]
      operator = parts[1]
      right_operand = parts[2]

      unless OPERATORS.key?(operator)
        raise ArgumentError, "Unsupported operator: '#{operator}'. Supported: #{OPERATORS.keys.join(', ')}"
      end

      [ left_operand, operator, right_operand ]
    end

    # Resolve a variable name to its value from context or node_result
    #
    # @param operand [String] Variable name or literal value
    # @return [Object] Resolved value
    def resolve_value(operand)
      # Try to parse as number first (literal value)
      if numeric?(operand)
        return parse_numeric(operand)
      end

      # Try to parse as boolean literal
      if boolean?(operand)
        return parse_boolean(operand)
      end

      # Try to parse as string literal (quoted)
      if string_literal?(operand)
        return parse_string_literal(operand)
      end

      # Otherwise, resolve as variable from node_result or context
      resolve_variable(operand)
    end

    # Check if string is numeric
    #
    # @param str [String] String to check
    # @return [Boolean]
    def numeric?(str)
      str.match?(/\A-?\d+(\.\d+)?\z/)
    end

    # Parse numeric string to Float or Integer
    #
    # @param str [String] Numeric string
    # @return [Numeric]
    def parse_numeric(str)
      str.include?(".") ? str.to_f : str.to_i
    end

    # Check if string is boolean literal
    #
    # @param str [String] String to check
    # @return [Boolean]
    def boolean?(str)
      %w[true false].include?(str.downcase)
    end

    # Parse boolean string
    #
    # @param str [String] Boolean string
    # @return [Boolean]
    def parse_boolean(str)
      str.downcase == "true"
    end

    # Check if string is a quoted string literal
    #
    # @param str [String] String to check
    # @return [Boolean]
    def string_literal?(str)
      (str.start_with?('"') && str.end_with?('"')) ||
        (str.start_with?("'") && str.end_with?("'"))
    end

    # Parse string literal by removing quotes
    #
    # @param str [String] Quoted string
    # @return [String]
    def parse_string_literal(str)
      str[1..-2] # Remove first and last characters (quotes)
    end

    # Resolve variable from node_result or context
    #
    # @param variable_name [String] Name of the variable
    # @return [Object] Variable value
    # @raise [ArgumentError] if variable not found
    def resolve_variable(variable_name)
      # Try node_result first (output_data hash)
      if @node_result.is_a?(Hash)
        output_data = @node_result["output_data"] || @node_result[:output_data] || {}

        # Check with string key
        if output_data.key?(variable_name)
          return output_data[variable_name]
        end

        # Check with symbol key
        if output_data.key?(variable_name.to_sym)
          return output_data[variable_name.to_sym]
        end
      end

      # Try direct node_result access
      if @node_result.key?(variable_name)
        return @node_result[variable_name]
      end

      if @node_result.key?(variable_name.to_sym)
        return @node_result[variable_name.to_sym]
      end

      # Try context (input_variables or variables)
      if @context.is_a?(Hash)
        # Try input_variables key (used in some contexts)
        input_vars = @context["input_variables"] || @context[:input_variables]
        if input_vars.is_a?(Hash)
          if input_vars.key?(variable_name)
            return input_vars[variable_name]
          end

          if input_vars.key?(variable_name.to_sym)
            return input_vars[variable_name.to_sym]
          end
        end

        # Try variables key (used in execution context)
        vars = @context["variables"] || @context[:variables]
        if vars.is_a?(Hash)
          if vars.key?(variable_name)
            return vars[variable_name]
          end

          if vars.key?(variable_name.to_sym)
            return vars[variable_name.to_sym]
          end
        end
      end

      # Try direct context access
      if @context.key?(variable_name)
        return @context[variable_name]
      end

      if @context.key?(variable_name.to_sym)
        return @context[variable_name.to_sym]
      end

      # Variable not found
      raise ArgumentError, "Variable '#{variable_name}' not found in context or node result"
    end

    # Perform comparison operation
    #
    # @param left_value [Object] Left operand value
    # @param operator [String] Comparison operator
    # @param right_value [Object] Right operand value
    # @return [Boolean] Comparison result
    def perform_comparison(left_value, operator, right_value)
      comparison_proc = OPERATORS[operator]
      comparison_proc.call(left_value, right_value)
    rescue StandardError => e
      raise ArgumentError, "Comparison failed: #{e.message}"
    end
  end
end
