# frozen_string_literal: true

module Ai
  class MissionApproval < ApplicationRecord
    self.table_name = "ai_mission_approvals"

    GATES = %w[feature_selection prd_review code_review merge_approval].freeze
    DECISIONS = %w[approved rejected].freeze

    belongs_to :mission, class_name: "Ai::Mission", foreign_key: "mission_id"
    belongs_to :account
    belongs_to :user

    validates :gate, presence: true, inclusion: { in: GATES }
    validates :decision, presence: true, inclusion: { in: DECISIONS }

    scope :for_gate, ->(gate) { where(gate: gate) }
    scope :approved, -> { where(decision: "approved") }
    scope :rejected, -> { where(decision: "rejected") }
    scope :recent, -> { order(created_at: :desc) }

    def approved?
      decision == "approved"
    end

    def rejected?
      decision == "rejected"
    end

    def approval_summary
      {
        id: id,
        gate: gate,
        decision: decision,
        comment: comment,
        user: user&.name,
        created_at: created_at.iso8601
      }
    end
  end
end
