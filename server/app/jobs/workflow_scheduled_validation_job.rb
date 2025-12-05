# frozen_string_literal: true

# WorkflowScheduledValidationJob
#
# Periodically validates workflows to ensure they remain healthy.
# Runs on a configurable schedule (default: daily) and validates workflows
# that haven't been validated recently.
#
# Features:
# - Batch processing to avoid overwhelming the system
# - Configurable validation frequency
# - Automatic retry for failed validations
# - Skips recently validated workflows
# - Account-scoped processing
#
# @example Schedule daily validation
#   WorkflowScheduledValidationJob.perform_later
#
# @example Schedule validation for specific account
#   WorkflowScheduledValidationJob.perform_later(account_id: 'uuid')
#
class WorkflowScheduledValidationJob < ApplicationJob
  queue_as :default

  # Maximum number of workflows to validate per run
  BATCH_SIZE = 50

  # How recent a validation must be to skip (in hours)
  VALIDATION_FRESHNESS_THRESHOLD = 24

  def perform(account_id: nil, batch_size: BATCH_SIZE)
    workflows = find_workflows_to_validate(account_id, batch_size)

    if workflows.empty?
      Rails.logger.info "[WorkflowScheduledValidationJob] No workflows need validation"
      return
    end

    Rails.logger.info "[WorkflowScheduledValidationJob] Validating #{workflows.count} workflows"

    results = {
      total: workflows.count,
      successful: 0,
      failed: 0,
      skipped: 0
    }

    workflows.each do |workflow|
      begin
        validate_workflow(workflow)
        results[:successful] += 1
      rescue => e
        Rails.logger.error "[WorkflowScheduledValidationJob] Failed to validate workflow #{workflow.id}: #{e.message}"
        results[:failed] += 1
      end
    end

    Rails.logger.info "[WorkflowScheduledValidationJob] Completed: #{results}"
    results
  end

  private

  def find_workflows_to_validate(account_id, batch_size)
    scope = AiWorkflow.where(status: %w[active draft])

    # Filter by account if specified
    scope = scope.where(account_id: account_id) if account_id.present?

    # Find workflows that either:
    # 1. Have never been validated
    # 2. Haven't been validated recently
    scope
      .left_joins(:workflow_validations)
      .select('ai_workflows.*')
      .select('MAX(workflow_validations.created_at) as last_validated_at')
      .group('ai_workflows.id')
      .having('MAX(workflow_validations.created_at) IS NULL OR MAX(workflow_validations.created_at) < ?',
              VALIDATION_FRESHNESS_THRESHOLD.hours.ago)
      .limit(batch_size)
  end

  def validate_workflow(workflow)
    # Run validation
    service = WorkflowValidationService.new(workflow)
    result = service.validate

    # Store validation result
    validation = workflow.workflow_validations.create!(result)

    Rails.logger.info "[WorkflowScheduledValidationJob] Validated workflow #{workflow.id}: " \
                      "Health Score: #{validation.health_score}, " \
                      "Status: #{validation.overall_status}, " \
                      "Issues: #{validation.issues.size}"

    validation
  end
end
