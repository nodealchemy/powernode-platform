# frozen_string_literal: true

# AiWorkflowAutoFixService
#
# Automatically fixes common workflow validation issues.
# Supports both full auto-fix (all fixable issues) and targeted fixes.
#
# Fixable Issues:
# - missing_start_node: Mark first node as start
# - missing_timeout: Apply default timeout values
# - missing_max_iterations: Apply default max iterations
# - missing_approval_timeout: Apply default approval timeout
# - orphaned_node: Connect to nearest compatible node
# - missing_configuration: Apply node-type defaults
#
# @example Full auto-fix
#   service = AiWorkflowAutoFixService.new(workflow)
#   result = service.fix_all
#   # => { fixed_count: 3, remaining_issues: [...], workflow: <updated_workflow> }
#
# @example Targeted fix
#   service = AiWorkflowAutoFixService.new(workflow)
#   result = service.fix_issue('missing_start_node')
#   # => { success: true, message: 'Fixed missing_start_node', workflow: <updated_workflow> }
#
class AiWorkflowAutoFixService
  attr_reader :workflow, :fixes_applied, :errors

  def initialize(workflow)
    @workflow = workflow
    @fixes_applied = []
    @errors = []
  end

  # Fix all auto-fixable issues in the workflow
  #
  # @return [Hash] Result with:
  #   - fixed_count [Integer]
  #   - fixes_applied [Array<Hash>]
  #   - remaining_issues [Array<Hash>]
  #   - workflow [Ai::Workflow]
  #   - errors [Array<String>]
  def fix_all
    # Run validation to get current issues
    validation_service = AiWorkflowValidationService.new(workflow)
    validation_result = validation_service.validate

    auto_fixable_issues = validation_result[:issues].select { |issue| issue[:auto_fixable] }

    # Group issues by code to avoid duplicate fixes
    issues_by_code = auto_fixable_issues.group_by { |issue| issue[:code] }

    # Fix each unique issue type
    issues_by_code.each do |code, issues|
      fix_issue_code(code, issues.first)
    end

    # Re-validate to get remaining issues
    validation_service = AiWorkflowValidationService.new(workflow.reload)
    updated_validation = validation_service.validate

    {
      fixed_count: @fixes_applied.size,
      fixes_applied: @fixes_applied,
      remaining_issues: updated_validation[:issues],
      workflow: workflow,
      errors: @errors,
      health_score_improvement: calculate_improvement(validation_result, updated_validation)
    }
  end

  # Fix a specific issue by code
  #
  # @param issue_code [String] The issue code to fix
  # @param node_id [String, nil] Optional node ID for node-specific fixes
  # @return [Hash] Result with success status and message
  def fix_issue(issue_code, node_id: nil)
    # Run validation to find the issue
    validation_service = AiWorkflowValidationService.new(workflow)
    validation_result = validation_service.validate

    issue = if node_id
              validation_result[:issues].find { |i| i[:code] == issue_code && i[:node_id] == node_id }
    else
              validation_result[:issues].find { |i| i[:code] == issue_code }
    end

    unless issue
      return {
        success: false,
        message: "Issue '#{issue_code}' not found in workflow"
      }
    end

    unless issue[:auto_fixable]
      return {
        success: false,
        message: "Issue '#{issue_code}' is not auto-fixable"
      }
    end

    result = fix_issue_code(issue_code, issue)

    {
      success: result,
      message: result ? "Fixed #{issue_code}" : "Failed to fix #{issue_code}",
      workflow: workflow,
      fixes_applied: @fixes_applied,
      errors: @errors
    }
  end

  # Preview what fixes would be applied without actually applying them
  #
  # @return [Hash] Preview result with planned fixes
  def preview_fixes
    validation_service = AiWorkflowValidationService.new(workflow)
    validation_result = validation_service.validate

    auto_fixable_issues = validation_result[:issues].select { |issue| issue[:auto_fixable] }

    planned_fixes = auto_fixable_issues.map do |issue|
      {
        issue_code: issue[:code],
        issue_message: issue[:message],
        node_id: issue[:node_id],
        node_name: issue[:node_name],
        fix_description: get_fix_description(issue[:code]),
        estimated_improvement: get_estimated_improvement(issue)
      }
    end

    {
      fixable_count: auto_fixable_issues.size,
      planned_fixes: planned_fixes,
      estimated_health_score_improvement: planned_fixes.sum { |f| f[:estimated_improvement] }
    }
  end

  private

  # ==========================================
  # Fix Implementations
  # ==========================================

  def fix_issue_code(code, issue)
    case code
    when "missing_start_node"
      fix_missing_start_node
    when "missing_timeout", "missing_approval_timeout"
      fix_missing_timeout(issue)
    when "missing_max_iterations"
      fix_missing_max_iterations(issue)
    when "orphaned_node"
      fix_orphaned_node(issue)
    when "missing_configuration"
      fix_missing_configuration(issue)
    else
      log_error("No auto-fix implementation for issue code: #{code}")
      false
    end
  end

  def fix_missing_start_node
    nodes = workflow.workflow_nodes.includes(:target_edges)

    # Find nodes with no incoming edges (potential start nodes)
    candidate_nodes = nodes.select { |n| n.target_edges.empty? && !n.is_start_node }

    return log_error("No candidate nodes found for start node") if candidate_nodes.empty?

    # Mark the first candidate as start node
    start_node = candidate_nodes.first
    start_node.update!(is_start_node: true)

    log_fix("missing_start_node", "Marked '#{start_node.name}' as start node")
    true
  rescue => e
    log_error("Failed to fix missing_start_node: #{e.message}")
    false
  end

  def fix_missing_timeout(issue)
    return false unless issue[:node_id]

    node = workflow.workflow_nodes.find_by(id: issue[:node_id])
    return log_error("Node not found: #{issue[:node_id]}") unless node

    # Determine appropriate timeout based on node type
    default_timeout = case node.node_type
    when "ai_agent"
                        120 # 2 minutes for AI agents
    when "api_call", "http_request", "webhook"
                        30 # 30 seconds for API calls
    when "human_approval"
                        86400 # 1 day for human approval
    else
                        60 # 1 minute default
    end

    # Get recommended timeout from issue metadata if available
    recommended_timeout = issue.dig(:metadata, :recommended_timeout) || default_timeout

    # Update configuration
    config = node.configuration || {}
    timeout_key = node.node_type == "human_approval" ? "approval_timeout_seconds" : "timeout_seconds"
    config[timeout_key] = recommended_timeout
    node.update!(configuration: config)

    log_fix(issue[:code], "Set timeout to #{recommended_timeout}s for '#{node.name}'")
    true
  rescue => e
    log_error("Failed to fix #{issue[:code]}: #{e.message}")
    false
  end

  def fix_missing_max_iterations(issue)
    return false unless issue[:node_id]

    node = workflow.workflow_nodes.find_by(id: issue[:node_id])
    return log_error("Node not found: #{issue[:node_id]}") unless node

    recommended_max = issue.dig(:metadata, :recommended_max_iterations) || 1000

    config = node.configuration || {}
    config["max_iterations"] = recommended_max
    node.update!(configuration: config)

    log_fix("missing_max_iterations", "Set max_iterations to #{recommended_max} for '#{node.name}'")
    true
  rescue => e
    log_error("Failed to fix missing_max_iterations: #{e.message}")
    false
  end

  def fix_orphaned_node(issue)
    return false unless issue[:node_id]

    orphaned_node = workflow.workflow_nodes.find_by(id: issue[:node_id])
    return log_error("Node not found: #{issue[:node_id]}") unless orphaned_node

    # Find start node or first node
    start_node = workflow.workflow_nodes.find_by(is_start_node: true) ||
                 workflow.workflow_nodes.where(node_type: "trigger").first ||
                 workflow.workflow_nodes.order(:created_at).first

    return log_error("No start node found to connect to") if start_node.nil? || start_node.id == orphaned_node.id

    # Create edge from start node to orphaned node
    edge = workflow.workflow_edges.create!(
      edge_id: SecureRandom.uuid,
      source_node_id: start_node.id,
      target_node_id: orphaned_node.id,
      edge_type: "default",
      metadata: { auto_created: true, created_by: "auto_fix" }
    )

    log_fix("orphaned_node", "Connected '#{orphaned_node.name}' to '#{start_node.name}'")
    true
  rescue => e
    log_error("Failed to fix orphaned_node: #{e.message}")
    false
  end

  def fix_missing_configuration(issue)
    return false unless issue[:node_id]

    node = workflow.workflow_nodes.find_by(id: issue[:node_id])
    return log_error("Node not found: #{issue[:node_id]}") unless node

    # Apply default configuration based on node type
    default_config = get_default_configuration(node.node_type)
    node.update!(configuration: default_config)

    log_fix("missing_configuration", "Applied default configuration for '#{node.name}'")
    true
  rescue => e
    log_error("Failed to fix missing_configuration: #{e.message}")
    false
  end

  # ==========================================
  # Helpers
  # ==========================================

  def get_default_configuration(node_type)
    case node_type
    when "ai_agent"
      {
        "prompt" => "Enter your prompt here",
        "temperature" => 0.7,
        "max_tokens" => 1000
      }
    when "api_call", "http_request"
      {
        "url" => "https://api.example.com/endpoint",
        "method" => "GET",
        "headers" => {}
      }
    when "condition"
      {
        "conditions" => [],
        "has_default_branch" => true
      }
    when "loop"
      {
        "iteration_source" => "array",
        "max_iterations" => 1000
      }
    when "delay"
      {
        "delay_seconds" => 60
      }
    when "transform"
      {
        "transformations" => []
      }
    else
      {}
    end
  end

  def get_fix_description(issue_code)
    descriptions = {
      "missing_start_node" => "Mark the first unconnected node as the workflow start",
      "missing_timeout" => "Set a reasonable timeout value based on node type",
      "missing_max_iterations" => "Set a safe maximum iteration limit to prevent infinite loops",
      "missing_approval_timeout" => "Set a default approval timeout to prevent indefinite waits",
      "orphaned_node" => "Connect the orphaned node to the workflow start",
      "missing_configuration" => "Apply default configuration for the node type"
    }

    descriptions[issue_code] || "Apply automatic fix"
  end

  def get_estimated_improvement(issue)
    improvements = {
      "error" => 15,
      "warning" => 5,
      "info" => 2
    }

    improvements[issue[:severity]] || 0
  end

  def calculate_improvement(before, after)
    before[:health_score] - after[:health_score]
  end

  def log_fix(code, message)
    @fixes_applied << {
      code: code,
      message: message,
      timestamp: Time.current
    }
  end

  def log_error(message)
    @errors << message
    Rails.logger.error("[AiWorkflowAutoFixService] #{message}")
    false
  end
end
