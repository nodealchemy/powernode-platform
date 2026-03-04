# frozen_string_literal: true

module Ai
  class PressureField < ApplicationRecord
    self.table_name = "ai_pressure_fields"

    FIELD_TYPES = %w[code_quality test_coverage doc_readability security_posture performance dependency_health].freeze

    belongs_to :account

    validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
    validates :artifact_ref, presence: true
    validates :pressure_value, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :threshold, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    attribute :dimensions, :json, default: -> { {} }

    scope :actionable, -> { where("pressure_value >= threshold") }
    scope :by_type, ->(type) { where(field_type: type) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :highest_pressure, -> { order(pressure_value: :desc) }
    scope :recently_measured, -> { where("last_measured_at > ?", 1.hour.ago) }

    def apply_decay!
      return if pressure_value <= 0.0

      decayed = [pressure_value * (1.0 - decay_rate), 0.0].max
      update!(pressure_value: decayed.round(4))
    end

    def record_measurement!(value:, dimensions: {})
      update!(
        pressure_value: value.round(4),
        dimensions: dimensions,
        last_measured_at: Time.current
      )

      # Broadcast update
      McpChannel.broadcast_to_account(
        account_id,
        { type: "pressure_field_update", field_id: id, field_type: field_type, artifact_ref: artifact_ref, pressure_value: pressure_value }
      )
    end

    def record_address!(agent_id)
      update!(
        last_addressed_at: Time.current,
        last_addressed_by_id: agent_id,
        address_count: address_count + 1
      )
    end

    def actionable?
      pressure_value >= threshold
    end
  end
end
