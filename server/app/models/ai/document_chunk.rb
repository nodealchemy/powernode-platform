# frozen_string_literal: true

module Ai
  class DocumentChunk < ApplicationRecord
    self.table_name = "ai_document_chunks"

    has_neighbors :embedding

    # Associations
    belongs_to :document, class_name: "Ai::Document", foreign_key: "document_id"
    belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase", foreign_key: "knowledge_base_id"

    # Delegate account access
    delegate :account, to: :knowledge_base

    # Validations
    validates :sequence_number, presence: true
    validates :sequence_number, uniqueness: { scope: :document_id }
    validates :content, presence: true

    # Scopes
    scope :with_embeddings, -> { where.not(embedding: nil) }
    scope :without_embeddings, -> { where(embedding: nil) }
    scope :ordered, -> { order(:sequence_number) }
    scope :for_knowledge_base, ->(kb_id) { where(knowledge_base_id: kb_id) }

    # Set embedding
    def set_embedding!(embedding_vector, model_name)
      update!(
        embedding: embedding_vector,
        embedding_model: model_name,
        embedded_at: Time.current
      )
    end

    # Check if embedded
    def embedded?
      embedding.present? && embedded_at.present?
    end

    # Get content preview
    def preview(max_length = 200)
      content.truncate(max_length)
    end

    # Calculate cosine similarity with another embedding using pgvector via neighbor gem
    def similarity_with(other_embedding)
      return 0.0 if embedding.blank? || other_embedding.blank?

      result = self.class.where(id: id)
        .nearest_neighbors(:embedding, other_embedding, distance: "cosine")
        .first
      return 0.0 unless result

      1.0 - (result.neighbor_distance || 1.0)
    end
  end
end
