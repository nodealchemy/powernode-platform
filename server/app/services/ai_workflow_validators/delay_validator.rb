# frozen_string_literal: true

module WorkflowValidators
  # Validates Delay nodes
  class DelayValidator < BaseValidator
    protected

    def validate_node_specific
      validate_delay_configuration
      validate_delay_duration
    end

    private

    def validate_delay_configuration
      return unless node.configuration.present?

      delay_seconds = node.configuration["delay_seconds"] || node.configuration[:delay_seconds]
      delay_expression = node.configuration["delay_expression"] || node.configuration[:delay_expression]

      if delay_seconds.blank? && delay_expression.blank?
        add_issue(
          code: "missing_delay",
          severity: "error",
          category: "configuration",
          message: "No delay duration configured",
          suggestion: "Provide either delay_seconds or delay_expression"
        )
      end
    end

    def validate_delay_duration
      return unless node.configuration.present?

      delay_seconds = node.configuration["delay_seconds"] || node.configuration[:delay_seconds]
      return if delay_seconds.blank?

      delay_seconds_int = delay_seconds.to_i

      if delay_seconds_int <= 0
        add_issue(
          code: "invalid_delay",
          severity: "error",
          category: "configuration",
          message: "Delay duration must be greater than 0",
          suggestion: "Set a positive delay duration"
        )
      elsif delay_seconds_int > 86400 # 1 day
        add_issue(
          code: "excessive_delay",
          severity: "warning",
          category: "performance",
          message: "Delay of #{delay_seconds_int}s (#{delay_seconds_int / 3600.0} hours) is very long",
          suggestion: "Consider if such a long delay is necessary"
        )
      end
    end
  end
end
