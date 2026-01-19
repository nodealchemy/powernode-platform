# frozen_string_literal: true

module Devops
  class PipelineStepSerializer
    def initialize(step, options = {})
      @step = step
      @options = options
    end

    def as_json
      {
        id: @step.id,
        name: @step.name,
        step_type: @step.step_type,
        position: @step.position,
        configuration: @step.configuration,
        inputs: @step.inputs,
        outputs: @step.outputs,
        condition: @step.condition,
        continue_on_error: @step.continue_on_error,
        is_active: @step.is_active,
        output_definitions: @step.output_definitions,
        requires_prompt: @step.requires_prompt?,
        requires_approval: @step.requires_approval,
        approval_settings: @step.approval_settings,
        shared_prompt_template_id: @step.shared_prompt_template_id,
        shared_prompt_template_name: @step.shared_prompt_template&.name,
        created_at: @step.created_at,
        updated_at: @step.updated_at
      }
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(step, options = {})
      new(step, options).as_json
    end

    def self.serialize_collection(steps, options = {})
      steps.map { |step| serialize(step, options) }
    end
  end
end
