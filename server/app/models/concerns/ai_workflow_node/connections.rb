# frozen_string_literal: true

module AiWorkflowNode::Connections
  extend ActiveSupport::Concern

  def can_execute?
    configuration.present? && valid_configuration_for_type?
  end

  def next_nodes
    source_edges.includes(:target_node).map(&:target_node)
  end

  def previous_nodes
    target_edges.includes(:source_node).map(&:source_node)
  end

  def has_conditions?
    source_edges.where(is_conditional: true).any?
  end

  def error_handler_node
    return nil unless error_node_id.present?

    ai_workflow.ai_workflow_nodes.find_by(node_id: error_node_id)
  end
end
