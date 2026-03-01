# frozen_string_literal: true

# AiWorkflowEventDispatcherService - Core event dispatcher for AI workflow execution
#
# This service manages the event-driven execution of AI workflows, dispatching
# events to trigger workflow execution and coordinating between workflow nodes.
#
# Usage:
#   dispatcher = AiWorkflowEventDispatcherService.instance
#   dispatcher.dispatch_event('workflow.node.completed', { node_id: '...' })
#
class AiWorkflowEventDispatcherService
  include Singleton

  # Define available workflow events
  WORKFLOW_EVENTS = {
    # Workflow lifecycle events
    "workflow.created" => { description: "Workflow was created", category: :lifecycle },
    "workflow.updated" => { description: "Workflow was updated", category: :lifecycle },
    "workflow.deleted" => { description: "Workflow was deleted", category: :lifecycle },
    "workflow.activated" => { description: "Workflow was activated", category: :lifecycle },
    "workflow.deactivated" => { description: "Workflow was deactivated", category: :lifecycle },

    # Workflow execution events
    "workflow.execution.started" => { description: "Workflow execution started", category: :execution },
    "workflow.execution.completed" => { description: "Workflow execution completed", category: :execution },
    "workflow.execution.failed" => { description: "Workflow execution failed", category: :execution },
    "workflow.execution.cancelled" => { description: "Workflow execution cancelled", category: :execution },
    "workflow.execution.paused" => { description: "Workflow execution paused", category: :execution },
    "workflow.execution.resumed" => { description: "Workflow execution resumed", category: :execution },

    # Node execution events
    "workflow.node.started" => { description: "Node execution started", category: :node },
    "workflow.node.completed" => { description: "Node execution completed", category: :node },
    "workflow.node.failed" => { description: "Node execution failed", category: :node },
    "workflow.node.skipped" => { description: "Node execution skipped", category: :node },
    "workflow.node.retrying" => { description: "Node execution retrying", category: :node },

    # Trigger events
    "workflow.trigger.fired" => { description: "Workflow trigger fired", category: :trigger },
    "workflow.trigger.scheduled" => { description: "Workflow trigger scheduled", category: :trigger },

    # AI-specific events
    "workflow.ai.request" => { description: "AI provider request initiated", category: :ai },
    "workflow.ai.response" => { description: "AI provider response received", category: :ai },
    "workflow.ai.error" => { description: "AI provider error occurred", category: :ai },

    # System events
    "workflow.system.health_check" => { description: "System health check", category: :system },
    "workflow.system.error" => { description: "System error occurred", category: :system }
  }.freeze

  def initialize
    @running = false
    @event_queue = Queue.new
    @event_handlers = Hash.new { |h, k| h[k] = [] }
    @processor_thread = nil
    @mutex = Mutex.new
    @stats = {
      events_dispatched: 0,
      events_processed: 0,
      errors: 0,
      last_event_at: nil
    }

    register_default_handlers
  end

  # Start the event processor thread
  def start_event_processor
    @mutex.synchronize do
      return if @running

      @running = true
      @processor_thread = Thread.new { process_events }
      Rails.logger.info "[EventDispatcher] Event processor started"
    end
  end

  # Stop the event processor thread
  def stop_event_processor
    @mutex.synchronize do
      return unless @running

      @running = false
      @event_queue.push(nil) # Signal to stop
      @processor_thread&.join(5) # Wait up to 5 seconds
      @processor_thread = nil
      Rails.logger.info "[EventDispatcher] Event processor stopped"
    end
  end

  # Dispatch an event to be processed
  #
  # @param event_type [String] The type of event (e.g., 'workflow.node.completed')
  # @param data [Hash] Event data payload
  # @param metadata [Hash] Optional metadata (source, timestamp, etc.)
  # @return [String] Event ID
  def dispatch_event(event_type, data = {}, metadata = {})
    event = build_event(event_type, data, metadata)

    @mutex.synchronize do
      @stats[:events_dispatched] += 1
      @stats[:last_event_at] = Time.current
    end

    # For synchronous processing in development or when processor isn't running
    if !@running || Rails.env.test?
      process_event_sync(event)
    else
      @event_queue.push(event)
    end

    Rails.logger.debug "[EventDispatcher] Dispatched event: #{event_type} (#{event[:id]})"
    event[:id]
  end

  # Register an event handler
  #
  # @param event_type [String] Event type to handle (supports wildcards like 'workflow.*')
  # @param handler [Proc] Handler block to execute
  def register_handler(event_type, &handler)
    @mutex.synchronize do
      @event_handlers[event_type] << handler
    end
    Rails.logger.debug "[EventDispatcher] Registered handler for: #{event_type}"
  end

  # Remove an event handler
  #
  # @param event_type [String] Event type
  # @param handler [Proc] Handler to remove
  def unregister_handler(event_type, handler)
    @mutex.synchronize do
      @event_handlers[event_type].delete(handler)
    end
  end

  # Get health status
  #
  # @return [Hash] Health status information
  def health_status
    @mutex.synchronize do
      {
        running: @running,
        queue_size: @event_queue.size,
        handlers_count: @event_handlers.values.sum(&:size),
        stats: @stats.dup
      }
    end
  end

  # Get registered event types
  #
  # @return [Array<String>] List of event types with handlers
  def registered_event_types
    @mutex.synchronize do
      @event_handlers.keys
    end
  end

  private

  def build_event(event_type, data, metadata)
    {
      id: SecureRandom.uuid,
      type: event_type,
      data: data,
      metadata: metadata.merge(
        dispatched_at: Time.current.iso8601,
        dispatcher_version: "1.0.0"
      )
    }
  end

  def process_events
    while @running
      begin
        event = @event_queue.pop
        break if event.nil? # Stop signal

        process_event_sync(event)
      rescue StandardError => e
        Rails.logger.error "[EventDispatcher] Error processing event: #{e.message}"
        @mutex.synchronize { @stats[:errors] += 1 }
      end
    end
  end

  def process_event_sync(event)
    handlers = find_handlers(event[:type])

    handlers.each do |handler|
      begin
        handler.call(event)
      rescue StandardError => e
        Rails.logger.error "[EventDispatcher] Handler error for #{event[:type]}: #{e.message}"
        @mutex.synchronize { @stats[:errors] += 1 }
      end
    end

    @mutex.synchronize { @stats[:events_processed] += 1 }
  end

  def find_handlers(event_type)
    handlers = []

    @mutex.synchronize do
      # Exact match handlers
      handlers.concat(@event_handlers[event_type])

      # Wildcard handlers (e.g., 'workflow.*' matches 'workflow.node.completed')
      @event_handlers.each do |pattern, pattern_handlers|
        next unless pattern.include?("*")

        regex = Regexp.new("^" + pattern.gsub(".", "\\.").gsub("*", ".*") + "$")
        handlers.concat(pattern_handlers) if regex.match?(event_type)
      end
    end

    handlers
  end

  def register_default_handlers
    # Handler for workflow node completion - triggers next node execution
    register_handler("workflow.node.completed") do |event|
      handle_node_completed(event)
    end

    # Handler for workflow execution started
    register_handler("workflow.execution.started") do |event|
      handle_execution_started(event)
    end

    # Handler for AI responses
    register_handler("workflow.ai.response") do |event|
      handle_ai_response(event)
    end

    # Catch-all logging handler for debugging
    register_handler("workflow.*") do |event|
      Rails.logger.info "[EventDispatcher] Event: #{event[:type]} - #{event[:data].keys.join(', ')}"
    end
  end

  def handle_node_completed(event)
    data = event[:data]
    workflow_run_id = data[:workflow_run_id]
    node_id = data[:node_id]

    return unless workflow_run_id && node_id

    # Find the workflow run and continue execution
    workflow_run = Ai::WorkflowRun.find_by(id: workflow_run_id) ||
                   Ai::WorkflowRun.find_by(run_id: workflow_run_id)

    return unless workflow_run&.running?

    Rails.logger.info "[EventDispatcher] Node completed: #{node_id}, continuing workflow #{workflow_run.run_id}"

    # Trigger continuation of workflow execution
    continue_workflow_execution(workflow_run, node_id, data[:output])
  rescue StandardError => e
    Rails.logger.error "[EventDispatcher] Error handling node completion: #{e.message}"
  end

  def handle_execution_started(event)
    data = event[:data]
    workflow_run_id = data[:workflow_run_id]

    Rails.logger.info "[EventDispatcher] Workflow execution started: #{workflow_run_id}"
  end

  def handle_ai_response(event)
    data = event[:data]
    node_execution_id = data[:node_execution_id]

    return unless node_execution_id

    node_execution = Ai::WorkflowNodeExecution.find_by(id: node_execution_id) ||
                     Ai::WorkflowNodeExecution.find_by(execution_id: node_execution_id)

    return unless node_execution

    Rails.logger.info "[EventDispatcher] AI response received for node: #{node_execution.node_id}"

    # Update node execution with AI response
    if data[:success]
      node_execution.update!(
        status: "completed",
        output_data: data[:output] || {},
        completed_at: Time.current
      )

      # Dispatch node completed event
      dispatch_event("workflow.node.completed", {
        workflow_run_id: node_execution.workflow_run.id,
        node_id: node_execution.node_id,
        node_execution_id: node_execution.id,
        output: data[:output]
      })
    else
      node_execution.update!(
        status: "failed",
        error_details: { error_message: data[:error] || "AI execution failed" },
        completed_at: Time.current
      )

      dispatch_event("workflow.node.failed", {
        workflow_run_id: node_execution.workflow_run.id,
        node_id: node_execution.node_id,
        error: data[:error]
      })
    end
  rescue StandardError => e
    Rails.logger.error "[EventDispatcher] Error handling AI response: #{e.message}"
  end

  def continue_workflow_execution(workflow_run, completed_node_id, output)
    # Find the next nodes to execute
    workflow = workflow_run.workflow
    completed_node = workflow.workflow_nodes.find_by(node_id: completed_node_id)

    return unless completed_node

    # Get outgoing edges from completed node
    next_edges = workflow.workflow_edges.where(source_node_id: completed_node_id)

    if next_edges.empty?
      # No more nodes - check if workflow is complete
      check_workflow_completion(workflow_run)
      return
    end

    # Execute next nodes
    next_edges.each do |edge|
      next_node = workflow.workflow_nodes.find_by(node_id: edge.target_node_id)
      next unless next_node

      # Check if node is ready (all dependencies met)
      next unless node_dependencies_met?(workflow_run, next_node)

      # Queue node for execution
      queue_node_execution(workflow_run, next_node, output)
    end
  end

  def node_dependencies_met?(workflow_run, node)
    workflow = workflow_run.workflow

    # Get all incoming edges
    incoming_edges = workflow.workflow_edges.where(target_node_id: node.node_id)

    return true if incoming_edges.empty?

    # Check if all source nodes have completed
    incoming_edges.all? do |edge|
      execution = workflow_run.node_executions.find_by(node_id: edge.source_node_id)
      execution&.status == "completed"
    end
  end

  def queue_node_execution(workflow_run, node, input_data)
    # Check if node execution already exists
    existing = workflow_run.node_executions.find_by(node_id: node.node_id)
    return if existing && !existing.pending?

    # Create or update node execution
    node_execution = existing || workflow_run.create_node_execution(node, input_data || {})

    Rails.logger.info "[EventDispatcher] Queuing node execution: #{node.name} (#{node.node_type})"

    # Execute based on node type
    case node.node_type
    when "start"
      execute_start_node(node_execution)
    when "end"
      execute_end_node(node_execution, input_data)
    when "ai_agent"
      execute_ai_agent_node(node_execution, input_data)
    when "condition"
      execute_condition_node(node_execution, input_data)
    when "data_processor"
      execute_data_processor_node(node_execution, input_data)
    else
      execute_generic_node(node_execution, input_data)
    end
  end

  def execute_start_node(node_execution)
    node_execution.update!(status: "running", started_at: Time.current)

    # Start node just passes through
    node_execution.update!(
      status: "completed",
      output_data: node_execution.input_data,
      completed_at: Time.current
    )

    dispatch_event("workflow.node.completed", {
      workflow_run_id: node_execution.workflow_run.id,
      node_id: node_execution.node_id,
      node_execution_id: node_execution.id,
      output: node_execution.output_data
    })
  end

  def execute_end_node(node_execution, input_data)
    node_execution.update!(status: "running", started_at: Time.current)

    # End node finalizes the workflow
    node_execution.update!(
      status: "completed",
      output_data: input_data || {},
      completed_at: Time.current
    )

    # Mark workflow as completed
    check_workflow_completion(node_execution.workflow_run)
  end

  def execute_ai_agent_node(node_execution, input_data)
    node_execution.update!(status: "running", started_at: Time.current)

    # Queue AI execution through the worker
    begin
      WorkerJobService.new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiNodeExecutionJob",
        "args" => [node_execution.id, input_data],
        "queue" => "ai_execution"
      })

      Rails.logger.info "[EventDispatcher] Queued AI agent execution: #{node_execution.node_id}"
    rescue StandardError => e
      Rails.logger.error "[EventDispatcher] Failed to queue AI execution: #{e.message}"

      # Execute synchronously as fallback
      execute_ai_agent_sync(node_execution, input_data)
    end
  end

  def execute_ai_agent_sync(node_execution, input_data)
    workflow_node = node_execution.workflow_node
    config = workflow_node.configuration || {}

    # Get agent_id from configuration
    agent_id = config["agent_id"] || config["ai_agent_id"]

    unless agent_id
      # Fallback to simple text generation if no agent configured
      return execute_simple_ai_call(node_execution, input_data)
    end

    # Find the AI agent
    agent = Ai::Agent.find_by(id: agent_id)
    unless agent
      node_execution.update!(
        status: "failed",
        error_details: { error_message: "AI Agent not found: #{agent_id}" },
        completed_at: Time.current
      )
      return
    end

    begin
      workflow_run = node_execution.workflow_run
      account = workflow_run.account

      # Create agent execution record
      agent_execution = Ai::AgentExecution.create!(
        agent: agent,
        account: account,
        user: workflow_run.user,
        provider: agent.provider,
        execution_id: SecureRandom.uuid,
        status: "pending",
        input_parameters: input_data,
        tokens_used: 0,
        cost_usd: 0.0,
        webhook_attempts: 0
      )

      # Link to node execution
      node_execution.update_column(:ai_agent_execution_id, agent_execution.id)

      # Start execution tracking
      agent_execution.start_execution!

      # Execute via MCP agent executor
      mcp_executor = Ai::McpAgentExecutor.new(
        agent: agent,
        execution: agent_execution,
        account: account
      )

      # Prepare input
      agent_input = prepare_agent_input(workflow_node, input_data)

      # Execute
      execution_result = mcp_executor.execute(agent_input)

      # Process result
      if execution_result["error"] || execution_result[:error]
        error_info = execution_result["error"] || execution_result[:error]
        error_message = error_info["message"] || error_info[:message] || "MCP execution error"

        agent_execution.fail_execution!(error_message, { "mcp_error" => error_info })

        node_execution.update!(
          status: "failed",
          error_details: { error_message: error_message },
          completed_at: Time.current
        )
      elsif execution_result["result"]
        result_data = execution_result["result"]
        output_data = result_data["output"] || result_data[:output]

        agent_execution.complete_execution!(
          { "output" => output_data },
          {
            "tokens_used" => result_data.dig("metadata", "tokens_used"),
            "processing_time_ms" => result_data.dig("metadata", "processing_time_ms"),
            "model_used" => result_data.dig("metadata", "model_used")
          }
        )

        node_execution.update!(
          status: "completed",
          output_data: { output: output_data, agent_name: agent.name },
          completed_at: Time.current
        )

        dispatch_event("workflow.node.completed", {
          workflow_run_id: node_execution.workflow_run.id,
          node_id: node_execution.node_id,
          node_execution_id: node_execution.id,
          output: node_execution.output_data
        })
      else
        agent_execution.fail_execution!("Unexpected response format", {})
        node_execution.update!(
          status: "failed",
          error_details: { error_message: "Unexpected MCP response format" },
          completed_at: Time.current
        )
      end
    rescue StandardError => e
      Rails.logger.error "[EventDispatcher] AI agent execution error: #{e.message}"
      node_execution.update!(
        status: "failed",
        error_details: { error_message: e.message },
        completed_at: Time.current
      )
    end
  end

  def execute_simple_ai_call(node_execution, input_data)
    workflow_node = node_execution.workflow_node
    config = workflow_node.configuration || {}

    # Get AI provider
    provider = Ai::Provider.find_by(id: config["provider_id"]) ||
               Ai::Provider.where(is_active: true).first

    unless provider
      node_execution.update!(
        status: "failed",
        error_details: { error_message: "No AI provider configured" },
        completed_at: Time.current
      )
      return
    end

    # Get credential
    credential = provider.provider_credentials.find_by(is_active: true)
    unless credential
      node_execution.update!(
        status: "failed",
        error_details: { error_message: "No active credentials for provider" },
        completed_at: Time.current
      )
      return
    end

    # Build prompt from node configuration
    prompt = build_ai_prompt(workflow_node, input_data)

    # Make AI call
    client = WorkerLlmClient.new(provider: provider, credential: credential)
    messages = [{ role: "user", content: prompt }]
    model = provider.default_model || provider.supported_models.first&.dig("id")
    response = client.complete(messages: messages, model: model)

    if response.success?
      node_execution.update!(
        status: "completed",
        output_data: { output: response.content, provider: provider.name },
        completed_at: Time.current
      )

      dispatch_event("workflow.node.completed", {
        workflow_run_id: node_execution.workflow_run.id,
        node_id: node_execution.node_id,
        node_execution_id: node_execution.id,
        output: node_execution.output_data
      })
    else
      node_execution.update!(
        status: "failed",
        error_details: { error_message: response.raw_response&.dig(:error) || "AI call failed" },
        completed_at: Time.current
      )
    end
  rescue StandardError => e
    Rails.logger.error "[EventDispatcher] Simple AI execution error: #{e.message}"
    node_execution.update!(
      status: "failed",
      error_details: { error_message: e.message },
      completed_at: Time.current
    )
  end

  def prepare_agent_input(workflow_node, input_data)
    config = workflow_node.configuration || {}
    prompt_template = config["prompt_template"] || config["prompt"]

    if prompt_template.present?
      rendered_prompt = render_template(prompt_template, input_data || {})
      { "input" => rendered_prompt, "context" => config["context"] || {} }
    else
      { "input" => (input_data || {}).to_json, "context" => config["context"] || {} }
    end
  end

  def render_template(template, variables)
    result = template.dup
    (variables || {}).each do |key, value|
      result.gsub!(/\{\{#{key}\}\}/, value.to_s)
      result.gsub!("{#{key}}", value.to_s)
    end
    result
  end

  def build_ai_prompt(workflow_node, input_data)
    config = workflow_node.configuration || {}
    template = config["prompt_template"] || config["system_prompt"] || "Process the following input:"

    # Substitute variables in template
    prompt = template.dup
    (input_data || {}).each do |key, value|
      prompt.gsub!("{{#{key}}}", value.to_s)
      prompt.gsub!("{#{key}}", value.to_s)
    end

    # Append input data if not already in template
    if input_data.present? && !template.include?("{{") && !template.include?("{")
      prompt += "\n\nInput: #{input_data.to_json}"
    end

    prompt
  end

  def execute_condition_node(node_execution, input_data)
    node_execution.update!(status: "running", started_at: Time.current)

    # Evaluate condition
    workflow_node = node_execution.workflow_node
    config = workflow_node.configuration || {}
    condition = config["condition"] || "true"

    result = evaluate_condition(condition, input_data)

    node_execution.update!(
      status: "completed",
      output_data: { result: result, branch: result ? "true" : "false" },
      completed_at: Time.current
    )

    dispatch_event("workflow.node.completed", {
      workflow_run_id: node_execution.workflow_run.id,
      node_id: node_execution.node_id,
      node_execution_id: node_execution.id,
      output: node_execution.output_data,
      condition_result: result
    })
  end

  def evaluate_condition(_condition, _input_data)
    # Simple condition evaluation - can be expanded
    true
  end

  def execute_data_processor_node(node_execution, input_data)
    node_execution.update!(status: "running", started_at: Time.current)

    # Process data transformation
    workflow_node = node_execution.workflow_node
    config = workflow_node.configuration || {}

    output = case config["processor_type"]
    when "transform"
               transform_data(input_data, config)
    when "filter"
               filter_data(input_data, config)
    when "aggregate"
               aggregate_data(input_data, config)
    else
               input_data
    end

    node_execution.update!(
      status: "completed",
      output_data: output,
      completed_at: Time.current
    )

    dispatch_event("workflow.node.completed", {
      workflow_run_id: node_execution.workflow_run.id,
      node_id: node_execution.node_id,
      node_execution_id: node_execution.id,
      output: output
    })
  end

  def transform_data(input_data, _config)
    input_data
  end

  def filter_data(input_data, _config)
    input_data
  end

  def aggregate_data(input_data, _config)
    input_data
  end

  def execute_generic_node(node_execution, input_data)
    node_execution.update!(status: "running", started_at: Time.current)

    # Generic pass-through
    node_execution.update!(
      status: "completed",
      output_data: input_data || {},
      completed_at: Time.current
    )

    dispatch_event("workflow.node.completed", {
      workflow_run_id: node_execution.workflow_run.id,
      node_id: node_execution.node_id,
      node_execution_id: node_execution.id,
      output: node_execution.output_data
    })
  end

  def check_workflow_completion(workflow_run)
    workflow_run.reload

    # Check if all nodes have been executed
    total_nodes = workflow_run.workflow.workflow_nodes.count
    completed_nodes = workflow_run.node_executions.where(status: "completed").count
    failed_nodes = workflow_run.node_executions.where(status: "failed").count

    workflow_run.update!(
      completed_nodes: completed_nodes,
      failed_nodes: failed_nodes
    )

    # Check if workflow is complete
    if completed_nodes + failed_nodes >= total_nodes
      final_status = failed_nodes > 0 ? "failed" : "completed"

      # Ensure completed_at is after started_at
      completion_time = Time.current
      if workflow_run.started_at.present? && completion_time <= workflow_run.started_at
        completion_time = workflow_run.started_at + 0.001.seconds
      end

      workflow_run.update!(
        status: final_status,
        completed_at: completion_time
      )

      dispatch_event("workflow.execution.#{final_status}", {
        workflow_run_id: workflow_run.id,
        run_id: workflow_run.run_id,
        completed_nodes: completed_nodes,
        failed_nodes: failed_nodes
      })

      Rails.logger.info "[EventDispatcher] Workflow #{workflow_run.run_id} #{final_status}"
    end
  end
end
