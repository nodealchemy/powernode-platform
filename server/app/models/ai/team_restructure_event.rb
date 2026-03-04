# frozen_string_literal: true

module Ai
  class TeamRestructureEvent < ApplicationRecord
    self.table_name = "ai_team_restructure_events"

    EVENT_TYPES = %w[role_change member_recruited member_released leader_emerged capability_gap].freeze

    belongs_to :account
    belongs_to :team, class_name: "Ai::AgentTeam", foreign_key: "ai_agent_team_id"
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

    validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

    attribute :previous_state, :json, default: -> { {} }
    attribute :new_state, :json, default: -> { {} }
    attribute :rationale, :json, default: -> { {} }
    attribute :metrics_snapshot, :json, default: -> { {} }

    scope :for_team, ->(team_id) { where(ai_agent_team_id: team_id) }
    scope :by_type, ->(type) { where(event_type: type) }
    scope :recent, -> { order(created_at: :desc) }
  end
end
