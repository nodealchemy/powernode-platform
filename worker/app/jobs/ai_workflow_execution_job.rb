# frozen_string_literal: true

class AiWorkflowExecutionJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_workflows', retry: 3

  def execute(workflow_run_id, options = {})
    @workflow_run_id = workflow_run_id
    @options = options
    @realtime = options['realtime'] || false
    @channel_id = options['channel_id']

    log_info("Starting workflow execution job for run ID: #{workflow_run_id}")

    # Safeguard: Check for potential runaway loops
    if detect_runaway_loop(workflow_run_id, options)
      log_error("Runaway loop detected for workflow run #{workflow_run_id}, aborting execution")
      return
    end

    # Get workflow run details (this also sets @workflow_id)
    workflow_run = fetch_workflow_run
    return unless workflow_run

    begin
      # Broadcast execution started if real-time
      broadcast_execution_status('started') if @realtime

      # Execute the workflow
      result = execute_workflow(workflow_run)

      if result['success']
        # Update workflow run status
        update_workflow_status('completed', {
          'completed_at' => Time.current.iso8601,
          'output_variables' => result['output_variables'] || {}
        })

        # Broadcast completion
        broadcast_execution_status('completed', {
          'output_variables' => result['output_variables'],
          'duration_ms' => result['duration_ms'],
          'total_cost' => result['total_cost']
        })

        log_info("Workflow execution completed successfully: #{workflow_run_id}")
      else
        # Handle execution failure
        handle_execution_failure(result['error_message'], result['error_details'] || {})
      end

    rescue StandardError => e
      handle_execution_error(e)
    end
  end

  private

  # Detect potential runaway loops by checking execution patterns
  def detect_runaway_loop(workflow_run_id, options)
    # Check recursion depth
    recursion_depth = options.dig('recursion_depth') || 0
    if recursion_depth > 10  # Higher threshold for worker jobs
      log_error("Excessive recursion depth detected: #{recursion_depth}")
      return true
    end

    # Check for rapid job creation pattern (multiple jobs for same workflow in short time)
    # Use Sidekiq's built-in Redis connection instead of creating direct Redis connections
    begin
      job_key = "workflow_job_count:#{workflow_run_id}"
      current_count = Sidekiq.redis { |conn| conn.incr(job_key) }
      Sidekiq.redis { |conn| conn.expire(job_key, 60) } # 1 minute window

      if current_count > 5  # More than 5 jobs for same workflow in 1 minute
        log_error("Rapid job creation detected for workflow #{workflow_run_id}: #{current_count} jobs in 1 minute")
        return true
      end
    rescue StandardError => redis_error
      log_warn("Redis unavailable for loop detection: #{redis_error.message}")
    end

    false
  rescue StandardError => e
    # If loop detection fails, err on the side of caution but continue
    log_warn("Loop detection failed: #{e.message}")
    false
  end

  def fetch_workflow_run
    # First, get the workflow run to extract the workflow_id
    # We need to query by run_id to find the workflow_id
    # The backend should provide an endpoint that accepts run_id and returns the full path

    # For now, we'll need to fetch from a standalone endpoint that finds by run_id
    # This is a temporary solution until we implement a proper lookup endpoint
    response = backend_api_get("/api/v1/ai/workflows/runs/lookup/#{@workflow_run_id}")

    if response['success']
      workflow_run = response['data']['workflow_run']
      @workflow_id = workflow_run['workflow_id'] || workflow_run['ai_workflow_id']
      @workflow_run_data = workflow_run  # Store for later reference
      log_info("Fetched workflow run #{@workflow_run_id} for workflow #{@workflow_id}")
      workflow_run
    else
      log_error("Failed to fetch workflow run #{@workflow_run_id}: #{response['error']}")
      nil
    end
  end

  def execute_workflow(workflow_run)
    # Call the backend processing service (does NOT create new jobs)
    # Use dedicated workflow execution circuit breaker with higher timeout
    response = execute_workflow_request

    if response['success']
      {
        'success' => true,
        'output_variables' => response['data']['output_variables'],
        'duration_ms' => response['data']['duration_ms'],
        'total_cost' => response['data']['total_cost']
      }
    else
      {
        'success' => false,
        'error_message' => response['error'] || 'Workflow execution failed',
        'error_details' => response['data'] || {}
      }
    end
  end

  private

  def execute_workflow_request
    # Use dedicated workflow execution circuit breaker with direct HTTP call to avoid nested timeouts
    with_workflow_execution_circuit_breaker do
      path = "/api/v1/ai/workflows/#{@workflow_id}/runs/#{@workflow_run_id}/process"
      log_api_request('POST', path, @options)
      start_time = Time.current

      begin
        # Make direct HTTP request bypassing BackendApiClient's circuit breaker
        result = make_direct_backend_request('POST', path, {
          execution_options: @options
        })
        duration = Time.current - start_time

        log_api_success('POST', path, duration, result)
        result
      rescue StandardError => e
        duration = Time.current - start_time
        log_api_error('POST', path, duration, e)
        raise
      end
    end
  end

  def make_direct_backend_request(method, path, data = {})
    # Direct HTTP request without BackendApiClient's circuit breaker
    require 'net/http'
    require 'json'

    config = PowernodeWorker.application.config
    uri = URI("#{config.backend_api_url}#{path}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 600  # 10 minutes for workflow execution (matches circuit breaker)
    http.open_timeout = 30   # 30 seconds to establish connection

    request = case method.upcase
    when 'POST'
      Net::HTTP::Post.new(uri)
    when 'PATCH'
      Net::HTTP::Patch.new(uri)
    when 'GET'
      Net::HTTP::Get.new(uri)
    else
      raise ArgumentError, "Unsupported HTTP method: #{method}"
    end

    request['Authorization'] = "Bearer #{WorkerJwt.token}"
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request['User-Agent'] = 'PowernodeWorker/1.0'

    unless %w[GET DELETE].include?(method.upcase)
      request.body = data.to_json
    end

    response = http.request(request)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    log_error("Failed to parse JSON response: #{e.message}")
    { 'success' => false, 'error' => 'Invalid JSON response from backend' }
  rescue StandardError => e
    log_error("Direct backend request failed: #{e.message}")
    { 'success' => false, 'error' => "Backend request failed: #{e.message}" }
  end


  def update_workflow_status(status, additional_data = {})
    payload = {
      workflow_run: {
        status: status
      }.merge(additional_data)
    }

    path = "/api/v1/ai/workflows/#{@workflow_id}/runs/#{@workflow_run_id}"
    response = backend_api_patch(path, payload)

    unless response['success']
      log_error("Failed to update workflow run status: #{response['error']}")
    end
  end

  def handle_execution_failure(error_message, error_details)
    log_error("Workflow execution failed: #{error_message}")

    # Prepare failure update with proper timestamps
    failure_data = build_failure_update(error_message, error_details)

    # Update workflow run status
    update_workflow_status('failed', failure_data)

    # Broadcast failure
    broadcast_execution_status('failed', {
      'error_message' => error_message,
      'error_details' => error_details
    })
  end

  def handle_execution_error(error)
    log_error("Workflow execution job error: #{error.message}")
    log_error(error.backtrace.join("\n"))

    # Prepare error update with proper timestamps
    error_data = build_failure_update(error.message, {
      'exception_class' => error.class.name,
      'backtrace' => error.backtrace&.first(10)
    })

    # Update workflow run status
    update_workflow_status('failed', error_data)

    # Broadcast error
    broadcast_execution_status('error', {
      'error_message' => error.message,
      'exception_class' => error.class.name
    })

    # Re-raise for retry mechanism
    raise error
  end

  def build_failure_update(error_message, error_details = {})
    # Ensure proper timestamp ordering for failed workflow runs
    current_time = Time.current

    # Check if workflow run has started_at already
    started_at_value = @workflow_run_data&.dig('started_at')

    # Build failure update with proper timestamps
    update_data = {
      'error_details' => {
        'error_message' => error_message
      }.merge(error_details)
    }

    # If started_at is not set, set it to slightly before completed_at to satisfy validation
    if started_at_value.nil?
      # Set started_at to 1 second before current time, completed_at to current time
      update_data['started_at'] = (current_time - 1.second).iso8601
      update_data['completed_at'] = current_time.iso8601
      log_warn("Workflow run #{@workflow_run_id} never started - setting started_at retroactively")
    else
      # started_at exists, just set completed_at
      update_data['completed_at'] = current_time.iso8601
    end

    update_data
  end

  def broadcast_execution_status(status, additional_data = {})
    return unless @realtime

    broadcast_data = {
      type: 'workflow_execution_status',
      workflow_run_id: @workflow_run_id,
      status: status,
      timestamp: Time.current.iso8601
    }.merge(additional_data)

    # Broadcast via backend API - don't fail execution if broadcast fails
    path = "/api/v1/ai/workflows/#{@workflow_id}/runs/#{@workflow_run_id}/broadcast"
    backend_api_post(path, {
      broadcast: broadcast_data,
      channel_id: @channel_id
    })
  rescue StandardError => e
    log_warn("Failed to broadcast execution status: #{e.message}")
    # Don't re-raise - broadcast failures shouldn't stop execution
  end
end