# frozen_string_literal: true

module Ai
  class HybridSearchResult < ApplicationRecord
    self.table_name = "ai_hybrid_search_results"

    SEARCH_MODES = %w[vector keyword hybrid graph].freeze
    FUSION_METHODS = %w[rrf weighted cascade].freeze

    # Associations
    belongs_to :account

    # Validations
    validates :query_text, presence: true
    validates :search_mode, presence: true, inclusion: { in: SEARCH_MODES }
    validates :fusion_method, inclusion: { in: FUSION_METHODS }, allow_nil: true

    # Scopes
    scope :by_mode, ->(mode) { where(search_mode: mode) }
    scope :recent, -> { order(created_at: :desc) }
    scope :reranked, -> { where(reranked: true) }

    # Average latency for a given search mode
    def self.avg_latency_for(mode)
      by_mode(mode).average(:total_latency_ms)&.round(2)
    end
  end
end
