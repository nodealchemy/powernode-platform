# frozen_string_literal: true

class AiWorkflowNodeExecutionJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_workflow_nodes', retry: 5

  def execute(node_execution_id, options = {})
    @node_execution_id = node_execution_id
    @options = options
    @execution_context = options['execution_context'] || {}

    log_info("Starting node execution job for ID: #{node_execution_id}")

    # Get node execution details
    node_execution = fetch_node_execution
    return unless node_execution

    begin
      # Execute the node
      result = execute_node(node_execution)

      if result['success']
        # Update node execution with results
        update_node_execution('completed', {
          'output_data' => result['output_data'] || {},
          'cost' => result['cost'] || 0,
          'completed_at' => Time.current.iso8601,
          'duration_ms' => result['execution_time_ms'] || 0
        })

        # Trigger next nodes if applicable
        trigger_next_nodes(node_execution, result)

        log_info("Node execution completed successfully: #{node_execution_id}")
      else
        # Handle execution failure
        handle_node_failure(node_execution, result)
      end

    rescue StandardError => e
      handle_node_error(node_execution, e)
    end
  end

  private

  def fetch_node_execution
    response = backend_api_get("/api/v1/ai/workflow-node-executions/#{@node_execution_id}")
    
    if response['success']
      response['data']['node_execution']
    else
      log_error("Failed to fetch node execution #{@node_execution_id}: #{response['error']}")
      nil
    end
  end

  def execute_node(node_execution)
    # Call the backend node execution service
    response = backend_api_post("/api/v1/ai/workflow-node-executions/#{@node_execution_id}/execute", {
      execution_options: @options,
      execution_context: @execution_context
    })

    if response['success']
      # Merge success flag so the caller can check result['success']
      response['data'].merge('success' => true)
    else
      {
        'success' => false,
        'error_message' => response['error'] || 'Node execution failed',
        'error_details' => response['data'] || {}
      }
    end
  end

  def update_node_execution(status, additional_data = {})
    payload = {
      node_execution: {
        status: status
      }.merge(additional_data)
    }

    response = backend_api_patch("/api/v1/ai/workflow-node-executions/#{@node_execution_id}", payload)
    
    unless response['success']
      log_error("Failed to update node execution status: #{response['error']}")
    end
  end

  def trigger_next_nodes(node_execution, execution_result)
    # Get next nodes to execute
    response = backend_api_get("/api/v1/ai/workflow-node-executions/#{@node_execution_id}/next-nodes")
    
    return unless response['success']
    
    next_nodes = response['data']['next_nodes'] || []
    
    # Queue execution for each next node
    next_nodes.each do |next_node_data|
      AiWorkflowNodeExecutionJob.perform_later(
        next_node_data['id'],
        @options.merge({
          'triggered_by_node' => @node_execution_id,
          'parent_result' => execution_result
        })
      )
    end
    
    log_info("Triggered #{next_nodes.size} next nodes for execution")
  end

  def handle_node_failure(node_execution, result)
    error_message = result['error_message'] || 'Node execution failed'
    error_details = result['error_details'] || {}

    log_error("Node execution failed: #{error_message}")

    # Check if node should be retried
    if should_retry_node?(node_execution, result)
      schedule_node_retry(node_execution, error_message)
    else
      # Mark as permanently failed
      update_node_execution('failed', {
        'completed_at' => Time.current.iso8601,
        'error_details' => {
          'error_message' => error_message,
          'error_details' => error_details,
          'retries_exhausted' => true
        }
      })

      # Handle workflow failure if error handling is set to 'stop'
      handle_workflow_error_propagation(node_execution, error_message)
    end
  end

  def handle_node_error(node_execution, error)
    log_error("Node execution job error: #{error.message}")
    log_error(error.backtrace.join("\n"))

    # Update node execution status
    update_node_execution('failed', {
      'completed_at' => Time.current.iso8601,
      'error_details' => {
        'error_message' => error.message,
        'exception_class' => error.class.name,
        'backtrace' => error.backtrace&.first(10)
      }
    })

    # Handle workflow error propagation
    handle_workflow_error_propagation(node_execution, error.message)

    # Re-raise for retry mechanism
    raise error
  end

  def should_retry_node?(node_execution, result)
    # Check retry configuration
    current_retries = node_execution['retry_count'] || 0
    max_retries = node_execution['max_retries'] || 0
    
    return false if current_retries >= max_retries

    # Check if error is retryable
    error_details = result['error_details'] || {}
    retryable = error_details['retryable']
    
    # Default to retryable for certain error types
    if retryable.nil?
      error_message = result['error_message'] || ''
      retryable = error_message.include?('timeout') || 
                  error_message.include?('connection') ||
                  error_message.include?('network')
    end

    retryable
  end

  def schedule_node_retry(node_execution, error_message)
    current_retries = node_execution['retry_count'] || 0
    retry_delay = calculate_retry_delay(current_retries)
    
    log_info("Scheduling node retry in #{retry_delay} seconds (attempt #{current_retries + 1})")

    # Update retry count
    backend_api_patch("/api/v1/ai/workflow-node-executions/#{@node_execution_id}", {
      node_execution: {
        retry_count: current_retries + 1,
        status: 'pending'
      }
    })

    # Schedule retry job
    AiWorkflowNodeExecutionJob.perform_in(
      retry_delay.seconds,
      @node_execution_id,
      @options.merge({
        'retry_attempt' => current_retries + 1,
        'previous_error' => error_message
      })
    )
  end

  def calculate_retry_delay(attempt_count)
    # Exponential backoff with jitter
    base_delay = 2 ** attempt_count
    jitter = rand(0.5..1.5)
    [base_delay * jitter, 300].min # Max 5 minutes
  end

  def handle_workflow_error_propagation(node_execution, error_message)
    workflow_run_id = node_execution['ai_workflow_run_id']
    return unless workflow_run_id

    # Check workflow error handling configuration
    response = backend_api_get("/api/v1/ai/workflow-runs/#{workflow_run_id}")
    return unless response['success']

    workflow_data = response['data']['workflow_run']
    error_handling = workflow_data.dig('ai_workflow', 'configuration', 'error_handling') || 'stop'

    case error_handling
    when 'stop'
      # Stop the entire workflow
      backend_api_post("/api/v1/ai/workflow-runs/#{workflow_run_id}/cancel", {
        reason: "Node execution failed: #{error_message}",
        failed_node_id: node_execution['node_id']
      })
    when 'continue'
      # Continue with other nodes (default behavior)
      log_info("Continuing workflow execution despite node failure")
    when 'retry_workflow'
      # Retry the entire workflow
      backend_api_post("/api/v1/ai/workflow-runs/#{workflow_run_id}/retry", {
        reason: "Node execution failed, retrying workflow"
      })
    end
  end
end