# frozen_string_literal: true

class WorkflowTimeoutJob < BaseJob
  sidekiq_options queue: 'maintenance', retry: 1

  def execute(workflow_run_id)
    @workflow_run_id = workflow_run_id

    log_info("Checking timeout for workflow run: #{workflow_run_id}")

    # Get workflow run from backend API
    response = backend_api_get("/api/v1/ai/workflow_runs/#{workflow_run_id}")

    unless response['success']
      log_warn("Could not fetch workflow run #{workflow_run_id}: #{response['error']}")
      return
    end

    workflow_run_data = response['data']['workflow_run']

    # Check if workflow is still active
    unless %w[initializing running waiting_approval].include?(workflow_run_data['status'])
      log_info("Workflow #{workflow_run_id} no longer active (#{workflow_run_data['status']}), skipping timeout check")
      return
    end

    # Call backend to check and handle timeout
    timeout_response = backend_api_post("/api/v1/ai/workflow_runs/#{workflow_run_id}/check_timeout", {})

    if timeout_response['success'] && timeout_response['data']['timed_out']
      log_info("Workflow #{workflow_run_id} automatically timed out: #{timeout_response['data']['reason']}")
    elsif timeout_response['success']
      log_info("Workflow #{workflow_run_id} timeout check passed")

      # Reschedule next check if still active (check every 2 minutes)
      if %w[initializing running waiting_approval].include?(workflow_run_data['status'])
        WorkflowTimeoutJob.perform_in(2.minutes, workflow_run_id)
        log_info("Rescheduled timeout check for workflow #{workflow_run_id} in 2 minutes")
      end
    else
      log_error("Failed to check timeout for workflow #{workflow_run_id}: #{timeout_response['error']}")
    end

  rescue StandardError => e
    log_error("Error in WorkflowTimeoutJob for #{workflow_run_id}: #{e.message}")
    log_error(e.backtrace.join("\n"))
    raise e
  end

  private

  def backend_api_get(path)
    BackendApiClient.instance.get(path)
  end

  def backend_api_post(path, data = {})
    BackendApiClient.instance.post(path, data)
  end
end