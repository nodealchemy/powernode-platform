# frozen_string_literal: true

# AiAgentOrchestrationService - Main facade for AI workflow orchestration
#
# This service acts as the primary public API for AI workflow and agent orchestration,
# delegating actual execution to the MCP (Model Context Protocol) core services while
# providing a stable, high-level interface.
#
# Key responsibilities:
# - Public API facade for workflow execution
# - Agent execution coordination with load balancing
# - Provider selection and optimization
# - Resource limit enforcement
# - Workflow validation and orchestration
# - Real-time execution monitoring and broadcasting
# - Performance metrics and analytics
#
# Architecture:
# - Facade pattern: Delegates to Mcp::AiWorkflowOrchestrator for execution
# - Load balancing: AiProviderLoadBalancerService for optimal provider selection
# - Error recovery: AiErrorRecoveryService for resilience
# - Monitoring: UnifiedMonitoringService for system telemetry
# - Multi-provider support: Works with OpenAI, Anthropic, Ollama, custom providers
#
# Service Layer Pattern:
# - This is a ROOT FACADE service (public API)
# - Delegates to MCP CORE services (implementation):
#   * Mcp::AiWorkflowOrchestrator - Actual workflow execution
#   * Mcp::WorkflowCheckpointManager - Checkpoint recovery
#   * McpProtocolService - MCP protocol handling
#
# Execution Modes:
# - Sequential: Execute agents one after another
# - Parallel: Execute multiple agents concurrently
# - Conditional: Branch based on conditions
# - MCP-based: Full MCP protocol workflow execution
#
# @example Execute workflow via MCP
#   service = AiAgentOrchestrationService.new(workflow, account: account, user: user)
#   run = service.execute_workflow(input_variables: { key: 'value' })
#
# @example Execute single agent with optimization
#   service = AiAgentOrchestrationService.new(account: account, user: user)
#   execution = service.execute_agent_with_orchestration(
#     agent,
#     input_parameters,
#     optimize_for_cost: true
#   )
#
# @example Monitor active executions
#   results = service.monitor_executions
#   # => { total_active: 5, by_status: {...}, performance_metrics: {...} }
#
class AiAgentOrchestrationService
  include ActiveModel::Model
  include ActiveModel::Attributes
  include AiNodeExecutors
  include AiOrchestrationBroadcasting

  class OrchestrationError < StandardError; end
  class ExecutionError < StandardError; end
  class ResourceLimitError < StandardError; end

  attr_accessor :account, :user, :workflow

  def initialize(workflow = nil, account: nil, user: nil)
    if workflow
      @workflow = workflow
      @account = workflow.account
      @user = user || workflow.creator
    else
      @account = account
      @user = user
    end
    @logger = Rails.logger
    @execution_context = build_execution_context
    @node_executors = build_node_executors_registry

    # Initialize enhanced services with error handling
    begin
      @load_balancer = AiProviderLoadBalancerService.new(@account, strategy: "cost_optimized") if @account
      @error_recovery = AiErrorRecoveryService.new(@account, @execution_context) if @account
    rescue StandardError => e
      @logger.warn "Failed to initialize enhanced services: #{e.message}"
      @load_balancer = nil
      @error_recovery = nil
    end
  end

  # Main orchestration method - coordinates multiple agent executions
  def orchestrate_workflow(workflow_config)
    @logger.info "Starting AI workflow orchestration for account #{@account.id}"

    validate_workflow_config!(workflow_config)

    workflow_execution = create_workflow_execution(workflow_config)

    # Broadcast workflow started
    AiExecutionStatusChannel.broadcast_workflow_status(workflow_execution)

    begin
      execute_workflow(workflow_execution, workflow_config)
    rescue => e
      @logger.error "Workflow orchestration failed: #{e.message}"
      workflow_execution.update!(
        status: "failed",
        error_message: e.message,
        completed_at: Time.current
      )

      # Broadcast failure
      AiExecutionStatusChannel.broadcast_workflow_status(workflow_execution)

      raise OrchestrationError, "Workflow execution failed: #{e.message}"
    end

    workflow_execution
  end

  # Execute a single agent with load balancing and provider selection
  def execute_agent_with_orchestration(agent, input_parameters, options = {})
    @logger.info "Orchestrating execution for agent #{agent.id}"

    # Select optimal provider based on current load and performance metrics
    optimal_provider = select_optimal_provider(agent, options)

    # Check resource limits and throttling
    enforce_resource_limits!(agent, optimal_provider)

    # Create execution record
    execution = agent.ai_agent_executions.create!(
      user: @user,
      ai_provider: optimal_provider,
      input_parameters: input_parameters,
      status: "pending",
      execution_id: SecureRandom.uuid,
      metadata: build_execution_metadata(agent, optimal_provider, options)
    )

    # Queue execution with appropriate priority
    priority = calculate_execution_priority(agent, @user, options)
    AiAgentExecutionJob.perform_async(
      execution.id,
      priority: priority,
      orchestration_context: build_orchestration_context(execution, options)
    )

    # Update orchestration metrics
    update_orchestration_metrics(agent, optimal_provider)

    execution
  end

  # Monitor and manage running executions
  def monitor_executions
    active_executions = @account.ai_agent_executions.where(status: [ "pending", "running" ])

    monitoring_results = {
      total_active: active_executions.count,
      by_status: active_executions.group(:status).count,
      by_provider: active_executions.joins(:ai_provider).group("ai_providers.name").count,
      resource_usage: calculate_resource_usage(active_executions),
      performance_metrics: calculate_performance_metrics(active_executions)
    }

    # Check for executions that need intervention
    check_for_stuck_executions(active_executions)
    check_resource_constraints(active_executions)

    monitoring_results
  end

  # Optimize execution parameters based on historical performance
  def optimize_execution_parameters(agent, input_parameters)
    @logger.info "Optimizing parameters for agent #{agent.id}"

    # Analyze historical performance data
    historical_data = analyze_historical_performance(agent)

    # Apply optimization strategies
    optimized_params = {
      provider_preferences: recommend_providers(agent, historical_data),
      resource_allocation: optimize_resource_allocation(agent, historical_data),
      execution_settings: optimize_execution_settings(agent, input_parameters, historical_data),
      cost_optimization: apply_cost_optimization(agent, historical_data)
    }

    @logger.info "Applied optimizations for agent #{agent.id}: #{optimized_params.keys.join(', ')}"

    optimized_params
  end

  # Real-time load balancing across providers
  def balance_load_across_providers
    providers = @account.ai_providers.active.includes(:ai_agent_executions)

    load_metrics = providers.map do |provider|
      current_load = calculate_provider_current_load(provider)
      {
        provider: provider,
        current_load: current_load,
        capacity: provider.metadata&.dig("max_concurrent") || 10,
        utilization: (current_load / (provider.metadata&.dig("max_concurrent") || 10).to_f * 100).round(2),
        avg_response_time: calculate_provider_avg_response_time(provider),
        success_rate: calculate_provider_success_rate(provider)
      }
    end

    # Redistribute load if necessary
    rebalance_executions_if_needed(load_metrics)

    load_metrics
  end

  # Predictive scaling and resource management
  def predict_and_scale_resources
    usage_patterns = analyze_usage_patterns
    predicted_load = predict_future_load(usage_patterns)

    scaling_recommendations = {
      immediate_actions: generate_immediate_actions(predicted_load),
      short_term_scaling: recommend_short_term_scaling(predicted_load),
      long_term_planning: recommend_long_term_planning(usage_patterns)
    }

    # Auto-scale if configured
    if auto_scaling_enabled?
      apply_auto_scaling(scaling_recommendations[:immediate_actions])
    end

    scaling_recommendations
  end

  # Execute workflow using the stored workflow instance
  def execute_workflow(input_variables: {})
    raise OrchestrationError, "No workflow set" unless @workflow

    workflow_run = @workflow.runs.create!(
      account: @account,
      user: @user,
      input_variables: input_variables,
      status: "running",
      run_id: SecureRandom.uuid,
      started_at: Time.current
    )

    begin
      orchestrator = Mcp::AiWorkflowOrchestrator.new(
        workflow_run: workflow_run,
        account: @account,
        user: @user
      )

      orchestrator.execute
      workflow_run.reload
    rescue => e
      workflow_run.update!(
        status: "failed",
        error_message: e.message,
        completed_at: Time.current
      )
      raise e
    end
  end

  # Getters for test compatibility
  def execution_context
    @execution_context
  end

  def node_executors
    @node_executors
  end

  private

  def build_execution_context
    return {} unless @workflow

    {
      workflow_id: @workflow.id,
      account_id: @account.id,
      user_id: @user&.id,
      created_at: Time.current.iso8601
    }
  end

  def build_node_executors_registry
    {
      "ai_agent" => "AiWorkflowNodeExecutors::AiAgentExecutor",
      "api_call" => "AiWorkflowNodeExecutors::ApiCallExecutor",
      "webhook" => "AiWorkflowNodeExecutors::WebhookExecutor",
      "condition" => "AiWorkflowNodeExecutors::ConditionExecutor",
      "loop" => "AiWorkflowNodeExecutors::LoopExecutor",
      "transform" => "AiWorkflowNodeExecutors::TransformExecutor",
      "delay" => "AiWorkflowNodeExecutors::DelayExecutor",
      "human_approval" => "AiWorkflowNodeExecutors::HumanApprovalExecutor",
      "sub_workflow" => "AiWorkflowNodeExecutors::SubWorkflowExecutor",
      "merge" => "AiWorkflowNodeExecutors::MergeExecutor",
      "split" => "AiWorkflowNodeExecutors::SplitExecutor"
    }
  end

  private

  def validate_workflow_config!(config)
    required_keys = %w[name agents execution_order]
    missing_keys = required_keys - config.keys.map(&:to_s)

    if missing_keys.any?
      raise OrchestrationError, "Missing required workflow configuration keys: #{missing_keys.join(', ')}"
    end

    unless config["agents"].is_a?(Array) && config["agents"].any?
      raise OrchestrationError, "Workflow must specify at least one agent"
    end
  end

  def create_workflow_execution(config)
    # Note: This method is obsolete with MCP orchestration
    # AiWorkflowExecution model has been replaced by AiWorkflowRun
    # This code path should not be used with new MCP workflows
    raise OrchestrationError, "Legacy workflow execution creation is deprecated. Use MCP workflows instead."
  end

  def execute_workflow(workflow_execution, config)
    workflow_execution.update!(status: "running", started_at: Time.current)

    results = case config["execution_order"]
    when "sequential"
      execute_sequential_workflow(workflow_execution, config)
    when "parallel"
      execute_parallel_workflow(workflow_execution, config)
    when "conditional"
      execute_conditional_workflow(workflow_execution, config)
    else
      raise OrchestrationError, "Unknown execution order: #{config['execution_order']}"
    end

    # Compile final output data from execution results
    final_output = compile_workflow_output(results, config)

    workflow_execution.update!(
      status: "completed",
      completed_at: Time.current,
      output_variables: final_output
    )
  end

  def execute_sequential_workflow(workflow_execution, config)
    results = []
    total_agents = config["agents"].size

    config["agents"].each_with_index do |agent_config, index|
      agent = @account.ai_agents.find(agent_config["id"])
      input = build_agent_input(agent_config, results, index)

      # Update progress and broadcast
      progress = (index.to_f / total_agents * 100).round(1)
      workflow_execution.update!(
        metadata: workflow_execution.metadata.merge(
          "progress_percentage" => progress,
          "current_step" => index + 1,
          "total_steps" => total_agents,
          "current_agent" => agent.name
        )
      )

      broadcast_workflow_update(workflow_execution, {
        type: "workflow_progress",
        message: "Processing step #{index + 1}/#{total_agents}: #{agent.name}",
        current_agent: agent.name
      })

      execution = execute_agent_with_orchestration(agent, input,
        workflow_context: workflow_execution,
        step_index: index
      )

      # Wait for completion before proceeding
      wait_for_execution_completion(execution)

      results << {
        agent_id: agent.id,
        execution_id: execution.id,
        result: execution.reload.output_data
      }
    end

    # Update workflow metadata
    workflow_execution.update!(
      metadata: workflow_execution.metadata.merge(
        "progress_percentage" => 100,
        "completed_steps" => total_agents,
        "results" => results
      )
    )

    # Broadcast completion
    broadcast_workflow_update(workflow_execution, {
      type: "workflow_completed",
      message: "Workflow execution completed successfully"
    })

    results
  end

  def execute_parallel_workflow(workflow_execution, config)
    executions = []

    # Start all agents in parallel
    config["agents"].each_with_index do |agent_config, index|
      agent = @account.ai_agents.find(agent_config["id"])
      input = build_agent_input(agent_config, [], index)

      execution = execute_agent_with_orchestration(agent, input,
        workflow_context: workflow_execution,
        step_index: index
      )

      executions << execution
    end

    # Wait for all to complete
    wait_for_all_executions_completion(executions)

    results = executions.map do |execution|
      execution.reload
      {
        agent_id: execution.ai_agent.id,
        execution_id: execution.id,
        result: execution.output_data
      }
    end

    workflow_execution.update!(
      metadata: workflow_execution.metadata.merge("results" => results)
    )

    results
  end

  def execute_conditional_workflow(workflow_execution, config)
    # Simple conditional workflow implementation - execute based on condition
    results = []

    condition_met = evaluate_workflow_condition(config["condition"] || {})
    agents_to_execute = condition_met ? config["agents"] : config["fallback_agents"] || []

    agents_to_execute.each_with_index do |agent_config, index|
      agent = @account.ai_agents.find(agent_config["id"])
      input = build_agent_input(agent_config, results, index)

      execution = execute_agent_with_orchestration(agent, input,
        workflow_context: workflow_execution,
        step_index: index
      )

      wait_for_execution_completion(execution)

      results << {
        agent_id: agent.id,
        execution_id: execution.id,
        result: execution.reload.output_data
      }
    end

    workflow_execution.update!(
      metadata: workflow_execution.metadata.merge(
        "condition_met" => condition_met,
        "results" => results
      )
    )

    results
  end

  # Evaluate workflow condition (simple implementation)
  def evaluate_workflow_condition(condition)
    # For now, return true for any condition
    # In a full implementation, this would evaluate the condition logic
    condition.present? ? true : false
  end

  def select_optimal_provider(agent, options = {})
    available_providers = agent.compatible_providers.active

    if available_providers.empty?
      raise OrchestrationError, "No available providers for agent #{agent.id}"
    end

    # Score providers based on multiple factors
    provider_scores = available_providers.map do |provider|
      score = calculate_provider_score(provider, agent, options)
      { provider: provider, score: score }
    end

    # Select best provider
    best_provider = provider_scores.max_by { |p| p[:score] }[:provider]

    @logger.info "Selected provider #{best_provider.name} for agent #{agent.id}"

    best_provider
  end

  def calculate_provider_score(provider, agent, options)
    # Multi-factor scoring algorithm
    base_score = 100

    # Factor in current load (lower load = higher score)
    current_load = calculate_provider_current_load(provider)
    max_load = provider.metadata&.dig("max_concurrent") || 10
    load_factor = [ 1.0 - (current_load / max_load.to_f), 0.1 ].max

    # Factor in success rate
    success_rate = calculate_provider_success_rate(provider) / 100.0

    # Factor in response time (lower = better)
    avg_response_time = calculate_provider_avg_response_time(provider)
    time_factor = [ 1.0 / (avg_response_time / 1000.0), 0.1 ].max

    # Factor in cost (lower = better, unless cost_priority is low)
    cost_factor = options[:optimize_for_cost] ? calculate_cost_factor(provider) : 1.0

    # Calculate weighted score
    score = base_score *
            (load_factor * 0.3) *
            (success_rate * 0.3) *
            (time_factor * 0.25) *
            (cost_factor * 0.15)

    score.round(2)
  end

  def enforce_resource_limits!(agent, provider)
    # Check account limits
    current_executions = @account.ai_agent_executions.where(status: [ "pending", "running" ]).count
    max_concurrent = @account.subscription&.ai_execution_limit || 10

    if current_executions >= max_concurrent
      raise ResourceLimitError, "Account concurrent execution limit reached (#{max_concurrent})"
    end

    # Check provider limits
    provider_executions = provider.ai_agent_executions.where(status: [ "pending", "running" ]).count
    provider_max = provider.metadata&.dig("max_concurrent") || 10

    if provider_executions >= provider_max
      raise ResourceLimitError, "Provider #{provider.name} concurrent execution limit reached"
    end
  end

  def build_execution_metadata(agent, provider, options)
    {
      orchestration_version: "1.0",
      selected_provider: provider.name,
      optimization_applied: options.present?,
      workflow_context: options[:workflow_context]&.id,
      step_index: options[:step_index],
      selection_factors: {
        load_balancing: true,
        cost_optimization: options[:optimize_for_cost] || false,
        performance_optimization: true
      }
    }
  end

  def calculate_execution_priority(agent, user, options)
    base_priority = 5

    # Higher priority for premium accounts
    base_priority += 2 if user.account.subscription&.premium?

    # Higher priority for workflow executions
    base_priority += 1 if options[:workflow_context]

    # Higher priority for time-sensitive agents
    base_priority += 1 if agent.agent_type == "real_time"

    [ base_priority, 10 ].min
  end

  def build_orchestration_context(execution, options)
    {
      orchestrated: true,
      workflow_id: options[:workflow_context]&.id,
      step_index: options[:step_index],
      optimization_settings: options.except(:workflow_context)
    }
  end

  def update_orchestration_metrics(agent, provider)
    # Update real-time metrics for monitoring dashboard
    Rails.cache.increment("orchestration:executions:#{@account.id}", 1)
    Rails.cache.increment("orchestration:provider_usage:#{provider.id}", 1)
    Rails.cache.write("orchestration:last_activity:#{@account.id}", Time.current, expires_in: 1.hour)
  end

  # Additional helper methods would be implemented here
  def calculate_resource_usage(executions); {}; end
  def calculate_performance_metrics(executions); {}; end
  def check_for_stuck_executions(executions); end
  def check_resource_constraints(executions); end
  def analyze_historical_performance(agent); {}; end
  def recommend_providers(agent, historical_data); []; end
  def optimize_resource_allocation(agent, historical_data); {}; end
  def optimize_execution_settings(agent, input_parameters, historical_data); {}; end
  def apply_cost_optimization(agent, historical_data); {}; end
  def calculate_provider_current_load(provider); provider.ai_agent_executions.where(status: [ "pending", "running" ]).count; end
  def calculate_provider_avg_response_time(provider); provider.ai_agent_executions.where(created_at: 24.hours.ago..Time.current).average(:duration_ms) || 1000; end
  def calculate_provider_success_rate(provider); executions = provider.ai_agent_executions.where(created_at: 24.hours.ago..Time.current); return 95 if executions.empty?; successful = executions.where(status: "completed").count; (successful.to_f / executions.count * 100).round(2); end
  def rebalance_executions_if_needed(load_metrics); end
  def analyze_usage_patterns; {}; end
  def predict_future_load(patterns); {}; end
  def generate_immediate_actions(predicted_load); []; end
  def recommend_short_term_scaling(predicted_load); {}; end
  def recommend_long_term_planning(usage_patterns); {}; end
  def auto_scaling_enabled?; false; end
  def apply_auto_scaling(actions); end
  def build_agent_input(agent_config, previous_results, index); agent_config["input"] || {}; end
  def wait_for_execution_completion(execution); end
  def wait_for_all_executions_completion(executions); end
  def calculate_cost_factor(provider); 1.0; end

  # Build AI agent prompt from input data and agent configuration
  def build_agent_prompt(agent_config, input_data)
    base_prompt = agent_config["system_prompt"] || agent_config["prompt"] || "You are a helpful AI assistant."

    # If there's input data, append it to the prompt
    if input_data.present?
      user_input = case input_data
      when String
        input_data
      when Hash
        input_data.map { |k, v| "#{k}: #{v}" }.join("\n")
      when Array
        input_data.join("\n")
      else
        input_data.to_s
      end

      "#{base_prompt}\n\nUser Input:\n#{user_input}"
    else
      base_prompt
    end
  end

  # Calculate cost from token usage based on provider pricing
  def calculate_cost_from_usage(usage, provider_name)
    return 0.0 unless usage&.dig(:total_tokens)

    # Default pricing per 1000 tokens (in USD cents)
    pricing = case provider_name.to_s.downcase
    when "openai"
      { prompt: 1.0, completion: 2.0 } # GPT-4 pricing as baseline
    when "anthropic"
      { prompt: 0.8, completion: 2.4 } # Claude pricing
    when "ollama"
      { prompt: 0.0, completion: 0.0 } # Local model, no cost
    else
      { prompt: 1.0, completion: 2.0 } # Default pricing
    end

    prompt_tokens = usage[:prompt_tokens] || 0
    completion_tokens = usage[:completion_tokens] || 0

    prompt_cost = (prompt_tokens / 1000.0) * pricing[:prompt]
    completion_cost = (completion_tokens / 1000.0) * pricing[:completion]

    (prompt_cost + completion_cost).round(6)
  end

  # Compile final output data from workflow execution results
  def compile_workflow_output(results, config)
    return {} if results.blank?

    # For sequential workflows, take the last result as primary output
    # and collect all results in an array
    if config["execution_order"] == "sequential"
      last_result = results.last
      {
        "primary_output" => last_result&.dig("result"),
        "all_results" => results,
        "execution_summary" => {
          "total_steps" => results.size,
          "completion_time" => Time.current.iso8601,
          "success" => true
        }
      }
    else
      # For parallel and conditional workflows, merge all results
      {
        "results" => results,
        "execution_summary" => {
          "total_executions" => results.size,
          "completion_time" => Time.current.iso8601,
          "success" => true
        }
      }
    end
  end

  # Determine if a node type should be executed asynchronously
  def should_execute_asynchronously?(node_type)
    # Async execution for complex, potentially long-running operations
    %w[ai_agent api_call webhook human_approval sub_workflow transform loop].include?(node_type)
  end

  # Delegate node execution to background worker
  def delegate_to_worker(node_execution, input_data)
    @logger.info "Delegating node execution #{node_execution.execution_id} to background worker"

    # Queue the job with execution context - handle gracefully if worker not available
    begin
      # Try to require the job class - this may fail in test environment
      if defined?(Sidekiq) && Rails.env.production?
        require_relative "../../../worker/app/jobs/ai_workflow_node_execution_job"
        AiWorkflowNodeExecutionJob.perform_async(
          node_execution.id,
          {
            "execution_context" => build_worker_execution_context(node_execution, input_data),
            "workflow_run_id" => node_execution.ai_workflow_run_id,
            "account_id" => @account.id,
            "user_id" => @user&.id
          }
        )
        @logger.info "Job queued successfully for node execution #{node_execution.execution_id}"
      else
        # In test/development environment, execute synchronously
        @logger.info "Executing node synchronously in test/development environment"
        execute_node_directly(node_execution, input_data)
      end
    rescue StandardError => e
      @logger.error "Failed to delegate to worker: #{e.message}"
      # Fallback to direct execution
      execute_node_directly(node_execution, input_data)
    end
  end

  # Execute node directly (synchronous execution for test/development)
  def execute_node_directly(node_execution, input_data)
    begin
      node_execution.update!(
        status: "running",
        started_at: Time.current,
        input_data: input_data
      )

      # Get the appropriate node executor
      executor = @node_executors[node_execution.node_type.to_sym]
      unless executor
        raise ExecutionError, "No executor found for node type: #{node_execution.node_type}"
      end

      # Execute the node
      result = executor.call(node_execution, input_data, @execution_context)

      # Update node execution with results
      node_execution.update!(
        status: "completed",
        completed_at: Time.current,
        output_data: result || {},
        duration_ms: ((Time.current - node_execution.started_at) * 1000).round
      )

      @logger.info "Node execution #{node_execution.execution_id} completed successfully"
      result

    rescue StandardError => e
      @logger.error "Node execution #{node_execution.execution_id} failed: #{e.message}"
      node_execution.update!(
        status: "failed",
        completed_at: Time.current,
        error_message: e.message,
        error_details: { error: e.class.name, message: e.message, backtrace: e.backtrace.first(10) }
      )
      raise
    end
  end

  # Build execution context for worker
  def build_worker_execution_context(node_execution, input_data)
    {
      "node_id" => node_execution.node_id,
      "node_type" => node_execution.node_type,
      "input_data" => input_data,
      "configuration" => node_execution.ai_workflow_node.configuration,
      "workflow_context" => @execution_context,
      "started_at" => Time.current.iso8601
    }
  end

  # Broadcasting methods moved to Concerns::AiOrchestrationBroadcasting

  public

  # Execute the entire workflow and return the workflow run
  def execute_workflow(input_variables: {}, user: nil, trigger_type: "manual")
    @logger.info "Starting workflow execution for workflow #{@workflow.id}"

    # Create workflow run with initializing status (MCP orchestrator will transition to running)
    run = @workflow.ai_workflow_runs.create!(
      account: @account,
      triggered_by_user: user || @user,
      trigger_type: trigger_type,
      input_variables: input_variables,
      run_id: SecureRandom.uuid,
      status: "initializing",
      started_at: Time.current,
      total_nodes: @workflow.ai_workflow_nodes.count,
      runtime_context: build_workflow_execution_context
    )

    begin
      # Execute the workflow using the MCP orchestrator
      orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: run, account: @account, user: user || @user)
      orchestrator.execute

      run.reload
      @logger.info "Completed workflow execution for run #{run.run_id} with status: #{run.status}"

    rescue StandardError => e
      @logger.error "Workflow execution failed: #{e.message}"
      run.fail_execution!(e.message, {
        exception_class: e.class.name,
        backtrace: e.backtrace&.first(5)
      })
    end

    run
  end

  # Execute a single node within a workflow run
  def execute_node(node, run, input_data = {})
    @logger.info "Executing node #{node.node_id} for run #{run.run_id}"

    # Create node execution record
    node_execution = run.ai_workflow_node_executions.create!(
      ai_workflow_node: node,
      node_id: node.node_id,
      node_type: node.node_type,
      status: "pending",
      input_data: input_data,
      started_at: Time.current
    )

    # Determine execution strategy based on node type
    if should_execute_asynchronously?(node.node_type)
      # Delegate to worker for async execution
      delegate_to_worker(node_execution, input_data)
      return node_execution
    end

    begin
      # Execute synchronously for simple nodes
      node_execution.update!(status: "running")

      # Execute based on node type
      result = case node.node_type
      when "start"
        {
          success: true,
          output_data: input_data,
          cost: 0,
          tokens_consumed: 0,
          tokens_generated: 0
        }
      when "end"
        {
          success: true,
          output_data: input_data,
          cost: 0,
          tokens_consumed: 0,
          tokens_generated: 0
        }
      when "ai_agent"
        execute_ai_agent_node(node, input_data)
      when "api_call"
        execute_api_call_node(node, input_data)
      when "webhook"
        execute_webhook_node(node, input_data)
      when "condition"
        execute_condition_node(node, input_data)
      when "transform"
        execute_transform_node(node, input_data)
      when "human_approval"
        execute_human_approval_node(node, input_data)
      else
        { success: false, error_message: "Unknown node type: #{node.node_type}" }
      end

      # Update execution with results
      if result[:success]
        node_execution.update!(
          status: "completed",
          completed_at: Time.current,
          output_data: result[:output_data] || {},
          cost: result[:cost] || 0,
          duration_ms: ((Time.current - node_execution.started_at) * 1000).to_i
        )
      else
        node_execution.update!(
          status: "failed",
          completed_at: Time.current,
          error_details: {
            error_message: result[:error_message],
            **(result[:error_details] || {})
          }
        )
      end

    rescue StandardError => e
      @logger.error "Node execution failed: #{e.message}"
      node_execution.update!(
        status: "failed",
        completed_at: Time.current,
        error_details: {
          error_message: e.message,
          exception_class: e.class.name,
          backtrace: e.backtrace&.first(5)
        }
      )
    end

    node_execution
  end

  # Validate workflow structure for execution readiness
  def validate_workflow_structure
    errors = []
    nodes = @workflow.ai_workflow_nodes.includes(:source_edges, :target_edges)
    edges = @workflow.ai_workflow_edges

    # Check for start and end nodes
    start_nodes = nodes.select(&:is_start_node?)
    end_nodes = nodes.select(&:is_end_node?)

    errors << "Workflow must have at least one start node" if start_nodes.empty?
    errors << "Workflow must have at least one end node" if end_nodes.empty?

    # Check for disconnected nodes
    connected_nodes = Set.new
    edges.each do |edge|
      connected_nodes.add(edge.source_node_id)
      connected_nodes.add(edge.target_node_id)
    end

    disconnected = nodes.reject { |node| connected_nodes.include?(node.node_id) || node.is_start_node? || node.is_end_node? }
    if disconnected.any?
      errors << "Found #{disconnected.count} disconnected nodes: #{disconnected.map(&:name).join(', ')}"
    end

    # Check for circular dependencies using DFS
    if has_circular_dependency?(nodes, edges)
      errors << "Workflow contains circular dependency"
    end

    # Validate node configurations
    nodes.each do |node|
      unless node.valid?
        errors << "Node '#{node.name}' has invalid configuration: #{node.errors.full_messages.join(', ')}"
      end
    end

    {
      valid: errors.empty?,
      errors: errors
    }
  end

  # Calculate execution path through workflow
  def calculate_execution_path(context_variables = {})
    nodes = @workflow.ai_workflow_nodes.includes(:source_edges, :target_edges)
    edges = @workflow.ai_workflow_edges

    start_nodes = nodes.select(&:is_start_node?)
    return [] if start_nodes.empty?

    path = []
    visited = Set.new

    start_nodes.each do |start_node|
      path.concat(trace_execution_path(start_node, nodes, edges, context_variables, visited))
    end

    path.uniq
  end

  # Pause workflow execution
  def pause_execution(run)
    unless run.status == "running"
      raise StandardError, "Cannot pause workflow run in status: #{run.status}"
    end

    # Create checkpoint data in metadata
    checkpoint_data = {
      execution_state: "paused",
      paused_at: Time.current.iso8601,
      current_node_executions: run.ai_workflow_node_executions
                                  .where(status: %w[pending running])
                                  .pluck(:id, :node_id, :status),
      runtime_context: run.runtime_context
    }

    run.update!(
      status: "waiting_approval",  # Use waiting_approval as closest to paused
      metadata: (run.metadata || {}).merge("checkpoint_data" => checkpoint_data)
    )

    @logger.info "Paused workflow run #{run.run_id}"
  end

  # Resume paused workflow execution
  def resume_execution(run)
    # waiting_approval is used as paused state
    unless run.status == "waiting_approval" && run.metadata&.dig("checkpoint_data", "execution_state") == "paused"
      raise StandardError, "Cannot resume workflow run that is not paused. Current status: #{run.status}"
    end

    run.update!(
      status: "running",
      metadata: (run.metadata || {}).merge("resumed_at" => Time.current.iso8601)
    )

    # Restore execution from checkpoint stored in metadata
    checkpoint_data = run.metadata&.dig("checkpoint_data")
    if checkpoint_data.present?
      execute_from_checkpoint(checkpoint_data)
    end

    @logger.info "Resumed workflow run #{run.run_id}"
  end

  # Cancel workflow execution
  def cancel_execution(run, reason: nil)
    # Cancel all active node executions
    run.ai_workflow_node_executions
       .where(status: %w[pending running])
       .update_all(
         status: "cancelled",
         completed_at: Time.current,
         error_details: { cancellation_reason: reason || "Workflow execution cancelled" }.to_json
       )

    # Update run status using the model's cancel method
    run.cancel_execution!(reason || "Workflow execution cancelled")

    # Log cancellation
    log_workflow_event(run, "workflow_cancelled", {
      reason: reason || "Manual cancellation",
      cancelled_at: Time.current.iso8601
    })

    @logger.info "Cancelled workflow run #{run.run_id}#{reason ? " - #{reason}" : ''}"
  end

  # Calculate comprehensive execution statistics
  def execution_statistics(run, include_performance: false)
    executions = run.ai_workflow_node_executions

    # AiWorkflowNodeExecution uses cost (not tokens_consumed/tokens_generated)
    total_cost = executions.sum(:cost) || 0

    stats = {
      total_nodes: executions.count,
      completed_nodes: executions.where(status: "completed").count,
      failed_nodes: executions.where(status: "failed").count,
      cancelled_nodes: executions.where(status: "cancelled").count,
      success_rate: calculate_success_rate(executions),
      total_cost: total_cost,
      # Estimate tokens based on cost (rough estimation)
      total_tokens: (total_cost / 0.002 * 1000).to_i  # ~$0.002 per 1K tokens average
    }

    if include_performance
      completed_executions = executions.where(status: "completed").where.not(duration_ms: nil)

      stats.merge!({
        average_node_execution_time: completed_executions.average(:duration_ms)&.to_f || 0,
        execution_efficiency_score: calculate_efficiency_score(run),
        cost_per_token: stats[:total_tokens] > 0 ? (stats[:total_cost] / stats[:total_tokens]).round(6) : 0
      })
    end

    stats
  end

  private

  def calculate_workflow_progress(workflow_execution)
    case workflow_execution.status
    when "completed"
      100
    when "failed", "cancelled"
      workflow_execution.metadata.dig("progress_percentage") || 0
    when "running"
      workflow_execution.metadata.dig("progress_percentage") || 25
    when "pending", "initializing"
      0
    else
      0
    end
  end

  def calculate_recent_success_rate(executions)
    return 100.0 if executions.empty?

    successful = executions.where(status: "completed").count
    (successful.to_f / executions.count * 100).round(1)
  end

  def get_system_status
    return {} unless @account&.id

    # Get current active executions
    active_executions = @account.ai_agent_executions.where(status: [ "queued", "processing" ])
    recent_executions = @account.ai_agent_executions.where(created_at: 1.hour.ago..Time.current)

    # Get provider status
    providers = @account.ai_providers.active
    provider_status = providers.map do |provider|
      current_load = calculate_provider_current_load(provider)
      max_load = provider.metadata&.dig("max_concurrent") || 10

      {
        id: provider.id,
        name: provider.name,
        status: current_load < max_load ? "available" : "at_capacity",
        current_load: current_load,
        max_capacity: max_load,
        success_rate: calculate_provider_success_rate(provider)
      }
    end

    # Get workflow status
    active_workflows = @account.ai_workflow_executions.where(status: [ "pending", "running" ])

    {
      account_id: @account.id,
      active_executions: active_executions.count,
      recent_executions: recent_executions.count,
      active_workflows: active_workflows.count,
      providers: provider_status,
      system_load: calculate_system_load_percentage(active_executions, @account),
      last_activity: recent_executions.maximum(:created_at) || 1.day.ago,
      overall_health: determine_system_health(recent_executions, active_executions)
    }
  end

  def calculate_system_load_percentage(active_executions, account)
    max_concurrent = account.subscription&.ai_execution_limit || 10
    current_load = active_executions.count

    return 0 if max_concurrent == 0
    [ (current_load.to_f / max_concurrent * 100).round(1), 100.0 ].min
  end

  def determine_system_health(recent_executions, active_executions)
    return "idle" if recent_executions.empty? && active_executions.empty?

    if recent_executions.any?
      success_rate = calculate_recent_success_rate(recent_executions)

      case success_rate
      when 90..100
        "excellent"
      when 75..89
        "good"
      when 50..74
        "degraded"
      else
        "poor"
      end
    else
      active_executions.any? ? "active" : "idle"
    end
  end

  # Node execution methods moved to Concerns::AiNodeExecutors

  # Workflow analysis methods
  def has_circular_dependency?(nodes, edges)
    # Simple cycle detection using DFS
    graph = build_adjacency_graph(edges)
    visited = Set.new
    rec_stack = Set.new

    nodes.each do |node|
      next if visited.include?(node.node_id)
      return true if has_cycle_dfs(node.node_id, graph, visited, rec_stack)
    end

    false
  end

  def build_adjacency_graph(edges)
    graph = Hash.new { |h, k| h[k] = [] }
    edges.each do |edge|
      graph[edge.source_node_id] << edge.target_node_id
    end
    graph
  end

  def has_cycle_dfs(node_id, graph, visited, rec_stack)
    visited.add(node_id)
    rec_stack.add(node_id)

    graph[node_id].each do |neighbor|
      if !visited.include?(neighbor)
        return true if has_cycle_dfs(neighbor, graph, visited, rec_stack)
      elsif rec_stack.include?(neighbor)
        return true
      end
    end

    rec_stack.delete(node_id)
    false
  end

  def trace_execution_path(current_node, nodes, edges, context_variables, visited)
    return [] if visited.include?(current_node.id)
    visited.add(current_node.id)

    path = [ current_node ]

    # Find outgoing edges
    outgoing_edges = edges.select { |e| e.source_node_id == current_node.node_id }

    # For each outgoing edge, continue tracing
    outgoing_edges.each do |edge|
      target_node = nodes.find { |n| n.node_id == edge.target_node_id }
      next unless target_node

      # Simple condition evaluation for conditional edges
      if edge.is_conditional? && context_variables.present?
        # Skip if condition doesn't match (simplified)
        next unless evaluate_edge_condition(edge, context_variables)
      end

      path.concat(trace_execution_path(target_node, nodes, edges, context_variables, visited.dup))
    end

    path
  end

  def evaluate_edge_condition(edge, context_variables)
    # Simplified condition evaluation
    condition = edge.condition_config
    return true if condition.blank?

    # Example: check if context_variables match condition
    true
  end

  def execute_from_checkpoint(checkpoint_data)
    # Restore execution state from checkpoint
    execution_state = checkpoint_data["execution_state"]
    current_executions = checkpoint_data["current_node_executions"] || []

    @logger.info "Restoring execution from checkpoint: #{execution_state}"

    # Resume any pending node executions
    current_executions.each do |exec_data|
      node_id = exec_data[1]  # node_id is at index 1
      status = exec_data[2]   # status is at index 2

      if status == "running"
        @logger.info "Resuming execution for node #{node_id}"
        # Here we would trigger the actual node execution
        # For now, just log that we would resume it
      end
    end
  end

  def log_workflow_event(run, event_type, data = {})
    # Log workflow events for audit trail
    @logger.info "Workflow Event [#{run.run_id}] #{event_type}: #{data}"

    # Here we would create a workflow log entry
    # For now, just use standard logging
  end

  def calculate_success_rate(executions)
    return 0.0 if executions.empty?

    successful = executions.where(status: [ "completed", "skipped" ]).count
    (successful.to_f / executions.count * 100).round(2)
  end

  def calculate_efficiency_score(run)
    # Simple efficiency calculation based on completion time vs expected time
    return 0.0 unless run.completed_at && run.started_at

    actual_duration = run.completed_at - run.started_at
    expected_duration = estimate_expected_duration(run)

    return 100.0 if expected_duration <= 0

    efficiency = (expected_duration / actual_duration.to_f * 100).round(2)
    [ efficiency, 100.0 ].min
  end

  def estimate_expected_duration(run)
    # Estimate expected duration based on workflow complexity
    node_count = run.ai_workflow.ai_workflow_nodes.count
    base_time_per_node = 30 # seconds

    node_count * base_time_per_node
  end

  def build_workflow_execution_context
    {
      workflow_id: @workflow.id,
      account_id: @account.id,
      user_id: @user&.id,
      execution_started_at: Time.current.iso8601,
      orchestration_service: self.class.name
    }
  end
end
