# frozen_string_literal: true

module Ai
  class KnowledgeBase < ApplicationRecord
    self.table_name = "ai_knowledge_bases"

    # Associations
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    has_many :documents, class_name: "Ai::Document", foreign_key: :knowledge_base_id, dependent: :destroy
    has_many :document_chunks, class_name: "Ai::DocumentChunk", foreign_key: :knowledge_base_id, dependent: :destroy
    has_many :rag_queries, class_name: "Ai::RagQuery", foreign_key: :knowledge_base_id, dependent: :destroy
    has_many :data_connectors, class_name: "Ai::DataConnector", foreign_key: :knowledge_base_id, dependent: :destroy
    has_many :knowledge_graph_nodes, class_name: "Ai::KnowledgeGraphNode", foreign_key: :knowledge_base_id, dependent: :nullify

    # Validations
    validates :name, presence: true
    validates :name, uniqueness: { scope: :account_id }
    validates :status, inclusion: { in: %w[active indexing paused archived error] }
    validates :embedding_model, presence: true
    validates :embedding_provider, presence: true
    validates :chunking_strategy, inclusion: { in: %w[recursive semantic fixed sentence paragraph custom] }
    validates :chunk_size, numericality: { greater_than: 0 }, allow_nil: true
    validates :chunk_overlap, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :public_bases, -> { where(is_public: true) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }

    # Status transitions
    def start_indexing!
      update!(status: "indexing")
    end

    def complete_indexing!
      update!(status: "active", last_indexed_at: Time.current)
    end

    def pause!
      update!(status: "paused")
    end

    def archive!
      update!(status: "archived")
    end

    def mark_error!(message = nil)
      update!(status: "error", settings: settings.merge("error_message" => message))
    end

    # Stats
    def update_stats!
      update!(
        document_count: documents.count,
        chunk_count: document_chunks.count,
        total_tokens: document_chunks.sum(:token_count),
        storage_bytes: documents.sum(:content_size_bytes)
      )
    end

    def record_query!
      touch(:last_queried_at)
    end
  end
end
