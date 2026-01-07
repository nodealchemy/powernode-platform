# frozen_string_literal: true

module CiCd
  # Orchestrates pipeline execution and triggers matching pipelines
  class PipelineExecutor
    class ExecutionError < StandardError; end

    attr_reader :pipeline_run

    def initialize(pipeline_run)
      @pipeline_run = pipeline_run
    end

    # Execute the pipeline run
    # @return [CiCd::PipelineRun] The updated pipeline run
    def execute
      start_execution

      pipeline_run.pipeline.pipeline_steps.ordered.each do |step|
        next unless step.is_enabled?

        execute_step(step)

        # Stop if step failed and continue_on_failure is not set
        if current_step_failed? && !step.config&.dig("continue_on_failure")
          break
        end
      end

      complete_execution
      pipeline_run
    rescue StandardError => e
      fail_execution(e.message)
      raise ExecutionError, e.message
    end

    class << self
      # Trigger pipelines that match the given event
      # @param event_type [String] The event type (e.g., "pull_request", "push")
      # @param payload [Hash] The webhook payload
      # @param account [Account] The account to scope pipelines
      # @return [Array<CiCd::PipelineRun>] Created pipeline runs
      def trigger_matching_pipelines(event_type:, payload:, account:)
        matching_pipelines = find_matching_pipelines(event_type, payload, account)

        matching_pipelines.map do |pipeline|
          create_pipeline_run(pipeline, event_type, payload)
        end
      end

      # Trigger a specific pipeline
      # @param pipeline [CiCd::Pipeline] The pipeline to trigger
      # @param trigger_type [Symbol] The trigger type (:manual, :webhook, :schedule)
      # @param context [Hash] The trigger context
      # @param triggered_by [User, nil] The user who triggered the run
      # @return [CiCd::PipelineRun] The created pipeline run
      def trigger(pipeline, trigger_type:, context: {}, triggered_by: nil)
        run = pipeline.pipeline_runs.create!(
          status: :pending,
          trigger_type: trigger_type,
          trigger_context: context,
          triggered_by: triggered_by
        )

        # Queue async execution
        # CiCd::PipelineExecutionJob.perform_async(run.id)

        run
      end

      private

      def find_matching_pipelines(event_type, payload, account)
        account.ci_cd_pipelines.active.select do |pipeline|
          pipeline.matches_trigger?(event_type, payload)
        end
      end

      def create_pipeline_run(pipeline, event_type, payload)
        context = extract_trigger_context(event_type, payload)

        run = pipeline.pipeline_runs.create!(
          status: :pending,
          trigger_type: :webhook,
          trigger_context: context
        )

        # Queue async execution
        # CiCd::PipelineExecutionJob.perform_async(run.id)

        run
      end

      def extract_trigger_context(event_type, payload)
        context = {
          event_type: event_type,
          received_at: Time.current.iso8601
        }

        case event_type
        when "pull_request"
          context.merge!(extract_pr_context(payload))
        when "push"
          context.merge!(extract_push_context(payload))
        when "issues"
          context.merge!(extract_issue_context(payload))
        when "release"
          context.merge!(extract_release_context(payload))
        end

        context
      end

      def extract_pr_context(payload)
        pr = payload["pull_request"] || {}
        {
          pr_number: pr["number"],
          pr_title: pr["title"],
          pr_body: pr["body"],
          pr_action: payload["action"],
          head_sha: pr.dig("head", "sha"),
          head_branch: pr.dig("head", "ref"),
          base_branch: pr.dig("base", "ref"),
          repository: payload.dig("repository", "full_name")
        }
      end

      def extract_push_context(payload)
        {
          ref: payload["ref"],
          before: payload["before"],
          after: payload["after"],
          commits: (payload["commits"] || []).map { |c| { sha: c["id"], message: c["message"] } },
          repository: payload.dig("repository", "full_name")
        }
      end

      def extract_issue_context(payload)
        issue = payload["issue"] || {}
        {
          issue_number: issue["number"],
          issue_title: issue["title"],
          issue_body: issue["body"],
          issue_action: payload["action"],
          labels: (issue["labels"] || []).map { |l| l["name"] },
          repository: payload.dig("repository", "full_name")
        }
      end

      def extract_release_context(payload)
        release = payload["release"] || {}
        {
          tag_name: release["tag_name"],
          release_name: release["name"],
          release_body: release["body"],
          draft: release["draft"],
          prerelease: release["prerelease"],
          repository: payload.dig("repository", "full_name")
        }
      end
    end

    private

    def start_execution
      pipeline_run.update!(
        status: :running,
        started_at: Time.current
      )
    end

    def execute_step(step)
      execution = create_step_execution(step)

      begin
        execution.update!(status: :running, started_at: Time.current)

        # Delegate to step handler
        result = step.execute(
          context: build_step_context,
          previous_outputs: collect_previous_outputs
        )

        execution.update!(
          status: :success,
          completed_at: Time.current,
          duration_seconds: calculate_duration(execution.started_at),
          outputs: result[:outputs],
          logs: result[:logs]
        )
      rescue StandardError => e
        execution.update!(
          status: :failed,
          completed_at: Time.current,
          duration_seconds: calculate_duration(execution.started_at),
          error_message: e.message,
          logs: e.backtrace&.first(10)&.join("\n")
        )
      end
    end

    def create_step_execution(step)
      pipeline_run.step_executions.create!(
        pipeline_step: step,
        status: :pending
      )
    end

    def build_step_context
      {
        pipeline: {
          id: pipeline_run.pipeline.id,
          name: pipeline_run.pipeline.name,
          slug: pipeline_run.pipeline.slug
        },
        run: {
          id: pipeline_run.id,
          run_number: pipeline_run.run_number,
          trigger_type: pipeline_run.trigger_type,
          trigger_context: pipeline_run.trigger_context
        },
        ai_config: pipeline_run.pipeline.ai_config&.environment_variables
      }
    end

    def collect_previous_outputs
      pipeline_run.step_executions
                  .includes(:pipeline_step)
                  .where(status: :success)
                  .each_with_object({}) do |execution, hash|
        hash[execution.pipeline_step.slug] = execution.outputs
      end
    end

    def current_step_failed?
      pipeline_run.step_executions.order(:created_at).last&.failed?
    end

    def complete_execution
      failed_steps = pipeline_run.step_executions.where(status: :failed).count
      status = failed_steps > 0 ? :failed : :success

      pipeline_run.update!(
        status: status,
        completed_at: Time.current,
        duration_seconds: calculate_duration(pipeline_run.started_at),
        outputs: collect_final_outputs
      )
    end

    def fail_execution(error_message)
      pipeline_run.update!(
        status: :failed,
        completed_at: Time.current,
        duration_seconds: pipeline_run.started_at ? calculate_duration(pipeline_run.started_at) : 0,
        error_message: error_message
      )
    end

    def collect_final_outputs
      pipeline_run.step_executions
                  .includes(:pipeline_step)
                  .where(status: :success)
                  .each_with_object({}) do |execution, hash|
        hash[execution.pipeline_step.slug] = execution.outputs
      end
    end

    def calculate_duration(started_at)
      return 0 unless started_at

      (Time.current - started_at).to_i
    end
  end
end
