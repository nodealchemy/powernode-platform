# frozen_string_literal: true

module AiWorkflowNode::NodeTypes
  extend ActiveSupport::Concern

  # Node type check methods
  def ai_agent_node?
    node_type == "ai_agent"
  end

  def api_call_node?
    node_type == "api_call"
  end

  def webhook_node?
    node_type == "webhook"
  end

  def condition_node?
    node_type == "condition"
  end

  def loop_node?
    node_type == "loop"
  end

  def transform_node?
    node_type == "transform"
  end

  def delay_node?
    node_type == "delay"
  end

  def human_approval_node?
    node_type == "human_approval"
  end

  def sub_workflow_node?
    node_type == "sub_workflow"
  end

  def merge_node?
    node_type == "merge"
  end

  def split_node?
    node_type == "split"
  end

  def start_node?
    node_type == "start"
  end

  def end_node?
    node_type == "end"
  end

  def trigger_node?
    node_type == "trigger"
  end

  # Consolidated node type check methods
  def kb_article_node?
    node_type == "kb_article"
  end

  def page_node?
    node_type == "page"
  end

  def mcp_operation_node?
    node_type == "mcp_operation"
  end

  # Action/operation type helpers for consolidated nodes
  def kb_article_action
    return nil unless kb_article_node?

    configuration["action"]
  end

  def page_action
    return nil unless page_node?

    configuration["action"]
  end

  def mcp_operation_type
    return nil unless mcp_operation_node?

    configuration["operation_type"]
  end
end
