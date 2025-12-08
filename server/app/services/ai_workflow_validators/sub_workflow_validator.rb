# frozen_string_literal: true

module WorkflowValidators
  # Validates Sub-Workflow nodes
  class SubWorkflowValidator < BaseValidator
    protected

    def validate_node_specific
      validate_required_fields(:workflow_id)
      validate_workflow_exists
      validate_no_circular_reference
      validate_input_mapping
      validate_timeout
    end

    private

    def validate_workflow_exists
      return unless node.configuration.present?

      workflow_id = node.configuration['workflow_id'] || node.configuration[:workflow_id]
      return if workflow_id.blank?

      unless AiWorkflow.exists?(workflow_id)
        add_issue(
          code: 'workflow_not_found',
          severity: 'error',
          category: 'configuration',
          message: "Sub-workflow with ID '#{workflow_id}' does not exist",
          suggestion: 'Select a valid workflow or create a new one'
        )
      end
    end

    def validate_no_circular_reference
      return unless node.configuration.present?

      workflow_id = node.configuration['workflow_id'] || node.configuration[:workflow_id]
      return if workflow_id.blank?

      # Get the parent workflow from the node
      parent_workflow = node.ai_workflow
      return unless parent_workflow

      if workflow_id == parent_workflow.id
        add_issue(
          code: 'circular_workflow_reference',
          severity: 'error',
          category: 'configuration',
          message: 'Sub-workflow cannot reference itself',
          suggestion: 'Select a different workflow'
        )
      end
    end

    def validate_input_mapping
      return unless node.configuration.present?

      input_mapping = node.configuration['input_mapping'] || node.configuration[:input_mapping]

      if input_mapping.blank?
        add_issue(
          code: 'missing_input_mapping',
          severity: 'info',
          category: 'configuration',
          message: 'No input mapping configured for sub-workflow',
          suggestion: 'Configure input_mapping to pass data to the sub-workflow'
        )
      end
    end
  end
end
