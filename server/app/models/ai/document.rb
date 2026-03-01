# frozen_string_literal: true

module Ai
  class Document < ApplicationRecord
    self.table_name = "ai_documents"

    # Associations
    belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase", foreign_key: "knowledge_base_id"
    belongs_to :uploaded_by, class_name: "User", foreign_key: "uploaded_by_id", optional: true

    has_many :chunks, class_name: "Ai::DocumentChunk", foreign_key: :document_id, dependent: :destroy

    # Delegate account access
    delegate :account, to: :knowledge_base

    # Validations
    validates :name, presence: true
    validates :source_type, presence: true, inclusion: { in: %w[upload url api database cloud_storage git] }
    validates :status, inclusion: { in: %w[pending processing indexed failed archived] }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :processing, -> { where(status: "processing") }
    scope :indexed, -> { where(status: "indexed") }
    scope :failed, -> { where(status: "failed") }
    scope :by_source_type, ->(type) { where(source_type: type) }

    # Callbacks
    after_save :update_knowledge_base_stats, if: :saved_change_to_status?

    # Status transitions
    def start_processing!
      update!(status: "processing")
    end

    def complete_indexing!(chunk_count:, token_count:)
      update!(
        status: "indexed",
        chunk_count: chunk_count,
        token_count: token_count,
        processed_at: Time.current
      )
    end

    def mark_failed!(error_message)
      current_errors = processing_errors || []
      current_errors << { error: error_message, timestamp: Time.current.iso8601 }
      update!(status: "failed", processing_errors: current_errors)
    end

    def archive!
      update!(status: "archived")
    end

    def refresh!
      update!(last_refreshed_at: Time.current)
    end

    # Helpers
    def expired?
      expires_at.present? && expires_at < Time.current
    end

    def needs_refresh?(interval_hours = 24)
      return true if last_refreshed_at.nil?

      last_refreshed_at < interval_hours.hours.ago
    end

    def generate_checksum(content_data = content)
      return unless content_data

      Digest::SHA256.hexdigest(content_data)
    end

    def content_changed?
      generate_checksum != checksum
    end

    private

    def update_knowledge_base_stats
      knowledge_base.update_stats!
    end
  end
end
