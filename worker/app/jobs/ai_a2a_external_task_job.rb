# frozen_string_literal: true

require_relative '../services/a2a/a2a_client'

class AiA2aExternalTaskJob < BaseJob
  include AiJobsConcern
  include AiSuspensionCheckConcern

  sidekiq_options queue: 'ai_agents', retry: 3

  def execute(a2a_task_id)
    log_info("Starting external A2A task execution", a2a_task_id: a2a_task_id)

    # Fetch the A2A task from backend
    @task = fetch_a2a_task(a2a_task_id)
    return unless @task

    # Kill switch check — bail if AI activity is suspended for the account
    return if bail_if_ai_suspended!(@task['account_id'])

    # Validate this is an external task
    unless @task['is_external']
      log_error("Task is not marked as external", task_id: a2a_task_id)
      return
    end

    # Validate external endpoint
    unless @task['external_endpoint_url'].present?
      fail_task('No external endpoint URL configured', 'CONFIGURATION_ERROR')
      return
    end

    begin
      # Start the task
      update_task_status('active', started_at: Time.current.iso8601)

      # Execute the external A2A request
      result = execute_external_a2a_task

      if result[:success]
        complete_task(result)
        log_info("External A2A task completed successfully",
          a2a_task_id: a2a_task_id,
          duration_ms: result[:duration_ms]
        )
      else
        fail_task(result[:error], result[:error_code])
        log_error("External A2A task failed",
          a2a_task_id: a2a_task_id,
          error: result[:error]
        )
      end

    rescue StandardError => e
      fail_task(e.message, 'EXECUTION_ERROR')
      handle_ai_processing_error(e, { a2a_task_id: a2a_task_id })
    end
  end

  private

  def fetch_a2a_task(task_id)
    response = backend_api_get("/api/v1/ai/a2a/tasks/#{task_id}/details")

    if response['success']
      response['data']['task']
    else
      log_error("Failed to fetch A2A task", task_id: task_id)
      nil
    end
  end

  def update_task_status(status, additional_data = {})
    payload = {
      status: status,
      **additional_data
    }

    backend_api_patch("/api/v1/ai/a2a/tasks/#{@task['task_id']}", payload)
  end

  # Orchestration entry point: log the outbound call, then delegate the A2A
  # protocol/transport work (request building, auth headers, standard/streaming
  # HTTP, response/error parsing) to A2a::A2aClient. Returns the uniform result
  # hash consumed by #complete_task / #fail_task.
  def execute_external_a2a_task
    log_info("Calling external A2A endpoint",
      url: @task['external_endpoint_url'],
      task_id: @task['task_id']
    )

    a2a_client.execute(@task)
  end

  # `self` is the HTTP requester so standard requests reuse this job's
  # AiJobsConcern #make_http_request (circuit breaker + structured logging).
  def a2a_client
    @a2a_client ||= A2a::A2aClient.new(http_requester: self)
  end

  def complete_task(result)
    payload = {
      status: result[:status] || 'completed',
      output: result[:output],
      artifacts: result[:artifacts] || [],
      completed_at: result[:poll_required] ? nil : Time.current.iso8601,
      duration_ms: result[:duration_ms],
      metadata: (@task['metadata'] || {}).merge(
        'external_response' => result[:external_response]
      )
    }

    # If polling is required, schedule a follow-up job
    if result[:poll_required]
      payload[:metadata]['external_task_id'] = result[:external_task_id]
      schedule_poll_job(result[:external_task_id])
    end

    backend_api_patch("/api/v1/ai/a2a/tasks/#{@task['task_id']}", payload)
  end

  def fail_task(error_message, error_code = nil)
    payload = {
      status: 'failed',
      error_message: error_message,
      error_code: error_code || 'EXECUTION_ERROR',
      completed_at: Time.current.iso8601
    }

    backend_api_patch("/api/v1/ai/a2a/tasks/#{@task['task_id']}", payload)
  end

  def schedule_poll_job(external_task_id)
    log_info("Scheduling poll for external task",
      task_id: @task['task_id'],
      external_task_id: external_task_id
    )

    # Re-enqueue this job with a delay to poll the external task
    AiA2aExternalTaskJob.perform_in(
      15, # Poll after 15 seconds
      @task['id']
    )
  end
end
