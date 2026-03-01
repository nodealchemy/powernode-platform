# frozen_string_literal: true

module Ai
  class SkillConflict < ApplicationRecord
    self.table_name = "ai_skill_conflicts"

    # ==========================================
    # Constants
    # ==========================================
    CONFLICT_TYPES = %w[duplicate overlapping circular_dependency stale orphan version_drift].freeze
    SEVERITIES = %w[critical high medium low].freeze
    STATUSES = %w[detected reviewing auto_resolved resolved dismissed].freeze
    SEVERITY_WEIGHTS = { "critical" => 4, "high" => 3, "medium" => 2, "low" => 1 }.freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :skill_a, class_name: "Ai::Skill", foreign_key: "skill_a_id"
    belongs_to :skill_b, class_name: "Ai::Skill", foreign_key: "skill_b_id", optional: true
    belongs_to :resolved_by, class_name: "User", foreign_key: "resolved_by_id", optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :conflict_type, presence: true, inclusion: { in: CONFLICT_TYPES }
    validates :severity, presence: true, inclusion: { in: SEVERITIES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where.not(status: %w[resolved dismissed]) }
    scope :unresolved, -> { where(status: %w[detected reviewing]) }
    scope :auto_resolvable, -> { where(auto_resolvable: true) }
    scope :by_priority, -> { order(priority_score: :desc) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }

    # ==========================================
    # Public Methods
    # ==========================================

    def resolve!(user: nil, strategy: nil, details: {})
      update!(
        status: "resolved",
        resolved_at: Time.current,
        resolved_by: user,
        resolution_strategy: strategy || resolution_strategy,
        resolution_details: details.present? ? details : resolution_details
      )
    end

    def dismiss!(user: nil)
      update!(
        status: "dismissed",
        resolved_at: Time.current,
        resolved_by: user
      )
    end

    def calculate_priority!
      severity_weight = SEVERITY_WEIGHTS.fetch(severity, 2)
      days = detected_at ? ((Time.current - detected_at) / 1.day).to_f : 0.0
      age_factor = [[1.0, days / 30.0].max, 3.0].min
      impact = similarity_score || 0.0

      update_column(:priority_score, severity_weight * age_factor * (1 + impact))
    end
  end
end
