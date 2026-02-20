# frozen_string_literal: true

module Ai
  class TelemetryEvent < ApplicationRecord
    self.table_name = "ai_telemetry_events"

    EVENT_CATEGORIES = %w[action trust budget delegation security lifecycle].freeze

    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"
    belongs_to :parent_event, class_name: "Ai::TelemetryEvent", foreign_key: "parent_event_id", optional: true

    has_many :child_events, class_name: "Ai::TelemetryEvent", foreign_key: "parent_event_id", dependent: :nullify

    validates :event_category, presence: true, inclusion: { in: EVENT_CATEGORIES }
    validates :event_type, presence: true
    validates :correlation_id, presence: true

    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :by_category, ->(cat) { where(event_category: cat) }
    scope :by_correlation, ->(id) { where(correlation_id: id) }
    scope :recent, -> { order(created_at: :desc) }
    scope :ordered, -> { order(sequence_number: :asc) }

    attribute :event_data, :json, default: -> { {} }
  end
end
