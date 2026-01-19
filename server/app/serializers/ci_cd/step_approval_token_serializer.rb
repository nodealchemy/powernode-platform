# frozen_string_literal: true

module CiCd
  class StepApprovalTokenSerializer
    def initialize(token, options = {})
      @token = token
      @options = options
    end

    def as_json
      {
        id: @token.id,
        status: @token.status,
        recipient_email: @token.recipient_email,
        expires_at: @token.expires_at,
        responded_at: @token.responded_at,
        response_comment: @token.response_comment,
        time_remaining_seconds: @token.time_remaining,
        step_execution: serialize_step_execution,
        pipeline_info: serialize_pipeline_info,
        responded_by_email: @token.responded_by&.email
      }
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(token, options = {})
      new(token, options).as_json
    end

    def self.serialize_collection(tokens, options = {})
      tokens.map { |token| serialize(token, options) }
    end

    private

    def serialize_step_execution
      {
        id: @token.step_execution.id,
        step_name: @token.step_execution.step_name,
        step_type: @token.step_execution.step_type,
        status: @token.step_execution.status
      }
    end

    def serialize_pipeline_info
      run = @token.step_execution.pipeline_run
      {
        pipeline_name: run.pipeline.name,
        run_number: run.run_number,
        trigger_type: run.trigger_type
      }
    end
  end
end
