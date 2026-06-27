# frozen_string_literal: true

module Ai
  # One operator/agent disposition of a fork or blocked task within a Campaign — the durable
  # decision log (replaces the ad-hoc DECISIONS block in the morning markdown file).
  class CampaignDecision < ApplicationRecord
    DECISION_TYPES = %w[unblock skip build remove defer policy escalate other].freeze

    belongs_to :campaign, class_name: "Ai::Campaign", foreign_key: "campaign_id"
    belongs_to :ralph_task, class_name: "Ai::RalphTask", foreign_key: "ralph_task_id", optional: true
    belongs_to :user, class_name: "User", foreign_key: "user_id", optional: true

    validates :decision_type, presence: true, inclusion: { in: DECISION_TYPES }

    scope :recent, ->(limit = 100) { order(created_at: :desc).limit(limit) }

    def summary
      {
        id: id, decision_type: decision_type, title: title, rationale: rationale,
        ralph_task_id: ralph_task_id, decided_by: user_id, decided_at: created_at
      }
    end
  end
end
