# frozen_string_literal: true

module Ai
  class KnowledgeGraphNode < ApplicationRecord
    self.table_name = "ai_knowledge_graph_nodes"

    has_neighbors :embedding

    NODE_TYPES = %w[entity concept relation attribute].freeze
    ENTITY_TYPES = %w[person organization technology event location skill agent team custom].freeze
    STATUSES = %w[active merged archived].freeze

    # Associations
    belongs_to :account
    belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase", foreign_key: "knowledge_base_id", optional: true
    belongs_to :source_document, class_name: "Ai::Document", foreign_key: "source_document_id", optional: true
    belongs_to :merged_into, class_name: "Ai::KnowledgeGraphNode", foreign_key: "merged_into_id", optional: true
    belongs_to :skill, class_name: "Ai::Skill", foreign_key: "ai_skill_id", optional: true

    has_many :outgoing_edges, class_name: "Ai::KnowledgeGraphEdge", foreign_key: :source_node_id, dependent: :destroy
    has_many :incoming_edges, class_name: "Ai::KnowledgeGraphEdge", foreign_key: :target_node_id, dependent: :destroy
    has_many :merged_nodes, class_name: "Ai::KnowledgeGraphNode", foreign_key: :merged_into_id

    # Validations
    validates :name, presence: true
    validates :node_type, presence: true, inclusion: { in: NODE_TYPES }
    validates :entity_type, inclusion: { in: ENTITY_TYPES }, allow_nil: true
    validates :status, inclusion: { in: STATUSES }
    validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
    validates :mention_count, numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :by_type, ->(type) { where(node_type: type) }
    scope :by_entity_type, ->(type) { where(entity_type: type) }
    scope :with_embeddings, -> { where.not(embedding: nil) }
    scope :for_knowledge_base, ->(kb_id) { where(knowledge_base_id: kb_id) }
    scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{sanitize_sql_like(query)}%") }
    scope :skill_nodes, -> { where(entity_type: "skill") }
    scope :for_skill, ->(skill_id) { where(ai_skill_id: skill_id) }

    # Get all edges (both incoming and outgoing)
    def edges
      Ai::KnowledgeGraphEdge.where("source_node_id = ? OR target_node_id = ?", id, id)
    end

    # Get all connected nodes (neighbors)
    def connected_nodes
      node_ids = outgoing_edges.pluck(:target_node_id) + incoming_edges.pluck(:source_node_id)
      self.class.where(id: node_ids.uniq)
    end

    # Increment mention count
    def record_mention!
      update!(mention_count: mention_count + 1, last_seen_at: Time.current)
    end

    # Mark as merged into another node
    def merge_into!(target_node)
      update!(status: "merged", merged_into_id: target_node.id)
    end

    # Archive the node
    def archive!
      update!(status: "archived")
    end

    # Set embedding
    def set_embedding!(embedding_vector)
      update!(embedding: embedding_vector)
    end

    # Virtual attribute set by pgvector's nearest_neighbors scope
    def neighbor_distance
      self[:neighbor_distance]
    end

    # Degree (number of connections)
    def degree
      outgoing_edges.count + incoming_edges.count
    end
  end
end
