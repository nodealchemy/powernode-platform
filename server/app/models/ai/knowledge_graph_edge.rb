# frozen_string_literal: true

module Ai
  class KnowledgeGraphEdge < ApplicationRecord
    self.table_name = "ai_knowledge_graph_edges"

    RELATION_TYPES = %w[
      is_a has_a part_of related_to depends_on
      created_by used_by located_in similar_to
      causes precedes follows custom
    ].freeze

    # Associations
    belongs_to :account
    belongs_to :source_node, class_name: "Ai::KnowledgeGraphNode"
    belongs_to :target_node, class_name: "Ai::KnowledgeGraphNode"
    belongs_to :source_document, class_name: "Ai::Document", optional: true

    # Validations
    validates :relation_type, presence: true, inclusion: { in: RELATION_TYPES }
    validates :weight, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
    validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :by_relation, ->(type) { where(relation_type: type) }
    scope :bidirectional_edges, -> { where(bidirectional: true) }
    scope :for_node, ->(node_id) { where("source_node_id = ? OR target_node_id = ?", node_id, node_id) }

    # Get the opposite node from a given node perspective
    def opposite_node(from_node_id)
      from_node_id == source_node_id ? target_node : source_node
    end

    # Combined score (weight * confidence)
    def combined_score
      (weight || 1.0) * (confidence || 1.0)
    end
  end
end
