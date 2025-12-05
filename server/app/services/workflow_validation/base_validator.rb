# frozen_string_literal: true

module WorkflowValidation
  # BaseValidator
  #
  # Base class for node-type-specific validators.
  # Provides common validation patterns and utilities.
  #
  class BaseValidator
    attr_reader :node, :issues

    def initialize(node)
      @node = node
      @issues = []
    end

    # Main validation method to be called by WorkflowValidationService
    #
    # @return [Array<Hash>] Array of validation issues
    def validate
      validate_required_configuration
      validate_node_specific
      @issues
    end

    protected

    # Override in subclasses for node-type-specific validation
    def validate_node_specific
      # Default implementation does nothing
    end

    # ==========================================
    # Common Validation Helpers
    # ==========================================

    # Check if configuration exists
    def validate_required_configuration
      if node.configuration.blank?
        add_issue(
          code: 'missing_configuration',
          severity: 'warning',
          category: 'configuration',
          message: 'Node has no configuration'
        )
      end
    end

    # Check if required fields exist in configuration
    def validate_required_fields(*fields)
      return if node.configuration.blank?

      fields.each do |field|
        unless node.configuration.key?(field.to_s) || node.configuration.key?(field.to_sym)
          add_issue(
            code: "missing_#{field}",
            severity: 'error',
            category: 'configuration',
            message: "Required field '#{field}' is missing from configuration",
            suggestion: "Add '#{field}' to the node configuration"
          )
        end
      end
    end

    # Check if a field has a specific value type
    def validate_field_type(field, expected_type)
      return unless node.configuration.present?

      value = node.configuration[field.to_s] || node.configuration[field.to_sym]
      return if value.nil?

      actual_type = value.class.name.downcase
      expected_type_name = expected_type.name.downcase

      unless value.is_a?(expected_type)
        add_issue(
          code: "invalid_#{field}_type",
          severity: 'error',
          category: 'configuration',
          message: "Field '#{field}' must be #{expected_type_name}, got #{actual_type}",
          suggestion: "Change '#{field}' to #{expected_type_name} type"
        )
      end
    end

    # Check if a field is not blank
    def validate_field_not_blank(field)
      return unless node.configuration.present?

      value = node.configuration[field.to_s] || node.configuration[field.to_sym]

      if value.blank?
        add_issue(
          code: "blank_#{field}",
          severity: 'warning',
          category: 'configuration',
          message: "Field '#{field}' should not be blank",
          suggestion: "Provide a value for '#{field}'"
        )
      end
    end

    # Check if a field is within valid options
    def validate_field_options(field, valid_options)
      return unless node.configuration.present?

      value = node.configuration[field.to_s] || node.configuration[field.to_sym]
      return if value.nil?

      unless valid_options.include?(value)
        add_issue(
          code: "invalid_#{field}_value",
          severity: 'error',
          category: 'configuration',
          message: "Field '#{field}' has invalid value '#{value}'",
          suggestion: "Use one of: #{valid_options.join(', ')}"
        )
      end
    end

    # Check if timeout is configured and reasonable
    def validate_timeout
      return unless node.configuration.present?

      timeout = node.configuration['timeout_seconds'] || node.configuration[:timeout_seconds] || node.timeout_seconds

      if timeout.nil?
        add_issue(
          code: 'missing_timeout',
          severity: 'info',
          category: 'performance',
          message: 'No timeout configured for this node',
          suggestion: 'Set a reasonable timeout (e.g., 30-300 seconds)',
          auto_fixable: true,
          metadata: { recommended_timeout: 30 }
        )
      elsif timeout.to_i > 600
        add_issue(
          code: 'timeout_too_long',
          severity: 'warning',
          category: 'performance',
          message: "Timeout of #{timeout}s is very long",
          suggestion: 'Consider reducing timeout to prevent workflow hangs'
        )
      elsif timeout.to_i < 5
        add_issue(
          code: 'timeout_too_short',
          severity: 'warning',
          category: 'performance',
          message: "Timeout of #{timeout}s may be too short",
          suggestion: 'Increase timeout to allow operation to complete'
        )
      end
    end

    # Check if retry configuration is valid
    def validate_retry_config
      return unless node.configuration.present?

      retry_count = node.configuration['retry_count'] || node.configuration[:retry_count] || node.retry_count

      if retry_count.present? && retry_count.to_i > 10
        add_issue(
          code: 'excessive_retries',
          severity: 'warning',
          category: 'performance',
          message: "Retry count of #{retry_count} is excessive",
          suggestion: 'Reduce retry count to avoid long execution times'
        )
      end
    end

    # ==========================================
    # Issue Management
    # ==========================================

    def add_issue(issue)
      # Set defaults
      issue[:severity] ||= 'warning'
      issue[:category] ||= 'configuration'
      issue[:auto_fixable] ||= false
      issue[:rule_id] ||= issue[:code]
      issue[:rule_name] ||= issue[:code].to_s.titleize

      @issues << issue
    end
  end
end
