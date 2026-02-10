# frozen_string_literal: true

module Ai
  class SharedKnowledge < ApplicationRecord
    self.table_name = "ai_shared_knowledges"

    has_neighbors :embedding

    # ==========================================
    # Constants
    # ==========================================
    CONTENT_TYPES = %w[text markdown code snippet procedure fact definition].freeze
    ACCESS_LEVELS = %w[private team account global].freeze
    SOURCE_TYPES = %w[agent workflow extraction manual import].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :title, presence: true, length: { maximum: 500 }
    validates :content, presence: true
    validates :content_type, inclusion: { in: CONTENT_TYPES }
    validates :access_level, inclusion: { in: ACCESS_LEVELS }
    validates :quality_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

    # ==========================================
    # Scopes
    # ==========================================
    scope :accessible_by, ->(access_level) {
      case access_level
      when "global" then where(access_level: "global")
      when "account" then where(access_level: %w[account global])
      when "team" then where(access_level: %w[team account global])
      else where(access_level: %w[private team account global])
      end
    }
    scope :by_content_type, ->(type) { where(content_type: type) }
    scope :with_tag, ->(tag) { where("? = ANY(tags)", tag) }
    scope :with_any_tags, ->(tags) { where("tags && ARRAY[?]::varchar[]", tags) }
    scope :with_embedding, -> { where.not(embedding: nil) }
    scope :high_quality, -> { where("quality_score >= ?", 0.7) }
    scope :recent, -> { order(created_at: :desc) }
    scope :frequently_used, -> { order(usage_count: :desc) }
    scope :by_source, ->(type) { where(source_type: type) }

    # ==========================================
    # Methods
    # ==========================================

    def touch_usage!
      update_columns(
        usage_count: usage_count + 1,
        last_used_at: Time.current
      )
    end

    # Verify content integrity
    def verify_integrity!
      return true unless integrity_hash.present?

      computed = Digest::SHA256.hexdigest(content)
      computed == integrity_hash
    end

    # Compute and store integrity hash
    def compute_integrity_hash!
      update!(integrity_hash: Digest::SHA256.hexdigest(content))
    end

    # Search by semantic similarity
    def self.semantic_search(query_embedding, limit: 10, threshold: 0.7)
      distance_threshold = 1.0 - threshold
      nearest_neighbors(:embedding, query_embedding, distance: "cosine")
        .limit(limit)
        .to_a
        .select { |e| e.neighbor_distance <= distance_threshold }
    end
  end
end
