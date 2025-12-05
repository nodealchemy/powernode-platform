# frozen_string_literal: true

module WorkflowValidators
  # Validates Human Approval nodes
  class HumanApprovalValidator < BaseValidator
    protected

    def validate_node_specific
      validate_required_fields(:approvers)
      validate_approvers_list
      validate_approval_criteria
      validate_timeout_configuration
    end

    private

    def validate_approvers_list
      return unless node.configuration.present?

      approvers = node.configuration['approvers'] || node.configuration[:approvers]
      return if approvers.blank?

      unless approvers.is_a?(Array)
        add_issue(
          code: 'approvers_not_array',
          severity: 'error',
          category: 'configuration',
          message: 'Approvers must be an array',
          suggestion: 'Configure approvers as an array of user IDs or email addresses'
        )
        return
      end

      if approvers.empty?
        add_issue(
          code: 'no_approvers',
          severity: 'error',
          category: 'configuration',
          message: 'No approvers configured',
          suggestion: 'Add at least one approver'
        )
      end
    end

    def validate_approval_criteria
      return unless node.configuration.present?

      min_approvals = node.configuration['min_approvals'] || node.configuration[:min_approvals]
      approvers = node.configuration['approvers'] || node.configuration[:approvers]

      return if min_approvals.blank? || approvers.blank?

      min_approvals_int = min_approvals.to_i
      approvers_count = approvers.is_a?(Array) ? approvers.size : 0

      if min_approvals_int > approvers_count
        add_issue(
          code: 'min_approvals_exceeds_approvers',
          severity: 'error',
          category: 'configuration',
          message: "Minimum approvals (#{min_approvals_int}) exceeds number of approvers (#{approvers_count})",
          suggestion: 'Reduce min_approvals or add more approvers'
        )
      end
    end

    def validate_timeout_configuration
      return unless node.configuration.present?

      timeout_seconds = node.configuration['approval_timeout_seconds'] || node.configuration[:approval_timeout_seconds]

      if timeout_seconds.blank?
        add_issue(
          code: 'missing_approval_timeout',
          severity: 'warning',
          category: 'configuration',
          message: 'No approval timeout configured',
          suggestion: 'Set an approval timeout to prevent workflow from waiting indefinitely',
          auto_fixable: true,
          metadata: { recommended_timeout: 86400 } # 1 day
        )
      end
    end
  end
end
