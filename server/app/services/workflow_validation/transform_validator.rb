# frozen_string_literal: true

module WorkflowValidation
  # Validates Transform nodes
  class TransformValidator < BaseValidator
    protected

    def validate_node_specific
      validate_required_fields(:transformations)
      validate_transformations_array
    end

    private

    def validate_transformations_array
      return unless node.configuration.present?

      transformations = node.configuration['transformations'] || node.configuration[:transformations]
      return if transformations.blank?

      unless transformations.is_a?(Array)
        add_issue(
          code: 'transformations_not_array',
          severity: 'error',
          category: 'configuration',
          message: 'Transformations must be an array',
          suggestion: 'Configure transformations as an array of transformation objects'
        )
        return
      end

      if transformations.empty?
        add_issue(
          code: 'empty_transformations',
          severity: 'error',
          category: 'configuration',
          message: 'No transformations configured',
          suggestion: 'Add at least one transformation'
        )
      end

      transformations.each_with_index do |transformation, index|
        validate_transformation(transformation, index)
      end
    end

    def validate_transformation(transformation, index)
      unless transformation.is_a?(Hash)
        add_issue(
          code: 'invalid_transformation_format',
          severity: 'error',
          category: 'configuration',
          message: "Transformation at index #{index} is not an object",
          suggestion: 'Each transformation must be an object with type and configuration'
        )
        return
      end

      unless transformation.key?('type')
        add_issue(
          code: 'missing_transformation_type',
          severity: 'error',
          category: 'configuration',
          message: "Transformation at index #{index} missing 'type'",
          suggestion: "Add 'type' to the transformation (e.g., 'map', 'filter', 'format')"
        )
      end

      valid_types = %w[map filter reduce format merge extract]
      transformation_type = transformation['type']

      if transformation_type.present? && !valid_types.include?(transformation_type)
        add_issue(
          code: 'invalid_transformation_type',
          severity: 'warning',
          category: 'configuration',
          message: "Unknown transformation type '#{transformation_type}' at index #{index}",
          suggestion: "Use one of: #{valid_types.join(', ')}"
        )
      end
    end
  end
end
