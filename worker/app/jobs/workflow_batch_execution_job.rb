# frozen_string_literal: true

# Background job for executing workflows as part of a batch
class WorkflowBatchExecutionJob < BaseJob
  sidekiq_options queue: :workflow_high_priority

  # Execute a single workflow as part of a batch operation
  def execute(workflow_id:, batch_id:, user_id: nil, execution_options: {})
    @workflow_id = workflow_id
    @batch_id = batch_id
    @user_id = user_id
    @execution_options = execution_options

    log_info("[BATCH_JOB] Starting batch workflow execution - Workflow: #{workflow_id}, Batch: #{batch_id}")

    # Make API call to backend to get workflow details
    workflow_data = fetch_workflow_data
    return handle_workflow_not_found unless workflow_data

    # Create workflow run via API
    workflow_run = create_workflow_run(workflow_data)
    return handle_run_creation_failure unless workflow_run

    # Execute the workflow
    execute_workflow_via_api(workflow_run)

    # Update batch progress
    update_batch_progress(success: true)

    log_info("[BATCH_JOB] Completed workflow #{workflow_id} in batch #{batch_id}")

  rescue StandardError => e
    log_error("[BATCH_JOB] Error executing workflow #{workflow_id}: #{e.message}")
    log_error(e.backtrace.join("\n"))
    update_batch_progress(success: false, error: e.message)
    raise e
  end

  private

  def fetch_workflow_data
    response = api_client.get("/api/v1/ai/workflows/#{@workflow_id}")

    if response['success']
      response['data']
    else
      log_error("[BATCH_JOB] Failed to fetch workflow: #{response['error']}")
      nil
    end
  rescue StandardError => e
    log_error("[BATCH_JOB] API error fetching workflow: #{e.message}")
    nil
  end

  def create_workflow_run(workflow_data)
    run_params = {
      workflow_id: @workflow_id,
      trigger_type: @execution_options['trigger_type'] || 'batch',
      input_variables: @execution_options['input_variables'] || {},
      metadata: {
        batch_id: @batch_id,
        execution_options: @execution_options
      }
    }

    response = api_client.post("/api/v1/ai/workflow_runs", run_params)

    if response['success']
      response['data']
    else
      log_error("[BATCH_JOB] Failed to create workflow run: #{response['error']}")
      nil
    end
  rescue StandardError => e
    log_error("[BATCH_JOB] API error creating workflow run: #{e.message}")
    nil
  end

  def execute_workflow_via_api(workflow_run)
    # Trigger workflow execution through API
    response = api_client.post(
      "/api/v1/ai/workflow_runs/#{workflow_run['run_id']}/execute",
      {}
    )

    unless response['success']
      raise "Workflow execution failed: #{response['error']}"
    end

    # Monitor execution status if needed
    if @execution_options['wait_for_completion']
      monitor_workflow_execution(workflow_run['run_id'])
    end
  end

  def monitor_workflow_execution(run_id)
    max_attempts = 60 # 5 minutes with 5-second intervals
    attempts = 0

    loop do
      attempts += 1
      break if attempts > max_attempts

      response = api_client.get("/api/v1/ai/workflow_runs/#{run_id}")

      if response['success']
        run_data = response['data']

        case run_data['status']
        when 'completed'
          log_info("[BATCH_JOB] Workflow #{run_id} completed successfully")
          return true
        when 'failed', 'cancelled'
          log_error("[BATCH_JOB] Workflow #{run_id} failed with status: #{run_data['status']}")
          return false
        when 'running', 'initializing'
          # Still processing, wait and check again
          sleep(5)
        else
          log_warn("[BATCH_JOB] Unknown workflow status: #{run_data['status']}")
          sleep(5)
        end
      else
        log_error("[BATCH_JOB] Failed to check workflow status: #{response['error']}")
        sleep(5)
      end
    end

    log_error("[BATCH_JOB] Workflow #{run_id} execution timeout")
    false
  end

  def update_batch_progress(success:, error: nil)
    # Update batch run progress via API
    update_params = {
      workflow_id: @workflow_id,
      success: success,
      error: error,
      completed_at: Time.current.iso8601
    }

    response = api_client.patch(
      "/api/v1/ai/batch_runs/#{@batch_id}/progress",
      update_params
    )

    unless response['success']
      log_error("[BATCH_JOB] Failed to update batch progress: #{response['error']}")
    end
  rescue StandardError => e
    log_error("[BATCH_JOB] Error updating batch progress: #{e.message}")
  end

  def handle_workflow_not_found
    log_error("[BATCH_JOB] Workflow #{@workflow_id} not found")
    update_batch_progress(success: false, error: 'Workflow not found')
  end

  def handle_run_creation_failure
    log_error("[BATCH_JOB] Failed to create workflow run for #{@workflow_id}")
    update_batch_progress(success: false, error: 'Failed to create workflow run')
  end

  def api_client
    @api_client ||= BackendApiClient.new
  end
end