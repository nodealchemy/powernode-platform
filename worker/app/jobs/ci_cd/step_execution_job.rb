# frozen_string_literal: true

module CiCd
  # Executes individual pipeline steps
  # Queue: ci_cd_default
  # Retry: 1
  class StepExecutionJob < BaseJob
    sidekiq_options queue: "ci_cd_default", retry: 1

    # Execute a single pipeline step
    # @param step_execution_id [String] The step execution ID
    def execute(step_execution_id)
      log_info "Starting step execution", step_execution_id: step_execution_id

      # Fetch step execution and config
      execution_data = fetch_step_execution(step_execution_id)
      step_config = execution_data["pipeline_step"]

      # Update status to running
      update_execution(step_execution_id, status: "running", started_at: Time.current.iso8601)

      # Get the appropriate handler and execute
      handler = get_step_handler(step_config["step_type"])
      result = handler.execute(
        config: step_config["config"],
        context: build_context(execution_data),
        previous_outputs: fetch_previous_outputs(execution_data["pipeline_run_id"])
      )

      # Update execution with results
      update_execution(
        step_execution_id,
        status: "success",
        completed_at: Time.current.iso8601,
        outputs: result[:outputs],
        logs: result[:logs]
      )

      log_info "Step execution completed", step_execution_id: step_execution_id
    rescue StandardError => e
      log_error "Step execution failed", e, step_execution_id: step_execution_id

      update_execution(
        step_execution_id,
        status: "failed",
        completed_at: Time.current.iso8601,
        error_message: e.message,
        logs: e.backtrace&.first(10)&.join("\n")
      )

      raise
    end

    private

    def fetch_step_execution(step_execution_id)
      response = api_client.get("/api/v1/internal/ci_cd/step_executions/#{step_execution_id}")
      response.dig("data", "step_execution")
    end

    def update_execution(step_execution_id, **attributes)
      api_client.patch("/api/v1/internal/ci_cd/step_executions/#{step_execution_id}", {
        step_execution: attributes
      })
    end

    def get_step_handler(step_type)
      handler_class = case step_type
                      when "checkout"
                        StepHandlers::CheckoutHandler
                      when "claude_execute"
                        StepHandlers::ClaudeExecuteHandler
                      when "post_comment"
                        StepHandlers::PostCommentHandler
                      when "create_pr"
                        StepHandlers::CreatePrHandler
                      when "deploy"
                        StepHandlers::DeployHandler
                      when "upload_artifact"
                        StepHandlers::UploadArtifactHandler
                      when "run_command"
                        StepHandlers::RunCommandHandler
                      else
                        StepHandlers::GenericHandler
                      end

      handler_class.new(api_client: api_client, logger: logger)
    end

    def build_context(execution_data)
      pipeline_run = fetch_pipeline_run(execution_data["pipeline_run_id"])

      {
        pipeline_run: pipeline_run,
        trigger_context: pipeline_run["trigger_context"],
        step_name: execution_data.dig("pipeline_step", "name"),
        step_type: execution_data.dig("pipeline_step", "step_type")
      }
    end

    def fetch_pipeline_run(pipeline_run_id)
      response = api_client.get("/api/v1/internal/ci_cd/pipeline_runs/#{pipeline_run_id}")
      response.dig("data", "pipeline_run")
    end

    def fetch_previous_outputs(pipeline_run_id)
      response = api_client.get("/api/v1/internal/ci_cd/pipeline_runs/#{pipeline_run_id}/step_executions")
      executions = response.dig("data", "step_executions") || []

      executions.each_with_object({}) do |execution, hash|
        next unless execution["status"] == "success"

        step_slug = execution.dig("pipeline_step", "slug")
        hash[step_slug] = execution["outputs"] if step_slug
      end
    end
  end
end
