# frozen_string_literal: true

module Ai
  class CollusionIndicator < ApplicationRecord
    self.table_name = "ai_collusion_indicators"

    INDICATOR_TYPES = %w[synchronized_output mutual_approval resource_hoarding trust_inflation echo_chamber].freeze

    belongs_to :account

    validates :indicator_type, presence: true, inclusion: { in: INDICATOR_TYPES }
    validates :correlation_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    attribute :agent_cluster, :json, default: -> { [] }
    attribute :evidence_summary, :json, default: -> { {} }

    scope :high_confidence, -> { where("correlation_score >= ?", 0.7) }
    scope :by_type, ->(type) { where(indicator_type: type) }
    scope :recent, -> { order(created_at: :desc) }
  end
end
