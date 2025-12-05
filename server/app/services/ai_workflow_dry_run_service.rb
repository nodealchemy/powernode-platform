# frozen_string_literal: true

class AiWorkflowDryRunService
  attr_reader :workflow, :input_variables, :user, :dry_run_result

  def initialize(workflow:, input_variables: {}, user:)
    @workflow = workflow
    @input_variables = input_variables
    @user = user
    @dry_run_result = {
      workflow_id: workflow.id,
      workflow_name: workflow.name,
      version: workflow.version,
      started_at: Time.current,
      nodes_executed: [],
      variables_snapshot: {},
      validation_errors: [],
      warnings: [],
      estimated_cost: 0.0,
      estimated_duration_ms: 0,
      execution_path: [],
      status: 'pending'
    }
  end

  def execute
    Rails.logger.info "[DryRun] Starting dry-run for workflow #{workflow.id}"

    # Validate workflow structure
    unless validate_workflow_structure
      @dry_run_result[:status] = 'failed'
      @dry_run_result[:completed_at] = Time.current
      return @dry_run_result
    end

    # Initialize variables
    initialize_workflow_variables

    # Simulate execution path
    simulate_execution_path

    # Calculate estimates
    calculate_estimates

    @dry_run_result[:status] = 'completed'
    @dry_run_result[:completed_at] = Time.current
    @dry_run_result[:duration_ms] = ((@dry_run_result[:completed_at] - @dry_run_result[:started_at]) * 1000).to_i

    Rails.logger.info "[DryRun] Completed dry-run for workflow #{workflow.id}"
    @dry_run_result
  rescue StandardError => e
    Rails.logger.error "[DryRun] Error during dry-run: #{e.message}"
    @dry_run_result[:status] = 'error'
    @dry_run_result[:error] = e.message
    @dry_run_result[:completed_at] = Time.current
    @dry_run_result
  end

  private

  def validate_workflow_structure
    valid = true

    # Check for start nodes
    if workflow.start_nodes.empty?
      @dry_run_result[:validation_errors] << 'No start node found in workflow'
      valid = false
    end

    # Check for circular dependencies
    if workflow.has_circular_dependencies?
      @dry_run_result[:validation_errors] << 'Circular dependency detected in workflow'
      valid = false
    end

    # Validate all nodes
    workflow.ai_workflow_nodes.each do |node|
      node_errors = validate_node(node)
      @dry_run_result[:validation_errors].concat(node_errors) if node_errors.any?
      valid = false if node_errors.any?
    end

    # Validate edges
    workflow.ai_workflow_edges.each do |edge|
      edge_errors = validate_edge(edge)
      @dry_run_result[:validation_errors].concat(edge_errors) if edge_errors.any?
      valid = false if edge_errors.any?
    end

    valid
  end

  def validate_node(node)
    errors = []

    # Check for required configuration
    case node.node_type
    when 'ai_agent'
      if node.configuration['agent_id'].blank?
        errors << "Node '#{node.name}' (#{node.node_id}): Missing required agent_id"
      end
    when 'api_call'
      if node.configuration['url'].blank?
        errors << "Node '#{node.name}' (#{node.node_id}): Missing required URL"
      end
    when 'condition'
      if node.configuration['condition_expression'].blank?
        errors << "Node '#{node.name}' (#{node.node_id}): Missing condition expression"
      end
    end

    # Validate connections
    if !node.is_start_node && !has_incoming_edges?(node)
      @dry_run_result[:warnings] << "Node '#{node.name}' (#{node.node_id}): No incoming connections (unreachable)"
    end

    errors
  end

  def validate_edge(edge)
    errors = []

    # Validate source node exists
    unless workflow.ai_workflow_nodes.find_by(node_id: edge.source_node_id)
      errors << "Edge #{edge.edge_id}: Source node #{edge.source_node_id} not found"
    end

    # Validate target node exists
    unless workflow.ai_workflow_nodes.find_by(node_id: edge.target_node_id)
      errors << "Edge #{edge.edge_id}: Target node #{edge.target_node_id} not found"
    end

    # Validate conditional edges
    if edge.is_conditional && edge.condition.blank?
      errors << "Edge #{edge.edge_id}: Conditional edge missing condition definition"
    end

    errors
  end

  def has_incoming_edges?(node)
    workflow.ai_workflow_edges.exists?(target_node_id: node.node_id)
  end

  def initialize_workflow_variables
    # Set input variables
    @dry_run_result[:variables_snapshot] = input_variables.deep_dup

    # Add workflow-defined variables with defaults
    workflow.ai_workflow_variables.each do |var|
      next if @dry_run_result[:variables_snapshot].key?(var.name)

      @dry_run_result[:variables_snapshot][var.name] = var.default_value
    end

    # Add system variables
    @dry_run_result[:variables_snapshot]['_workflow_id'] = workflow.id
    @dry_run_result[:variables_snapshot]['_workflow_version'] = workflow.version
    @dry_run_result[:variables_snapshot]['_dry_run'] = true
    @dry_run_result[:variables_snapshot]['_user_id'] = user.id
    @dry_run_result[:variables_snapshot]['_started_at'] = @dry_run_result[:started_at].iso8601
  end

  def simulate_execution_path
    visited_nodes = Set.new
    execution_queue = workflow.start_nodes.to_a

    while execution_queue.any?
      current_node = execution_queue.shift

      # Prevent infinite loops in simulation
      if visited_nodes.include?(current_node.node_id)
        @dry_run_result[:warnings] << "Possible infinite loop detected at node '#{current_node.name}'"
        break
      end

      visited_nodes.add(current_node.node_id)

      # Simulate node execution
      node_result = simulate_node_execution(current_node)
      @dry_run_result[:nodes_executed] << node_result
      @dry_run_result[:execution_path] << current_node.node_id

      # Find next nodes based on outgoing edges
      next_nodes = find_next_nodes(current_node, node_result)
      execution_queue.concat(next_nodes)

      # Stop if we hit an end node
      break if current_node.is_end_node
    end
  end

  def simulate_node_execution(node)
    node_result = {
      node_id: node.node_id,
      node_type: node.node_type,
      name: node.name,
      simulated_at: Time.current.iso8601,
      estimated_duration_ms: estimate_node_duration(node),
      estimated_cost: estimate_node_cost(node),
      inputs: extract_node_inputs(node),
      outputs: generate_mock_outputs(node),
      status: 'simulated'
    }

    # Update variables with mock outputs
    if node_result[:outputs].present?
      @dry_run_result[:variables_snapshot].merge!(node_result[:outputs])
    end

    node_result
  end

  def estimate_node_duration(node)
    # Estimate based on node type
    case node.node_type
    when 'ai_agent'
      node.configuration['estimated_duration'] || 5000 # 5 seconds default
    when 'api_call'
      node.configuration['timeout'] || 3000 # 3 seconds default
    when 'condition', 'transform'
      100 # Very fast
    when 'delay'
      node.configuration['delay_ms'] || 1000
    when 'database'
      500 # Database query
    else
      1000 # Generic default
    end
  end

  def estimate_node_cost(node)
    # Estimate cost for AI nodes
    case node.node_type
    when 'ai_agent'
      # Rough estimate: $0.01 per agent execution
      0.01
    when 'api_call'
      # External API might have costs
      node.configuration['estimated_cost']&.to_f || 0.0
    else
      0.0
    end
  end

  def extract_node_inputs(node)
    inputs = {}

    # Extract input mappings from configuration
    input_mappings = node.configuration['inputs'] || node.configuration['input_mapping'] || {}

    input_mappings.each do |key, variable_name|
      inputs[key] = @dry_run_result[:variables_snapshot][variable_name]
    end

    inputs
  end

  def generate_mock_outputs(node)
    # Generate appropriate mock data based on node type
    case node.node_type
    when 'ai_agent'
      {
        "#{node.node_id}_output" => "[DRY RUN] Simulated AI agent response",
        "#{node.node_id}_tokens_used" => 150,
        "#{node.node_id}_model" => node.configuration['model'] || 'unknown'
      }
    when 'api_call'
      {
        "#{node.node_id}_response" => { status: 'success', data: '[DRY RUN] Simulated API response' },
        "#{node.node_id}_status_code" => 200
      }
    when 'transform'
      {
        "#{node.node_id}_result" => "[DRY RUN] Transformed data"
      }
    when 'condition'
      {
        "#{node.node_id}_condition_result" => true
      }
    else
      {
        "#{node.node_id}_output" => "[DRY RUN] Simulated output"
      }
    end
  end

  def find_next_nodes(current_node, node_result)
    next_nodes = []

    outgoing_edges = workflow.ai_workflow_edges.where(source_node_id: current_node.node_id)

    outgoing_edges.each do |edge|
      # For conditional edges, evaluate condition in dry-run mode
      if edge.is_conditional
        # In dry-run, we take all branches to see full potential paths
        next_nodes << workflow.ai_workflow_nodes.find_by(node_id: edge.target_node_id)
      else
        next_nodes << workflow.ai_workflow_nodes.find_by(node_id: edge.target_node_id)
      end
    end

    next_nodes.compact
  end

  def calculate_estimates
    @dry_run_result[:estimated_duration_ms] = @dry_run_result[:nodes_executed].sum { |n| n[:estimated_duration_ms] }
    @dry_run_result[:estimated_cost] = @dry_run_result[:nodes_executed].sum { |n| n[:estimated_cost] }

    @dry_run_result[:summary] = {
      total_nodes: @dry_run_result[:nodes_executed].count,
      ai_agent_nodes: @dry_run_result[:nodes_executed].count { |n| n[:node_type] == 'ai_agent' },
      api_call_nodes: @dry_run_result[:nodes_executed].count { |n| n[:node_type] == 'api_call' },
      estimated_duration_seconds: (@dry_run_result[:estimated_duration_ms] / 1000.0).round(2),
      estimated_cost_usd: @dry_run_result[:estimated_cost].round(4)
    }
  end
end
