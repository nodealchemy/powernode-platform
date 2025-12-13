# frozen_string_literal: true

module AiWorkflowNode::Positioning
  extend ActiveSupport::Concern

  def update_position(x, y)
    update!(position: position.merge({ x: x, y: y }))
  end

  def distance_to(other_node)
    return Float::INFINITY unless other_node.is_a?(AiWorkflowNode)

    dx = position["x"] - other_node.position["x"]
    dy = position["y"] - other_node.position["y"]
    Math.sqrt(dx * dx + dy * dy)
  end
end
