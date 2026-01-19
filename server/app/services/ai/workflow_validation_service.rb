# frozen_string_literal: true

class Ai::WorkflowValidationService
  attr_reader :workflow, :issues, :validated_nodes

  def initialize(workflow)
    @workflow = workflow
    @issues = []
    @validated_nodes = 0
    @start_time = Time.current
  end

  def validate
    perform_structural_validation
    perform_connectivity_validation
    perform_node_configuration_validation

    {
      total_nodes: nodes.size,
      validated_nodes: @validated_nodes,
      issues: @issues,
      overall_status: determine_overall_status,
      health_score: calculate_health_score,
      validation_duration_ms: ((Time.current - @start_time) * 1000).round
    }
  end

  private

  def nodes
    @nodes ||= workflow.nodes.to_a
  end

  def edges
    @edges ||= workflow.edges.to_a
  end

  def perform_structural_validation
    if nodes.empty?
      add_issue(
        code: "empty_workflow",
        severity: "error",
        category: "structural",
        message: "Workflow has no nodes",
        suggestion: "Add at least one node to the workflow"
      )
      return
    end

    start_nodes = nodes.select { |n| n.node_type == "trigger" || n.metadata&.dig("is_start") }
    if start_nodes.empty?
      add_issue(
        code: "missing_start_node",
        severity: "error",
        category: "structural",
        message: "No start node found in workflow",
        suggestion: "Add a trigger or mark a node as the start node"
      )
    elsif start_nodes.size > 1
      add_issue(
        code: "multiple_start_nodes",
        severity: "error",
        category: "structural",
        message: "Multiple start nodes found in workflow",
        suggestion: "Ensure only one node is marked as the start node"
      )
    end

    end_nodes = nodes.select { |n| n.node_type == "end" }
    if end_nodes.empty?
      add_issue(
        code: "missing_end_node",
        severity: "warning",
        category: "structural",
        message: "No explicit end node found",
        suggestion: "Consider adding an end node for clarity"
      )
    end

    @validated_nodes = nodes.size
  end

  def perform_connectivity_validation
    return if nodes.empty?

    # Build adjacency list
    adjacency = Hash.new { |h, k| h[k] = [] }
    edges.each do |edge|
      adjacency[edge.source_node_id] << edge.target_node_id
    end

    # Find nodes with no incoming edges (potential start nodes)
    nodes_with_incoming = edges.map(&:target_node_id).uniq
    orphaned_nodes = nodes.reject do |node|
      node.node_type == "trigger" ||
        node.metadata&.dig("is_start") ||
        nodes_with_incoming.include?(node.node_id)
    end

    orphaned_nodes.each do |node|
      add_issue(
        code: "orphaned_node",
        severity: "warning",
        category: "connectivity",
        node_id: node.id,
        node_name: node.name,
        message: "Node '#{node.name}' is not connected to the workflow",
        suggestion: "Connect this node to the workflow or remove it",
        auto_fixable: true
      )
    end

    # Check for nodes with no outgoing connections (except end nodes)
    nodes_with_outgoing = edges.map(&:source_node_id).uniq
    dead_end_nodes = nodes.reject do |node|
      node.node_type == "end" ||
        nodes_with_outgoing.include?(node.node_id)
    end

    dead_end_nodes.each do |node|
      # Trigger nodes without output are always an error
      if node.node_type == "trigger"
        add_issue(
          code: "trigger_no_output",
          severity: "error",
          category: "connectivity",
          node_id: node.id,
          node_name: node.name,
          message: "Trigger node '#{node.name}' has no outgoing connections",
          suggestion: "Connect the trigger to at least one downstream node"
        )
        next
      end

      add_issue(
        code: "dead_end_node",
        severity: "info",
        category: "connectivity",
        node_id: node.id,
        node_name: node.name,
        message: "Node '#{node.name}' has no outgoing connections",
        suggestion: "Consider connecting this node to other nodes or adding an end node"
      )
    end
  end

  def perform_node_configuration_validation
    nodes.each do |node|
      case node.node_type
      when "ai_agent"
        validate_ai_agent_node(node)
      when "api_call", "http_request"
        validate_api_call_node(node)
      when "condition"
        validate_condition_node(node)
      when "loop"
        validate_loop_node(node)
      when "human_approval"
        validate_human_approval_node(node)
      end
    end
  end

  def validate_ai_agent_node(node)
    config = node.configuration || {}

    unless config["agent_id"].present?
      add_issue(
        code: "missing_agent",
        severity: "error",
        category: "configuration",
        node_id: node.id,
        node_name: node.name,
        message: "No AI agent selected for node '#{node.name}'",
        suggestion: "Select an AI agent from the configuration panel"
      )
    end

    unless config["prompt"].present?
      add_issue(
        code: "missing_prompt",
        severity: "error",
        category: "configuration",
        node_id: node.id,
        node_name: node.name,
        message: "No prompt configured for node '#{node.name}'",
        suggestion: "Add a prompt to instruct the AI agent"
      )
    end

    unless config["timeout_seconds"].present?
      add_issue(
        code: "missing_timeout",
        severity: "warning",
        category: "configuration",
        node_id: node.id,
        node_name: node.name,
        message: "No timeout specified for node '#{node.name}'",
        suggestion: "Set a reasonable timeout value (e.g., 120 seconds)",
        auto_fixable: true,
        metadata: { recommended_timeout: 120 }
      )
    end
  end

  def validate_api_call_node(node)
    config = node.configuration || {}

    unless config["url"].present?
      add_issue(
        code: "missing_url",
        severity: "error",
        category: "configuration",
        node_id: node.id,
        node_name: node.name,
        message: "No URL configured for node '#{node.name}'",
        suggestion: "Add a URL for the API call"
      )
    end

    unless config["method"].present?
      add_issue(
        code: "missing_method",
        severity: "error",
        category: "configuration",
        node_id: node.id,
        node_name: node.name,
        message: "No HTTP method specified for node '#{node.name}'",
        suggestion: "Select an HTTP method (GET, POST, PUT, DELETE, etc.)"
      )
    end
  end

  def validate_condition_node(node)
    config = node.configuration || {}

    unless config["conditions"].is_a?(Array) && config["conditions"].any?
      add_issue(
        code: "missing_conditions",
        severity: "error",
        category: "configuration",
        node_id: node.id,
        node_name: node.name,
        message: "No conditions defined for node '#{node.name}'",
        suggestion: "Add at least one condition to evaluate"
      )
    end
  end

  def validate_loop_node(node)
    config = node.configuration || {}

    unless config["iteration_source"].present?
      add_issue(
        code: "missing_iteration_source",
        severity: "error",
        category: "configuration",
        node_id: node.id,
        node_name: node.name,
        message: "No iteration source specified for node '#{node.name}'",
        suggestion: "Specify what to iterate over"
      )
    end

    unless config["max_iterations"].present?
      add_issue(
        code: "missing_max_iterations",
        severity: "warning",
        category: "configuration",
        node_id: node.id,
        node_name: node.name,
        message: "No max iterations specified for node '#{node.name}'",
        suggestion: "Set a maximum number of iterations to prevent infinite loops",
        auto_fixable: true,
        metadata: { recommended_max_iterations: 100 }
      )
    end
  end

  def validate_human_approval_node(node)
    config = node.configuration || {}

    unless config["approvers"].is_a?(Array) && config["approvers"].any?
      add_issue(
        code: "missing_approvers",
        severity: "error",
        category: "configuration",
        node_id: node.id,
        node_name: node.name,
        message: "No approvers defined for node '#{node.name}'",
        suggestion: "Add at least one approver for this node"
      )
    end
  end

  def add_issue(code:, severity:, category:, message:, suggestion: nil, node_id: nil, node_name: nil, auto_fixable: false, metadata: nil)
    @issues << {
      code: code,
      severity: severity,
      category: category,
      message: message,
      suggestion: suggestion,
      node_id: node_id,
      node_name: node_name,
      auto_fixable: auto_fixable,
      metadata: metadata
    }.compact
  end

  def determine_overall_status
    return "valid" if @issues.empty?
    return "invalid" if @issues.any? { |i| i[:severity] == "error" }
    return "warning" if @issues.any? { |i| i[:severity] == "warning" }
    "valid"
  end

  def calculate_health_score
    base_score = 100
    penalties = {
      "error" => 15,
      "warning" => 5,
      "info" => 2
    }

    total_penalty = @issues.sum { |issue| penalties[issue[:severity]] || 0 }
    [ base_score - total_penalty, 0 ].max
  end
end
