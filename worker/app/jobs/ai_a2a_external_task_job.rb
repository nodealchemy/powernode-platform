# frozen_string_literal: true

class AiA2aExternalTaskJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_agents', retry: 3

  # A2A Protocol constants
  A2A_CONTENT_TYPE = 'application/json'
  A2A_VERSION = '0.3'
  DEFAULT_TIMEOUT = 120

  def execute(a2a_task_id)
    log_info("Starting external A2A task execution", a2a_task_id: a2a_task_id)

    # Fetch the A2A task from backend
    @task = fetch_a2a_task(a2a_task_id)
    return unless @task

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

  def execute_external_a2a_task
    start_time = Time.current

    endpoint_url = @task['external_endpoint_url']
    authentication = @task['external_authentication'] || {}

    # Build A2A-compliant request
    request_body = build_a2a_request

    log_info("Calling external A2A endpoint",
      url: endpoint_url,
      task_id: @task['task_id']
    )

    # Build headers
    headers = build_a2a_headers(authentication)

    # Determine if we should use streaming
    use_streaming = @task.dig('metadata', 'streaming') == true

    if use_streaming
      execute_streaming_request(endpoint_url, headers, request_body, start_time)
    else
      execute_standard_request(endpoint_url, headers, request_body, start_time)
    end
  end

  def build_a2a_request
    message = @task['message'] || {}

    # A2A tasks/send request format
    {
      id: @task['task_id'],
      message: message,
      sessionId: @task['ai_workflow_run_id'],
      historyLength: (@task['history'] || []).size,
      acceptedOutputModes: ['application/json', 'text/plain'],
      metadata: @task['metadata'] || {}
    }
  end

  def build_a2a_headers(authentication)
    headers = {
      'Content-Type' => A2A_CONTENT_TYPE,
      'Accept' => A2A_CONTENT_TYPE,
      'X-A2A-Version' => A2A_VERSION
    }

    # Add authentication
    case authentication['type']
    when 'bearer'
      headers['Authorization'] = "Bearer #{authentication['token']}"
    when 'api_key'
      header_name = authentication['header_name'] || 'X-API-Key'
      headers[header_name] = authentication['key']
    when 'basic'
      credentials = Base64.strict_encode64("#{authentication['username']}:#{authentication['password']}")
      headers['Authorization'] = "Basic #{credentials}"
    end

    headers
  end

  def execute_standard_request(endpoint_url, headers, request_body, start_time)
    timeout = @task.dig('metadata', 'timeout') || DEFAULT_TIMEOUT

    begin
      response = make_http_request(
        endpoint_url,
        method: :post,
        headers: headers,
        body: request_body.to_json,
        timeout: timeout
      )

      duration_ms = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i >= 200 && response.code.to_i < 300
        parse_a2a_response(response.body, duration_ms)
      else
        parse_a2a_error(response.body, response.code, duration_ms)
      end

    rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
      {
        success: false,
        error: "External A2A endpoint timeout: #{e.message}",
        error_code: 'TIMEOUT',
        duration_ms: ((Time.current - start_time) * 1000).to_i
      }
    rescue StandardError => e
      {
        success: false,
        error: "External A2A connection failed: #{e.message}",
        error_code: 'CONNECTION_ERROR',
        duration_ms: ((Time.current - start_time) * 1000).to_i
      }
    end
  end

  def execute_streaming_request(endpoint_url, headers, request_body, start_time)
    # For streaming, we use SSE and accumulate results
    # This is a simplified implementation - full SSE would require async handling
    execute_standard_request(endpoint_url, headers, request_body, start_time)
  end

  def parse_a2a_response(body, duration_ms)
    data = JSON.parse(body)

    # A2A response format
    status = data['status'] || {}
    state = status['state'] || 'completed'

    case state
    when 'completed'
      {
        success: true,
        output: extract_output_from_response(data),
        artifacts: data['artifacts'] || [],
        duration_ms: duration_ms,
        external_response: data
      }
    when 'failed'
      error = data['error'] || {}
      {
        success: false,
        error: error['message'] || 'External agent failed',
        error_code: error['code'] || 'EXTERNAL_FAILURE',
        duration_ms: duration_ms
      }
    when 'input-required'
      # Task needs input - update our task status
      {
        success: true,
        status: 'input_required',
        output: {
          'input_request' => data['message'],
          'prompt' => extract_text_from_message(data['message'])
        },
        duration_ms: duration_ms
      }
    when 'working', 'submitted'
      # Task is still in progress - need to poll
      {
        success: true,
        status: 'active',
        external_task_id: data['id'],
        duration_ms: duration_ms,
        poll_required: true
      }
    else
      {
        success: false,
        error: "Unknown A2A state: #{state}",
        error_code: 'UNKNOWN_STATE',
        duration_ms: duration_ms
      }
    end
  rescue JSON::ParserError => e
    {
      success: false,
      error: "Invalid JSON response from external agent: #{e.message}",
      error_code: 'INVALID_RESPONSE',
      duration_ms: duration_ms
    }
  end

  def parse_a2a_error(body, status_code, duration_ms)
    begin
      data = JSON.parse(body)
      error = data['error'] || data

      {
        success: false,
        error: error['message'] || "HTTP #{status_code}",
        error_code: error['code'] || "HTTP_#{status_code}",
        duration_ms: duration_ms
      }
    rescue JSON::ParserError
      {
        success: false,
        error: "HTTP #{status_code}: #{body.truncate(200)}",
        error_code: "HTTP_#{status_code}",
        duration_ms: duration_ms
      }
    end
  end

  def extract_output_from_response(data)
    message = data['message'] || {}

    {
      'content' => extract_text_from_message(message),
      'message' => message,
      'status' => data['status']
    }
  end

  def extract_text_from_message(message)
    return '' unless message.is_a?(Hash)

    parts = message['parts'] || []
    parts.select { |p| p['type'] == 'text' }
         .map { |p| p['text'] }
         .join("\n")
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
    # Schedule a polling job to check on the external task status
    # This would be a separate job that polls the external endpoint
    log_info("External task requires polling",
      task_id: @task['task_id'],
      external_task_id: external_task_id
    )

    # AiA2aExternalTaskPollJob.perform_in(10.seconds, @task['id'], external_task_id)
  end
end
