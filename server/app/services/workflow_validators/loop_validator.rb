# frozen_string_literal: true

module WorkflowValidators
  # Validates Loop nodes
  class LoopValidator < BaseValidator
    protected

    def validate_node_specific
      validate_required_fields(:iteration_source)
      validate_iteration_source
      validate_max_iterations
      validate_timeout
    end

    private

    def validate_iteration_source
      validate_field_options(:iteration_source, %w[array range count variable])
    end

    def validate_max_iterations
      return unless node.configuration.present?

      max_iterations = node.configuration['max_iterations'] || node.configuration[:max_iterations]

      if max_iterations.present?
        max_iterations_int = max_iterations.to_i

        if max_iterations_int <= 0
          add_issue(
            code: 'invalid_max_iterations',
            severity: 'error',
            category: 'configuration',
            message: 'Max iterations must be greater than 0',
            suggestion: 'Set a positive value for max_iterations'
          )
        elsif max_iterations_int > 10000
          add_issue(
            code: 'excessive_max_iterations',
            severity: 'warning',
            category: 'performance',
            message: "Max iterations of #{max_iterations_int} is very high",
            suggestion: 'Consider reducing max_iterations to prevent long execution times'
          )
        end
      else
        add_issue(
          code: 'missing_max_iterations',
          severity: 'warning',
          category: 'configuration',
          message: 'No max iterations limit set',
          suggestion: 'Set max_iterations to prevent infinite loops',
          auto_fixable: true,
          metadata: { recommended_max_iterations: 1000 }
        )
      end
    end
  end
end
