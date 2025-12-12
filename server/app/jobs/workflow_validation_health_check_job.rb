# frozen_string_literal: true

# WorkflowValidationHealthCheckJob
#
# Monitors workflow validation health and creates alerts for degradation.
# Detects workflows with declining health scores or stale validations.
#
# Detection Criteria:
# - Health score drops > 10 points from previous validation
# - No validation in past 7 days for active workflows
# - Workflows stuck in 'invalid' status for extended periods
# - Sudden increase in error-severity issues
#
# @example Run health check
#   WorkflowValidationHealthCheckJob.perform_later
#
# @example Run for specific account
#   WorkflowValidationHealthCheckJob.perform_later(account_id: 'uuid')
#
class WorkflowValidationHealthCheckJob < ApplicationJob
  queue_as :default

  # Health score drop threshold to trigger alert
  HEALTH_DEGRADATION_THRESHOLD = 10

  # Days without validation to consider stale
  STALE_VALIDATION_THRESHOLD = 7

  # Maximum age for 'invalid' status before alerting
  INVALID_STATUS_THRESHOLD = 3

  def perform(account_id: nil)
    workflows = find_workflows_to_check(account_id)

    if workflows.empty?
      Rails.logger.info "[WorkflowValidationHealthCheckJob] No workflows need health check"
      return
    end

    Rails.logger.info "[WorkflowValidationHealthCheckJob] Checking health for #{workflows.count} workflows"

    alerts = []

    workflows.each do |workflow|
      workflow_alerts = check_workflow_health(workflow)
      alerts.concat(workflow_alerts) if workflow_alerts.any?
    end

    if alerts.any?
      Rails.logger.warn "[WorkflowValidationHealthCheckJob] Generated #{alerts.count} alerts"
      process_alerts(alerts)
    else
      Rails.logger.info "[WorkflowValidationHealthCheckJob] All workflows healthy"
    end

    { alerts_generated: alerts.count }
  end

  private

  def find_workflows_to_check(account_id)
    scope = AiWorkflow.where(status: %w[active paused])
                      .includes(:workflow_validations)

    scope = scope.where(account_id: account_id) if account_id.present?

    scope
  end

  def check_workflow_health(workflow)
    alerts = []

    # Get latest validations
    latest_validations = workflow.workflow_validations
                                 .order(created_at: :desc)
                                 .limit(2)

    return alerts if latest_validations.empty?

    latest = latest_validations.first
    previous = latest_validations.second

    # Check for stale validation
    if latest.created_at < STALE_VALIDATION_THRESHOLD.days.ago
      alerts << create_alert(
        workflow: workflow,
        type: "stale_validation",
        severity: "warning",
        message: "Workflow has not been validated in #{(Time.current - latest.created_at).to_i / 86400} days",
        metadata: {
          last_validated_at: latest.created_at,
          days_since_validation: (Time.current - latest.created_at).to_i / 86400
        }
      )
    end

    # Check for health degradation
    if previous && (previous.health_score - latest.health_score) >= HEALTH_DEGRADATION_THRESHOLD
      alerts << create_alert(
        workflow: workflow,
        type: "health_degradation",
        severity: "error",
        message: "Health score dropped #{previous.health_score - latest.health_score} points",
        metadata: {
          previous_score: previous.health_score,
          current_score: latest.health_score,
          degradation: previous.health_score - latest.health_score
        }
      )
    end

    # Check for persistent invalid status
    if latest.validation_invalid? && latest.created_at < INVALID_STATUS_THRESHOLD.days.ago
      alerts << create_alert(
        workflow: workflow,
        type: "persistent_invalid_status",
        severity: "error",
        message: "Workflow has been invalid for #{(Time.current - latest.created_at).to_i / 86400} days",
        metadata: {
          invalid_since: latest.created_at,
          days_invalid: (Time.current - latest.created_at).to_i / 86400,
          error_count: latest.error_count
        }
      )
    end

    # Check for high error count
    if latest.error_count > 5
      alerts << create_alert(
        workflow: workflow,
        type: "high_error_count",
        severity: "warning",
        message: "Workflow has #{latest.error_count} validation errors",
        metadata: {
          error_count: latest.error_count,
          health_score: latest.health_score
        }
      )
    end

    alerts
  end

  def create_alert(workflow:, type:, severity:, message:, metadata: {})
    {
      workflow_id: workflow.id,
      workflow_name: workflow.name,
      account_id: workflow.account_id,
      type: type,
      severity: severity,
      message: message,
      metadata: metadata,
      created_at: Time.current
    }
  end

  def process_alerts(alerts)
    # Group alerts by account
    alerts_by_account = alerts.group_by { |alert| alert[:account_id] }

    alerts_by_account.each do |account_id, account_alerts|
      # Log alerts
      Rails.logger.warn "[WorkflowValidationHealthCheckJob] Account #{account_id}: #{account_alerts.count} alerts"

      # Here you could:
      # 1. Store alerts in database (if you have an Alert model)
      # 2. Send notifications via email/Slack
      # 3. Broadcast via WebSocket
      # 4. Trigger auto-remediation

      # For now, just log the details
      account_alerts.each do |alert|
        Rails.logger.warn "[WorkflowValidationHealthCheckJob] Alert: #{alert[:type]} - #{alert[:message]}"
      end

      # Broadcast via ActionCable
      broadcast_alerts(account_id, account_alerts)
    end
  end

  def broadcast_alerts(account_id, alerts)
    ActionCable.server.broadcast(
      "account_#{account_id}",
      {
        type: "validation_health_alerts",
        alerts: alerts,
        count: alerts.count
      }
    )
  rescue => e
    Rails.logger.error "[WorkflowValidationHealthCheckJob] Failed to broadcast alerts: #{e.message}"
  end
end
