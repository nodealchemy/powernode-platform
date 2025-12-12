# frozen_string_literal: true

# Service for processing multiple workflows in batch
class AiWorkflowBatchProcessor
  include ActiveModel::Model

  attr_accessor :account, :user, :logger

  def initialize(account:, user: nil)
    @account = account
    @user = user
    @logger = Rails.logger
    @batch_id = SecureRandom.uuid
    @batch_results = []
    @processing_queue = Queue.new
    @thread_pool = []
    @max_concurrent = 5 # Maximum concurrent workflow executions
  end

  # Process multiple workflows in batch
  def process_batch(workflow_configs)
    @logger.info "[BATCH] Starting batch processing #{@batch_id} for #{workflow_configs.count} workflows"

    batch_run = create_batch_run(workflow_configs)

    begin
      # Initialize thread pool
      initialize_thread_pool

      # Queue all workflows
      workflow_configs.each_with_index do |config, index|
        @processing_queue << {
          config: config,
          index: index,
          batch_run: batch_run
        }
      end

      # Wait for all processing to complete
      wait_for_completion

      # Aggregate batch results
      finalize_batch(batch_run)

    rescue StandardError => e
      handle_batch_error(batch_run, e)
    ensure
      shutdown_thread_pool
    end

    batch_run
  end

  # Process workflows with common parameters
  def process_parameterized_batch(workflow_template, parameter_sets)
    @logger.info "[BATCH] Processing parameterized batch with #{parameter_sets.count} parameter sets"

    configs = parameter_sets.map do |params|
      {
        workflow_id: workflow_template.id,
        input_variables: params,
        trigger_type: "batch"
      }
    end

    process_batch(configs)
  end

  # Process workflows in scheduled intervals
  def process_scheduled_batch(workflows, schedule_config)
    @logger.info "[BATCH] Processing scheduled batch for #{workflows.count} workflows"

    batch_schedule = create_batch_schedule(workflows, schedule_config)

    workflows.each_with_index do |workflow, index|
      delay = calculate_delay(index, schedule_config)

      # Schedule execution
      WorkflowBatchExecutionJob.set(wait: delay).perform_later(
        workflow_id: workflow.id,
        batch_id: @batch_id,
        user_id: @user&.id,
        execution_options: schedule_config[:execution_options] || {}
      )
    end

    batch_schedule
  end

  private

  def create_batch_run(workflow_configs)
    BatchWorkflowRun.create!(
      batch_id: @batch_id,
      account: @account,
      user: @user,
      total_workflows: workflow_configs.count,
      status: "processing",
      started_at: Time.current,
      configuration: {
        max_concurrent: @max_concurrent,
        configs: workflow_configs
      }
    )
  end

  def initialize_thread_pool
    @max_concurrent.times do
      thread = Thread.new do
        process_workflow_queue
      end
      @thread_pool << thread
    end
  end

  def process_workflow_queue
    while !@processing_queue.empty? || !@shutdown_requested
      begin
        # Get next workflow from queue (with timeout)
        item = @processing_queue.pop(true) rescue nil
        break unless item

        process_single_workflow(item)

      rescue StandardError => e
        @logger.error "[BATCH] Thread error: #{e.message}"
      end
    end
  end

  def process_single_workflow(item)
    config = item[:config]
    batch_run = item[:batch_run]

    @logger.info "[BATCH] Processing workflow #{item[:index] + 1} in batch #{@batch_id}"

    begin
      # Find workflow
      workflow = AiWorkflow.find(config[:workflow_id])

      # Create workflow run
      workflow_run = workflow.runs.create!(
        account: @account,
        triggered_by_user: @user,
        status: "initializing",
        trigger_type: config[:trigger_type] || "batch",
        input_variables: config[:input_variables] || {},
        metadata: {
          batch_id: @batch_id,
          batch_index: item[:index]
        }
      )

      # Execute workflow using MCP orchestrator
      orchestrator = Mcp::AiWorkflowOrchestrator.new(
        workflow_run: workflow_run,
        account: @account,
        user: @user
      )

      orchestrator.execute
      workflow_run.reload

      # Record result
      record_workflow_result(batch_run, workflow_run, "success")

    rescue StandardError => e
      @logger.error "[BATCH] Workflow execution failed: #{e.message}"
      record_workflow_result(batch_run, workflow_run, "failed", e.message)
    end
  end

  def record_workflow_result(batch_run, workflow_run, status, error = nil)
    result = {
      workflow_id: workflow_run&.ai_workflow_id,
      run_id: workflow_run&.run_id,
      status: status,
      error: error,
      completed_at: Time.current
    }

    @batch_results << result

    # Update batch run progress
    batch_run.increment!(:completed_workflows)

    if status == "failed"
      batch_run.increment!(:failed_workflows)
    else
      batch_run.increment!(:successful_workflows)
    end

    # Broadcast progress
    broadcast_batch_progress(batch_run)
  end

  def wait_for_completion
    @thread_pool.each(&:join)
  end

  def shutdown_thread_pool
    @shutdown_requested = true
    @thread_pool.each { |t| t.kill if t.alive? }
  end

  def finalize_batch(batch_run)
    @logger.info "[BATCH] Finalizing batch #{@batch_id}"

    batch_run.update!(
      status: "completed",
      completed_at: Time.current,
      results: @batch_results,
      duration_ms: ((Time.current - batch_run.started_at) * 1000).to_i
    )

    # Calculate statistics
    stats = calculate_batch_statistics(batch_run)
    batch_run.update!(statistics: stats)

    broadcast_batch_completion(batch_run)
  end

  def handle_batch_error(batch_run, error)
    @logger.error "[BATCH] Batch processing failed: #{error.message}"

    batch_run.update!(
      status: "failed",
      completed_at: Time.current,
      error_details: {
        error: error.message,
        error_class: error.class.name,
        backtrace: error.backtrace.first(10)
      }
    )
  end

  def calculate_batch_statistics(batch_run)
    {
      total_workflows: batch_run.total_workflows,
      successful: batch_run.successful_workflows,
      failed: batch_run.failed_workflows,
      success_rate: (batch_run.successful_workflows.to_f / batch_run.total_workflows * 100).round(2),
      average_duration: calculate_average_duration(@batch_results),
      total_duration_ms: batch_run.duration_ms
    }
  end

  def calculate_average_duration(results)
    # This would calculate average duration from individual workflow runs
    0 # Placeholder
  end

  def broadcast_batch_progress(batch_run)
    ActionCable.server.broadcast(
      "batch_processing_#{@batch_id}",
      {
        type: "batch_progress",
        batch_id: @batch_id,
        progress: {
          total: batch_run.total_workflows,
          completed: batch_run.completed_workflows,
          successful: batch_run.successful_workflows,
          failed: batch_run.failed_workflows,
          percentage: (batch_run.completed_workflows.to_f / batch_run.total_workflows * 100).round(2)
        }
      }
    )
  end

  def broadcast_batch_completion(batch_run)
    ActionCable.server.broadcast(
      "batch_processing_#{@batch_id}",
      {
        type: "batch_completed",
        batch_id: @batch_id,
        statistics: batch_run.statistics,
        completed_at: batch_run.completed_at
      }
    )
  end

  def create_batch_schedule(workflows, schedule_config)
    {
      batch_id: @batch_id,
      workflows: workflows.map(&:id),
      schedule_config: schedule_config,
      created_at: Time.current
    }
  end

  def calculate_delay(index, schedule_config)
    case schedule_config[:type]
    when "staggered"
      index * (schedule_config[:interval] || 10).seconds
    when "fixed_rate"
      (index / schedule_config[:batch_size].to_f).floor * schedule_config[:interval].seconds
    else
      0
    end
  end
end
