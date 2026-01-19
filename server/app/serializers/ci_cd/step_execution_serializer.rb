# frozen_string_literal: true

module CiCd
  class StepExecutionSerializer
    def initialize(execution, options = {})
      @execution = execution
      @options = options
    end

    def as_json
      {
        id: @execution.id,
        status: @execution.status,
        started_at: @execution.started_at,
        completed_at: @execution.completed_at,
        duration_seconds: @execution.duration_seconds,
        outputs: @execution.outputs,
        logs: @execution.logs,
        error_message: @execution.error_message,
        step_name: @execution.step_name,
        step_type: @execution.step_type,
        position: @execution.pipeline_step.position,
        created_at: @execution.created_at,
        updated_at: @execution.updated_at
      }
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(execution, options = {})
      new(execution, options).as_json
    end

    def self.serialize_collection(executions, options = {})
      executions.map { |execution| serialize(execution, options) }
    end
  end
end
