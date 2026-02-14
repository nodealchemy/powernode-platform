# frozen_string_literal: true

module Ai
  class WorkflowApprovalToken < ApplicationRecord
    include Approvable

    # Associations
    belongs_to :node_execution, class_name: "Ai::WorkflowNodeExecution",
               foreign_key: "ai_workflow_node_execution_id"
    belongs_to :recipient_user, class_name: "User", foreign_key: "recipient_user_id", optional: true
    belongs_to :responded_by, class_name: "User", foreign_key: "responded_by_id", optional: true

    # Scopes
    scope :for_node_execution, ->(node_execution_id) { where(ai_workflow_node_execution_id: node_execution_id) }

    # Class Methods
    def self.create_for_recipient(node_execution:, recipient_email:, recipient_user: nil, expires_in: 24.hours)
      raw_token = generate_raw_token
      digest = generate_digest(raw_token)

      token = create!(
        node_execution: node_execution,
        token_digest: digest,
        recipient_email: recipient_email,
        recipient_user: recipient_user,
        expires_at: Time.current + expires_in
      )

      [ token, raw_token ]
    end

    # Backwards compatibility alias
    def expired?
      token_expired?
    end

    def email_context
      workflow_run = node_execution.workflow_run
      workflow = workflow_run.workflow
      node = node_execution.node

      {
        token_id: id,
        recipient_email: recipient_email,
        node_name: node&.name || "Human Approval",
        workflow_name: workflow.name,
        run_id: workflow_run.run_id,
        trigger_type: workflow_run.trigger_type,
        approval_message: node_execution.metadata["approval_message"],
        expires_at: expires_at,
        timeout_hours: default_timeout_hours
      }
    end

    private

    def notify_approval!(comment, by_user)
      node_execution.approve_execution!(
        by_user&.id,
        { "approved" => true, "comment" => comment, "reason" => comment }
      )
    end

    def notify_rejection!(comment, by_user)
      node_execution.approve_execution!(
        by_user&.id,
        { "approved" => false, "comment" => comment, "reason" => comment }
      )
    end

    def default_timeout_hours
      node_execution&.node&.configuration&.dig("approval_timeout_hours") || 24
    end
  end
end
