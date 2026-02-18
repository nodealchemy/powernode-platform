# frozen_string_literal: true

module Ai
  class BehavioralFingerprint < ApplicationRecord
    self.table_name = "ai_behavioral_fingerprints"

    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"

    validates :metric_name, presence: true, uniqueness: { scope: :agent_id }
    validates :baseline_mean, :baseline_stddev, :deviation_threshold, numericality: true
    validates :rolling_window_days, numericality: { greater_than: 0 }
    validates :observation_count, :anomaly_count, numericality: { greater_than_or_equal_to: 0 }

    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :for_metric, ->(name) { where(metric_name: name) }

    # Check if a value deviates from the baseline beyond the threshold
    def anomalous?(value)
      return false if observation_count < 5 || baseline_stddev.zero?

      z_score = (value - baseline_mean).abs / baseline_stddev
      z_score > deviation_threshold
    end
  end
end
