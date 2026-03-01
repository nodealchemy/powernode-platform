# frozen_string_literal: true

module Ai
  class AgentObservation < ApplicationRecord
    self.table_name = "ai_agent_observations"

    RATE_LIMIT_PER_HOUR = 100
    DEDUP_WINDOW_MINUTES = 15

    SENSOR_TYPES = %w[
      knowledge_health platform_health recommendation peer_agent
      workspace code_change budget
    ].freeze

    OBSERVATION_TYPES = %w[anomaly degradation opportunity recommendation request alert].freeze
    SEVERITIES = %w[info warning critical].freeze

    # Associations
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
    belongs_to :goal, class_name: "Ai::AgentGoal", optional: true

    # Validations
    validates :sensor_type, presence: true, inclusion: { in: SENSOR_TYPES }
    validates :observation_type, presence: true, inclusion: { in: OBSERVATION_TYPES }
    validates :severity, presence: true, inclusion: { in: SEVERITIES }
    validates :title, presence: true

    validate :rate_limit_check, on: :create

    # JSON columns
    attribute :data, :json, default: -> { {} }

    # Scopes
    scope :unprocessed, -> { where(processed: false) }
    scope :actionable, -> { where(requires_action: true, processed: false) }
    scope :by_severity, -> { order(Arel.sql("CASE severity WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END")) }
    scope :recent, -> { order(created_at: :desc) }
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :by_sensor, ->(type) { where(sensor_type: type) }

    # Instance methods
    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def mark_processed!
      update!(processed: true)
    end

    # Check if a similar observation exists within the dedup window
    def self.duplicate_exists?(agent_id:, sensor_type:, data_fingerprint:)
      where(ai_agent_id: agent_id, sensor_type: sensor_type)
        .where("created_at > ?", DEDUP_WINDOW_MINUTES.minutes.ago)
        .where("data->>'fingerprint' = ?", data_fingerprint)
        .exists?
    end

    private

    def rate_limit_check
      return unless ai_agent_id

      recent_count = self.class.for_agent(ai_agent_id)
                         .where("created_at > ?", 1.hour.ago)
                         .count

      if recent_count >= RATE_LIMIT_PER_HOUR
        errors.add(:base, "Observation rate limit exceeded (#{RATE_LIMIT_PER_HOUR}/hour)")
      end
    end
  end
end
