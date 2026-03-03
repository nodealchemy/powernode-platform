# frozen_string_literal: true

module Devops
  # Orchestrates full pipeline runs by executing steps sequentially.
  # Fetches the pipeline run and its steps from the internal API,
  # creates step executions for every active step, then processes
  # each one in order — handling simulation mode, approval gates,
  # and real handler execution.
  #
  # Queue: devops_high
  # Retry: 1
  class PipelineExecutionJob < BaseJob
    sidekiq_options queue: "devops_high", retry: 1

    # @param pipeline_run_id [String] The pipeline run UUID
    # @param options [Hash] Execution options from the trigger endpoint
    #   - simulate [Boolean] Run in simulation mode (no real handlers)
    #   - step_delay [Integer] Seconds to sleep per simulated step
    #   - fail_step [Integer] Step position to simulate failure at
    def execute(pipeline_run_id, options = {})
      @options = normalize_options(options)
      @pipeline_run_id = pipeline_run_id

      log_info "Starting pipeline execution",
               pipeline_run_id: pipeline_run_id,
               simulate: @options[:simulate]

      # 1. Fetch pipeline run with steps
      @run_data = fetch_pipeline_run(pipeline_run_id)
      steps = @run_data["steps"] || []

      if steps.empty?
        log_warn "No active steps found", pipeline_run_id: pipeline_run_id
        update_pipeline_run(status: "success", started_at: now_iso, completed_at: now_iso)
        return
      end

      # 2. Transition run to "running"
      update_pipeline_run(status: "running", started_at: now_iso)

      # 3. Create step executions for ALL steps upfront.
      #    This prevents the notify_pipeline_run callback from
      #    prematurely completing the run after just one step finishes.
      step_executions = create_all_step_executions(pipeline_run_id, steps)

      # 4. Process each step sequentially
      previous_outputs = {}
      failed = false

      step_executions.each_with_index do |step_exec, index|
        step = steps[index]

        if failed
          update_step_execution(step_exec["id"], status: "skipped")
          next
        end

        result = process_step(step_exec, step, previous_outputs)

        case result[:status]
        when "waiting_approval"
          log_info "Pipeline paused for approval", step_name: step["name"]
          return
        when "success"
          previous_outputs[step["name"]] = result[:outputs] || {}
        when "failure"
          if step["continue_on_error"]
            previous_outputs[step["name"]] = result[:outputs] || {}
          else
            failed = true
          end
        end
      end

      # The notify_pipeline_run callback on StepExecution handles the
      # final run status once all step executions are completed/skipped.
      log_info "Pipeline execution finished", pipeline_run_id: pipeline_run_id
    rescue StandardError => e
      log_error "Pipeline execution failed", e, pipeline_run_id: pipeline_run_id
      update_pipeline_run(
        status: "failure",
        completed_at: now_iso,
        error_message: "Orchestrator error: #{e.message}"
      )
      raise
    end

    private

    # Process a single step: approval gate, simulation, or real execution
    def process_step(step_exec, step, previous_outputs)
      step_exec_id = step_exec["id"]

      # Approval gate — pause pipeline until human responds
      if step["requires_approval"]
        update_step_execution(step_exec_id,
          status: "waiting_approval",
          started_at: now_iso
        )
        return { status: "waiting_approval" }
      end

      # Simulation mode — sleep then succeed/fail based on options
      if @options[:simulate]
        return simulate_step(step_exec_id, step)
      end

      # Real execution via step handler
      execute_step_handler(step_exec_id, step, previous_outputs)
    rescue StandardError => e
      log_error "Step failed", e, step_name: step["name"]
      update_step_execution(step_exec_id,
        status: "failure",
        completed_at: now_iso,
        error_message: e.message,
        logs: e.backtrace&.first(5)&.join("\n")
      )
      { status: "failure", error_message: e.message, outputs: {} }
    end

    # Simulate step execution with configurable delay and failure
    def simulate_step(step_exec_id, step)
      delay = @options[:step_delay]
      fail_position = @options[:fail_step]

      sleep(delay) if delay.positive?

      if fail_position && step["position"] == fail_position
        update_step_execution(step_exec_id,
          status: "failure",
          started_at: now_iso,
          completed_at: now_iso,
          error_message: "Simulated failure at step position #{fail_position}",
          logs: "Simulation: step failed (fail_step=#{fail_position})"
        )
        { status: "failure", error_message: "Simulated failure", outputs: {} }
      else
        update_step_execution(step_exec_id,
          status: "success",
          started_at: now_iso,
          completed_at: now_iso,
          outputs: { simulated: true },
          logs: "Simulation: step completed successfully"
        )
        { status: "success", outputs: { "simulated" => true } }
      end
    end

    # Execute a step handler inline and update the step execution
    def execute_step_handler(step_exec_id, step, previous_outputs)
      config = step["configuration"] || {}

      update_step_execution(step_exec_id, status: "running", started_at: now_iso)

      handler = get_step_handler(step["step_type"])
      result = handler.execute(
        config: config,
        context: build_execution_context,
        previous_outputs: previous_outputs
      )

      update_step_execution(step_exec_id,
        status: "success",
        completed_at: now_iso,
        outputs: result[:outputs] || {},
        logs: result[:logs]
      )

      { status: "success", outputs: result[:outputs] || {} }
    end

    # Resolve step type to handler class (mirrors StepExecutionJob map)
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
                      when "run_command", "run_tests"
                        StepHandlers::RunCommandHandler
                      when "create_branch"
                        StepHandlers::CheckoutHandler
                      else
                        StepHandlers::GenericHandler
                      end

      handler_class.new(api_client: api_client, logger: logger)
    end

    # --- API Communication ---

    def fetch_pipeline_run(pipeline_run_id)
      response = api_client.get("/api/v1/internal/devops/pipeline_runs/#{pipeline_run_id}")
      response.dig("data", "pipeline_run")
    end

    def update_pipeline_run(**attributes)
      api_client.patch("/api/v1/internal/devops/pipeline_runs/#{@pipeline_run_id}", {
        pipeline_run: attributes
      })
    end

    def create_step_execution(pipeline_run_id, step_id)
      response = api_client.post("/api/v1/internal/devops/step_executions", {
        step_execution: {
          pipeline_run_id: pipeline_run_id,
          pipeline_step_id: step_id,
          status: "pending"
        }
      })
      response.dig("data", "step_execution")
    end

    def update_step_execution(step_exec_id, **attributes)
      api_client.patch("/api/v1/internal/devops/step_executions/#{step_exec_id}", {
        step_execution: attributes
      })
    end

    def create_all_step_executions(pipeline_run_id, steps)
      steps.map { |step| create_step_execution(pipeline_run_id, step["id"]) }
    end

    def build_execution_context
      @execution_context ||= {
        pipeline_run: @run_data,
        trigger_context: @run_data["trigger_context"] || {}
      }
    end

    def normalize_options(options)
      opts = options.is_a?(Hash) ? options : {}
      {
        simulate: opts["simulate"] || opts[:simulate] || false,
        step_delay: (opts["step_delay"] || opts[:step_delay] || 3).to_i,
        fail_step: opts["fail_step"] || opts[:fail_step]
      }
    end

    def now_iso
      Time.current.iso8601
    end
  end
end
