# frozen_string_literal: true

# AiWorkflowService - Shared patterns for AI workflow execution services
#
# Provides common functionality for workflow-related services:
# - Workflow validation
# - Node execution patterns
# - State management helpers
# - Event broadcasting
# - Execution context management
#
# Usage:
#   class WorkflowExecutionService
#     include BaseAiService
#     include AiWorkflowService
#
#     def execute_workflow
#       with_workflow_context(@workflow_run) do
#         # Execute workflow logic
#       end
#     end
#   end
#
module AiWorkflowService
  extend ActiveSupport::Concern

  included do
    # Assumes BaseAiService is also included
  end

  # =============================================================================
  # WORKFLOW CONTEXT MANAGEMENT
  # =============================================================================

  # Execute block within workflow execution context
  #
  # @param workflow_run [Ai::WorkflowRun] The workflow run being executed
  # @yield Block to execute with workflow context
  def with_workflow_context(workflow_run)
    @workflow_run = workflow_run
    @workflow = workflow_run.workflow
    @execution_context = initialize_execution_context

    begin
      result = yield
      finalize_workflow_context(result)
      result
    rescue StandardError => e
      handle_workflow_error(e)
      raise
    ensure
      cleanup_workflow_context
    end
  end

  # =============================================================================
  # WORKFLOW VALIDATION
  # =============================================================================

  # Validate workflow can be executed
  #
  # @raise [ValidationError] if workflow cannot be executed
  def validate_workflow_executable!
    unless @workflow.can_execute?
      raise ValidationError, "Workflow cannot be executed: status=#{@workflow.status}"
    end

    unless @workflow.has_valid_structure?
      raise ValidationError, "Workflow has invalid structure"
    end

    validate_start_nodes!
    validate_mcp_requirements! if @workflow.uses_mcp?
  end

  # Validate workflow has start nodes
  def validate_start_nodes!
    start_nodes = find_start_nodes

    if start_nodes.empty?
      raise ValidationError, "Workflow has no start nodes"
    end
  end

  # Validate MCP tool requirements
  def validate_mcp_requirements!
    tool_requirements = @workflow.mcp_orchestration_config&.dig("tool_requirements") || []

    tool_requirements.each do |requirement|
      validate_mcp_tool_available!(requirement)
    end
  end

  def validate_mcp_tool_available!(requirement)
    tool_id = requirement["tool_id"]
    min_version = requirement["min_version"]

    # Check tool availability
    unless mcp_registry.tool_available?(tool_id)
      raise ValidationError, "Required MCP tool not found: #{tool_id}"
    end

    # Check version if specified
    if min_version.present?
      tool_version = mcp_registry.tool_version(tool_id)
      required_version = Gem::Version.new(min_version)

      if Gem::Version.new(tool_version) < required_version
        raise ValidationError,
              "Tool #{tool_id} version #{tool_version} is below required #{min_version}"
      end
    end
  end

  # =============================================================================
  # NODE NAVIGATION
  # =============================================================================

  # Find workflow start nodes
  #
  # @return [ActiveRecord::Relation] Start nodes
  def find_start_nodes
    # Find nodes marked as start nodes
    start_nodes = @workflow.nodes.where(is_start_node: true)

    # Fallback: nodes with no incoming edges
    if start_nodes.empty?
      all_target_node_ids = @workflow.edges.pluck(:target_node_id)
      start_nodes = @workflow.nodes.where.not(node_id: all_target_node_ids)
    end

    start_nodes
  end

  # Find next nodes from current node based on result
  #
  # @param current_node [Ai::WorkflowNode] Current node
  # @param node_result [Hash] Node execution result
  # @return [Array<Ai::WorkflowNode>] Next nodes to execute
  def find_next_nodes(current_node, node_result)
    outgoing_edges = @workflow.edges.where(source_node_id: current_node.node_id)

    # Evaluate edges to find valid paths
    valid_edges = outgoing_edges.select do |edge|
      evaluate_edge_condition(edge, node_result)
    end

    # Sort by priority
    valid_edges = valid_edges.sort_by { |edge| edge.priority || 0 }

    # Get target nodes
    target_node_ids = valid_edges.map(&:target_node_id)
    @workflow.nodes.where(node_id: target_node_ids)
  end

  # Check if node prerequisites are complete
  #
  # @param node [Ai::WorkflowNode] Node to check
  # @return [Boolean] Whether all prerequisites are complete
  def prerequisites_complete?(node)
    incoming_edges = @workflow.edges.where(target_node_id: node.node_id)

    # No incoming edges means node is ready
    return true if incoming_edges.empty?

    # Check all source nodes have executed
    incoming_edges.all? do |edge|
      source_result = @execution_context[:node_results][edge.source_node_id]
      source_result.present? && evaluate_edge_condition(edge, source_result)
    end
  end

  # =============================================================================
  # EDGE EVALUATION
  # =============================================================================

  # Evaluate if edge condition is satisfied
  #
  # @param edge [Ai::WorkflowEdge] Edge to evaluate
  # @param node_result [Hash] Node execution result
  # @return [Boolean] Whether edge condition is satisfied
  def evaluate_edge_condition(edge, node_result)
    return false if node_result.nil?

    case edge.edge_type
    when "default"
      true
    when "success"
      node_result[:success] == true
    when "error"
      node_result[:success] == false
    when "conditional"
      evaluate_conditional_expression(edge.condition, node_result)
    else
      true
    end
  end

  # Evaluate conditional expression
  #
  # @param condition [Hash] Condition to evaluate
  # @param node_result [Hash] Node result context
  # @return [Boolean] Evaluation result
  def evaluate_conditional_expression(condition, node_result)
    return true if condition.blank?

    # Use simple expression evaluator for now
    # TODO: Implement more robust expression evaluation
    operator = condition["operator"]
    field = condition["field"]
    value = condition["value"]

    actual_value = node_result.dig(*field.to_s.split("."))

    case operator
    when "equals"
      actual_value == value
    when "not_equals"
      actual_value != value
    when "greater_than"
      actual_value.to_f > value.to_f
    when "less_than"
      actual_value.to_f < value.to_f
    when "contains"
      actual_value.to_s.include?(value.to_s)
    else
      true
    end
  rescue StandardError => e
    log_warn "Conditional evaluation failed", {
      condition: condition,
      error: e.message
    }
    false
  end

  # =============================================================================
  # STATE MANAGEMENT
  # =============================================================================

  # Update workflow run status
  #
  # @param status [String] New status
  # @param attributes [Hash] Additional attributes to update
  def update_workflow_status(status, attributes = {})
    @workflow_run.update!(
      status: status,
      **attributes
    )

    broadcast_workflow_status(status, attributes)
  end

  # Update execution context
  #
  # @param node [Ai::WorkflowNode] Node that produced output
  # @param output_data [Hash] Node output data
  def update_execution_context(node, output_data)
    @execution_context[:node_results][node.node_id] = output_data
    @execution_context[:execution_path] << node.node_id

    # Extract variables from output
    if output_data.is_a?(Hash)
      extract_variables(node, output_data)
    end

    # Persist context
    @workflow_run.update_column(:runtime_context, @execution_context)
  end

  # =============================================================================
  # BROADCASTING
  # =============================================================================

  # Broadcast workflow status change
  #
  # @param status [String] New status
  # @param data [Hash] Additional data to broadcast
  def broadcast_workflow_status(status, data = {})
    AiOrchestrationChannel.broadcast_to(
      @workflow,
      {
        type: "workflow.status.changed",
        workflow_id: @workflow.id,
        run_id: @workflow_run.run_id,
        status: status,
        data: data,
        timestamp: Time.current.iso8601
      }
    )
  end

  # Broadcast node execution update
  #
  # @param node [Ai::WorkflowNode] Node being executed
  # @param status [String] Node execution status
  # @param data [Hash] Additional data
  def broadcast_node_execution(node, status, data = {})
    # Get the node execution record to use the channel's proper broadcast method
    node_execution = @workflow_run.node_executions
                                  .find_by(node_id: node.node_id)

    if node_execution
      # Use the channel's class method which sets the correct 'event' field
      # and broadcasts to all appropriate streams (run, workflow, account)
      # NOTE: Frontend expects "node.execution.updated" - do NOT use "workflow.node.execution.updated"
      AiOrchestrationChannel.broadcast_node_execution(
        node_execution,
        "node.execution.updated"
      )
    else
      Rails.logger.warn "[BASE_WORKFLOW_SERVICE] Node execution not found for node #{node.node_id}"
    end
  end

  # =============================================================================
  # ERROR HANDLING
  # =============================================================================

  # Handle workflow-specific errors
  #
  # @param error [StandardError] Error that occurred
  def handle_workflow_error(error)
    log_error "Workflow execution failed", {
      workflow_id: @workflow.id,
      run_id: @workflow_run.run_id,
      error: error.message
    }

    update_workflow_status("failed", {
      error_details: {
        error_message: error.message,
        error_class: error.class.name,
        backtrace: error.backtrace&.first(10)
      },
      completed_at: Time.current
    })
  end

  private

  # =============================================================================
  # CONTEXT INITIALIZATION
  # =============================================================================

  def initialize_execution_context
    {
      workflow_id: @workflow.id,
      workflow_run_id: @workflow_run.id,
      run_id: @workflow_run.run_id,
      account_id: @account&.id,
      user_id: @user&.id,
      started_at: Time.current,
      variables: @workflow_run.input_variables&.dup || {},
      node_results: {},
      execution_path: []
    }
  end

  def finalize_workflow_context(result)
    log_info "Workflow execution completed", {
      workflow_id: @workflow.id,
      run_id: @workflow_run.run_id,
      duration_ms: calculate_execution_duration
    }
  end

  def cleanup_workflow_context
    # Cleanup any temporary resources
    @execution_context = nil
  end

  # =============================================================================
  # HELPERS
  # =============================================================================

  def extract_variables(node, output_data)
    variable_mapping = node.configuration&.dig("output_variables") || {}

    variable_mapping.each do |var_name, output_path|
      value = extract_value_from_path(output_data, output_path)
      @execution_context[:variables][var_name] = value if value.present?
    end

    # Also extract direct variable assignments
    if output_data["variables"].is_a?(Hash)
      @execution_context[:variables].merge!(output_data["variables"])
    end
  end

  def extract_value_from_path(data, path)
    return data if path.blank?

    path.to_s.split(".").reduce(data) do |current, key|
      break nil unless current.is_a?(Hash) || current.is_a?(Array)

      if current.is_a?(Array) && key =~ /\A\d+\z/
        current[key.to_i]
      else
        current[key.to_s] || current[key.to_sym]
      end
    end
  end

  def calculate_execution_duration
    return 0 unless @workflow_run.started_at

    ((Time.current - @workflow_run.started_at) * 1000).round
  end

  def mcp_registry
    @mcp_registry ||= McpRegistryService.new(account: @account)
  end
end
