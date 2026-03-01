# frozen_string_literal: true

module Ai
  class RagQuery < ApplicationRecord
    self.table_name = "ai_rag_queries"

    has_neighbors :query_embedding

    # Associations
    belongs_to :account
    belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase", foreign_key: "knowledge_base_id"
    belongs_to :user, optional: true

    # Validations
    validates :query_text, presence: true
    validates :status, inclusion: { in: %w[pending processing completed failed] }
    validates :retrieval_strategy, inclusion: { in: %w[similarity hybrid rerank keyword] }, allow_nil: true
    validates :top_k, numericality: { greater_than: 0 }, allow_nil: true
    validates :similarity_threshold, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

    # Scopes
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }

    # Status transitions
    def start_processing!
      update!(status: "processing")
    end

    def complete!(chunks:, latency_ms:)
      avg_score = chunks.any? ? chunks.sum { |c| c[:score] || 0 } / chunks.size : nil

      update!(
        status: "completed",
        retrieved_chunks: chunks,
        chunks_retrieved: chunks.size,
        avg_similarity_score: avg_score,
        query_latency_ms: latency_ms
      )
    end

    def mark_failed!(reason = nil)
      update!(
        status: "failed",
        metadata: metadata.merge("failure_reason" => reason)
      )
    end

    # Set query embedding
    def set_embedding!(embedding_vector)
      update!(query_embedding: embedding_vector)
    end

    # Analytics helpers
    def successful?
      status == "completed" && chunks_retrieved.to_i > 0
    end

    def quality_score
      return nil unless avg_similarity_score.present?

      (avg_similarity_score * 100).round(2)
    end
  end
end
