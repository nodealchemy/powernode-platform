# frozen_string_literal: true

module Ai
  class ModelPricing < ApplicationRecord
    self.table_name = "ai_model_pricings"

    # ==========================================
    # Validations
    # ==========================================
    validates :model_id, presence: true
    validates :provider_type, presence: true
    validates :input_per_1k, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :output_per_1k, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :source, presence: true
    validates :model_id, uniqueness: { scope: :provider_type }

    # ==========================================
    # Scopes
    # ==========================================
    scope :for_provider, ->(type) { where(provider_type: type) }
    scope :stale, ->(threshold = 24.hours.ago) { where("last_synced_at < ? OR last_synced_at IS NULL", threshold) }
    scope :by_tier, ->(tier) { where(tier: tier) }
    scope :manual_overrides, -> { where(source: "manual") }
    scope :auto_synced, -> { where.not(source: "manual") }

    # ==========================================
    # Callbacks
    # ==========================================
    attribute :metadata, :json, default: -> { {} }

    # ==========================================
    # Methods
    # ==========================================

    # Returns pricing hash in the format matching MODEL_PRICING constant
    def pricing_hash
      {
        "input" => input_per_1k.to_f,
        "output" => output_per_1k.to_f,
        "cached_input" => (cached_input_per_1k || 0).to_f,
        "tier" => tier
      }
    end
  end
end
