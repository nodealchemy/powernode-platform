# frozen_string_literal: true

module Devops
  class StepApprovalToken < ApplicationRecord
    include Approvable

    # Associations
    belongs_to :step_execution, class_name: "Devops::StepExecution"
    belongs_to :recipient_user, class_name: "User", optional: true
    belongs_to :responded_by, class_name: "User", optional: true

    # Scopes
    scope :for_step_execution, ->(step_execution_id) { where(step_execution_id: step_execution_id) }

    # Class Methods
    def self.create_for_recipient(step_execution:, recipient_email:, recipient_user: nil, expires_in: 24.hours)
      raw_token = generate_raw_token
      digest = generate_digest(raw_token)

      token = create!(
        step_execution: step_execution,
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
      {
        token_id: id,
        recipient_email: recipient_email,
        step_name: step_execution.step_name,
        pipeline_name: step_execution.pipeline_run.pipeline.name,
        run_number: step_execution.pipeline_run.run_number,
        trigger_type: step_execution.pipeline_run.trigger_type,
        trigger_context: step_execution.pipeline_run.trigger_context,
        expires_at: expires_at,
        timeout_hours: default_timeout_hours
      }
    end

    private

    def notify_approval!(comment, by_user)
      step_execution.handle_approval_response!(approved: true, comment: comment, by_user: by_user)
    end

    def notify_rejection!(comment, by_user)
      step_execution.handle_approval_response!(approved: false, comment: comment, by_user: by_user)
    end

    def default_timeout_hours
      step_execution&.pipeline_step&.approval_settings&.dig("timeout_hours") || 24
    end
  end
end
