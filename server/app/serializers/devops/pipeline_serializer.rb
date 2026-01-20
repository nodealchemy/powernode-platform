# frozen_string_literal: true

module Devops
  class PipelineSerializer
    def initialize(pipeline, options = {})
      @pipeline = pipeline
      @options = options
    end

    def as_json
      {
        id: @pipeline.id,
        name: @pipeline.name,
        slug: @pipeline.slug,
        description: @pipeline.description,
        pipeline_type: @pipeline.pipeline_type,
        triggers: @pipeline.triggers,
        environment: @pipeline.environment,
        secret_refs: @pipeline.secret_refs,
        runner_labels: @pipeline.runner_labels,
        timeout_minutes: @pipeline.timeout_minutes,
        allow_concurrent: @pipeline.allow_concurrent,
        features: @pipeline.features,
        is_active: @pipeline.is_active,
        is_system: @pipeline.is_system,
        version: @pipeline.version,
        step_count: @pipeline.pipeline_steps.size,
        run_count: @pipeline.runs.count,
        last_run: serialize_last_run,
        success_rate: calculate_success_rate,
        created_at: @pipeline.created_at,
        updated_at: @pipeline.updated_at
      }
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(pipeline, options = {})
      new(pipeline, options).as_json
    end

    def self.serialize_collection(pipelines, options = {})
      pipelines.map { |pipeline| serialize(pipeline, options) }
    end

    private

    def serialize_last_run
      last = @pipeline.runs.order(created_at: :desc).first
      return nil unless last

      {
        id: last.id,
        run_number: last.run_number,
        status: last.status,
        started_at: last.started_at,
        completed_at: last.completed_at
      }
    end

    def calculate_success_rate
      total = @pipeline.runs.where(status: %w[success failure cancelled]).count
      return nil if total.zero?

      successful = @pipeline.runs.where(status: "success").count
      ((successful.to_f / total) * 100).round(1)
    end
  end
end
