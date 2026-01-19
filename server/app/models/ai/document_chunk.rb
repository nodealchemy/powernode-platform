# frozen_string_literal: true

module Ai
  class DocumentChunk < ApplicationRecord
    self.table_name = "ai_document_chunks"

    # Associations
    belongs_to :document, class_name: "Ai::Document"
    belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase"

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

    # Calculate similarity with another embedding (cosine similarity)
    def similarity_with(other_embedding)
      return 0.0 if embedding.blank? || other_embedding.blank?

      emb = embedding.is_a?(Array) ? embedding : JSON.parse(embedding.to_json)
      other = other_embedding.is_a?(Array) ? other_embedding : JSON.parse(other_embedding.to_json)

      dot_product = emb.zip(other).sum { |a, b| a * b }
      magnitude_a = Math.sqrt(emb.sum { |x| x**2 })
      magnitude_b = Math.sqrt(other.sum { |x| x**2 })

      return 0.0 if magnitude_a.zero? || magnitude_b.zero?

      dot_product / (magnitude_a * magnitude_b)
    end
  end
end
