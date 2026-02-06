# frozen_string_literal: true

module Devops
  class AiWorkflowTriggerService
    def initialize(account:)
      @account = account
    end

    def on_pipeline_event(pipeline_run:, event_type:)
      return unless Shared::FeatureFlagService.enabled?(:cross_system_triggers)

      triggers = find_matching_triggers(pipeline_run, event_type)
      triggers.each do |trigger|
        execute_workflow_trigger(trigger, pipeline_run)
      end
    end

    def on_deployment_event(deployment:, event_type:)
      return unless Shared::FeatureFlagService.enabled?(:cross_system_triggers)

      triggers = Ai::WorkflowTrigger.where(
        account: @account,
        trigger_type: "devops_pipeline_event",
        is_active: true
      ).select do |t|
        config = t.configuration || {}
        config["event_type"] == event_type
      end

      triggers.each do |trigger|
        execute_workflow_trigger(trigger, deployment)
      end
    end

    private

    def find_matching_triggers(pipeline_run, event_type)
      Ai::WorkflowTrigger.where(
        account: @account,
        trigger_type: "devops_pipeline_event",
        is_active: true
      ).select do |trigger|
        config = trigger.configuration || {}
        matches_event?(config, event_type) &&
          matches_pipeline?(config, pipeline_run)
      end
    end

    def matches_event?(config, event_type)
      events = config["events"] || [config["event_type"]]
      events.include?(event_type)
    end

    def matches_pipeline?(config, pipeline_run)
      pipeline_id = config["pipeline_id"]
      return true unless pipeline_id

      pipeline_run.pipeline.id == pipeline_id
    end

    def execute_workflow_trigger(trigger, source)
      workflow = trigger.workflow
      return unless workflow&.can_execute?

      input_variables = build_input_variables(trigger, source)

      workflow.execute(
        input_variables,
        trigger_type: "devops_event",
        trigger_metadata: {
          trigger_id: trigger.id,
          source_type: source.class.name,
          source_id: source.id,
          triggered_at: Time.current.iso8601
        }
      )
    rescue => e
      Rails.logger.error "[AiWorkflowTrigger] Failed to execute workflow #{trigger.ai_workflow_id}: #{e.message}"
    end

    def build_input_variables(trigger, source)
      variables = trigger.configuration&.dig("input_mapping") || {}

      if source.is_a?(Devops::PipelineRun)
        variables.merge(
          "pipeline_name" => source.pipeline.name,
          "pipeline_status" => source.status,
          "trigger_type" => source.trigger_type,
          "commit_sha" => source.trigger_context&.dig("commit_sha"),
          "branch" => source.trigger_context&.dig("branch")
        )
      else
        variables
      end
    end
  end
end
