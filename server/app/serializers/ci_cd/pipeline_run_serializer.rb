# frozen_string_literal: true

module CiCd
  class PipelineRunSerializer
    def initialize(run, options = {})
      @run = run
      @options = options
    end

    def as_json
      {
        id: @run.id,
        run_number: @run.run_number,
        status: @run.status,
        trigger_type: @run.trigger_type,
        trigger_context: @run.trigger_context,
        started_at: @run.started_at,
        completed_at: @run.completed_at,
        duration_seconds: @run.duration_seconds,
        outputs: @run.outputs,
        artifacts: @run.artifacts,
        error_message: @run.error_message,
        external_run_id: @run.external_run_id,
        external_run_url: @run.external_run_url,
        progress_percentage: @run.progress_percentage,
        pr_number: @run.pr_number,
        commit_sha: @run.commit_sha,
        branch: @run.branch,
        step_execution_count: @run.step_executions.count,
        current_step: serialize_current_step,
        created_at: @run.created_at,
        updated_at: @run.updated_at
      }
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(run, options = {})
      new(run, options).as_json
    end

    def self.serialize_collection(runs, options = {})
      runs.map { |run| serialize(run, options) }
    end

    private

    def serialize_current_step
      current = @run.current_step
      return nil unless current

      {
        id: current.id,
        name: current.pipeline_step.name,
        step_type: current.pipeline_step.step_type,
        status: current.status
      }
    end
  end
end
