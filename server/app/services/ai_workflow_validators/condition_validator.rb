# frozen_string_literal: true

module WorkflowValidators
  # Validates Condition nodes
  class ConditionValidator < BaseValidator
    protected

    def validate_node_specific
      validate_required_fields(:conditions)
      validate_conditions_array
      validate_default_branch
    end

    private

    def validate_conditions_array
      return unless node.configuration.present?

      conditions = node.configuration["conditions"] || node.configuration[:conditions]
      return if conditions.blank?

      unless conditions.is_a?(Array)
        add_issue(
          code: "conditions_not_array",
          severity: "error",
          category: "configuration",
          message: "Conditions must be an array",
          suggestion: "Configure conditions as an array of condition objects"
        )
        return
      end

      if conditions.empty?
        add_issue(
          code: "empty_conditions",
          severity: "error",
          category: "configuration",
          message: "No conditions configured",
          suggestion: "Add at least one condition"
        )
      end

      conditions.each_with_index do |condition, index|
        validate_condition(condition, index)
      end
    end

    def validate_condition(condition, index)
      unless condition.is_a?(Hash)
        add_issue(
          code: "invalid_condition_format",
          severity: "error",
          category: "configuration",
          message: "Condition at index #{index} is not an object",
          suggestion: "Each condition must be an object with field, operator, and value"
        )
        return
      end

      %w[field operator value].each do |required_key|
        unless condition.key?(required_key)
          add_issue(
            code: "missing_condition_#{required_key}",
            severity: "error",
            category: "configuration",
            message: "Condition at index #{index} missing '#{required_key}'",
            suggestion: "Add '#{required_key}' to the condition"
          )
        end
      end
    end

    def validate_default_branch
      return unless node.configuration.present?

      has_default = node.configuration["has_default_branch"] || node.configuration[:has_default_branch]

      if has_default == false
        add_issue(
          code: "no_default_branch",
          severity: "warning",
          category: "configuration",
          message: "No default branch configured",
          suggestion: "Consider adding a default branch for cases when no conditions match"
        )
      end
    end
  end
end
