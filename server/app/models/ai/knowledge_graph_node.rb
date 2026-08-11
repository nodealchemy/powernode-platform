# frozen_string_literal: true

module Ai
  class KnowledgeGraphNode < ApplicationRecord
    self.table_name = "ai_knowledge_graph_nodes"

    has_neighbors :embedding

    # "content" is deliberately NOT "entity". (account_id, name, node_type) is
    # uniquely indexed over active rows, so giving pages/articles their own
    # node_type moves free-form content TITLES out of the namespace that skills,
    # agents and teams share — the collision becomes structurally impossible
    # rather than avoided by a naming convention, and it needs no migration.
    NODE_TYPES = %w[entity concept relation attribute code_entity content].freeze
    ENTITY_TYPES = %w[
      person organization technology event location skill agent team custom
      file directory class module method function variable type_definition interface constant
      data_source
      page article
    ].freeze
    STATUSES = %w[active merged archived].freeze

    # Associations
    belongs_to :account
    belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase", foreign_key: "knowledge_base_id", optional: true
    belongs_to :source_document, class_name: "Ai::Document", foreign_key: "source_document_id", optional: true
    belongs_to :merged_into, class_name: "Ai::KnowledgeGraphNode", foreign_key: "merged_into_id", optional: true
    belongs_to :skill, class_name: "Ai::Skill", foreign_key: "ai_skill_id", optional: true
    belongs_to :data_source, class_name: "Ai::DataSource", foreign_key: "ai_data_source_id", optional: true

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
    scope :data_source_nodes, -> { where(entity_type: "data_source") }
    scope :for_data_source, ->(id) { where(ai_data_source_id: id) }
    scope :code_entities, -> { where(node_type: "code_entity") }
    scope :for_project, ->(kb_id) { code_entities.for_knowledge_base(kb_id) }

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

    # Exponential confidence decay based on last_seen_at age, floor at 0.05
    def decay_confidence!
      return if decay_rate.nil? || decay_rate.zero?
      return if confidence.nil?

      reference = last_seen_at || updated_at
      days_since = ((Time.current - reference) / 1.day).to_i
      return if days_since < 1

      decayed = confidence * ((1 - decay_rate) ** days_since)
      update!(confidence: [decayed, 0.05].max)
    end

    # Recalculate quality score based on confidence, mention count, and connections
    def recalculate_quality_score!
      confidence_factor = confidence || 0.5
      mention_factor = [Math.log10(mention_count + 1) / 3.0, 1.0].min
      connection_factor = [degree / 20.0, 1.0].min

      new_score = (
        confidence_factor * 0.50 +
        mention_factor * 0.30 +
        connection_factor * 0.20
      ).round(4)

      update!(
        quality_score: [new_score, 1.0].min,
        last_quality_recalc_at: Time.current,
        # Embedding-independent freshness signal: the daily quality recalc keeps
        # event_processed_24h reflecting ongoing pipeline health (not just new
        # embeddings). Single atomic write — no extra query.
        last_event_processed_at: Time.current
      )
    end
  end
end
