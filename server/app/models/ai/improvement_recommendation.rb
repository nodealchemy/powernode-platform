# frozen_string_literal: true

module Ai
  class ImprovementRecommendation < ApplicationRecord
    STATUSES = %w[pending approved applied dismissed].freeze
    RECOMMENDATION_TYPES = %w[provider_switch team_composition timeout_adjustment model_upgrade cost_optimization].freeze

    belongs_to :account
    belongs_to :approved_by, class_name: "User", optional: true

    validates :recommendation_type, presence: true, inclusion: { in: RECOMMENDATION_TYPES }
    validates :target_type, presence: true
    validates :target_id, presence: true
    validates :confidence_score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: "pending") }
    scope :approved, -> { where(status: "approved") }
    scope :applied, -> { where(status: "applied") }
    scope :dismissed, -> { where(status: "dismissed") }
    scope :high_confidence, -> { where("confidence_score >= ?", 0.7) }
    scope :by_type, ->(type) { where(recommendation_type: type) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }

    def approve!(user)
      update!(status: "approved", approved_by: user)
    end

    def apply!(user)
      update!(status: "applied", approved_by: user, applied_at: Time.current)
    end

    def dismiss!
      update!(status: "dismissed")
    end

    def target
      target_type.constantize.find_by(id: target_id)
    rescue NameError
      nil
    end
  end
end
