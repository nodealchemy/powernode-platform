# frozen_string_literal: true

module Ai
  class ImprovementRecommendation < ApplicationRecord
    STATUSES = %w[pending approved applied dismissed].freeze
    RECOMMENDATION_TYPES = %w[provider_switch team_composition timeout_adjustment model_upgrade cost_optimization skill_consolidation skill_connection prompt_refinement skill_creation code_lint dead_code code_duplication convention_adherence test_gap agent_reliability skill_health learning_health].freeze
    # Code-quality types are discovered via the /improve loop (Tier-1) and promoted
    # to dev-improve Ralph tasks rather than auto-applied as config changes.
    CODE_QUALITY_TYPES = %w[code_lint dead_code code_duplication convention_adherence test_gap].freeze

    belongs_to :account
    belongs_to :approved_by, class_name: "User", foreign_key: "approved_by_id", optional: true

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
    scope :for_target, ->(target_type, target_id) { where(target_type: target_type, target_id: target_id) }
    # Tier-2(b): first-class repository scoping via the polymorphic target
    scope :by_repository, ->(repository_id) { where(target_type: "Devops::GitRepository", target_id: repository_id) }
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
