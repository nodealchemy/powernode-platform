# frozen_string_literal: true

module CiCd
  class StepApprovalTokenSerializer < BaseSerializer
    attributes :id, :status, :recipient_email, :expires_at, :responded_at,
               :response_comment, :time_remaining_seconds

    attribute :step_execution do |token|
      {
        id: token.step_execution.id,
        step_name: token.step_execution.step_name,
        step_type: token.step_execution.step_type,
        status: token.step_execution.status
      }
    end

    attribute :pipeline_info do |token|
      run = token.step_execution.pipeline_run
      {
        pipeline_name: run.pipeline.name,
        run_number: run.run_number,
        trigger_type: run.trigger_type
      }
    end

    attribute :time_remaining_seconds do |token|
      token.time_remaining
    end

    attribute :responded_by_email do |token|
      token.responded_by&.email
    end
  end
end
