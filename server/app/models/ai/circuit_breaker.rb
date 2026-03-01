# frozen_string_literal: true

module Ai
  class CircuitBreaker < ApplicationRecord
    self.table_name = "ai_circuit_breakers"

    STATES = %w[closed open half_open].freeze

    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"

    validates :action_type, presence: true, uniqueness: { scope: :agent_id }
    validates :state, inclusion: { in: STATES }
    validates :failure_threshold, numericality: { greater_than: 0 }
    validates :success_threshold, numericality: { greater_than: 0 }
    validates :cooldown_seconds, numericality: { greater_than: 0 }

    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :by_state, ->(state) { where(state: state) }
    scope :open_breakers, -> { where(state: "open") }
    scope :tripped, -> { where(state: %w[open half_open]) }

    def closed?
      state == "closed"
    end

    def open?
      state == "open"
    end

    def half_open?
      state == "half_open"
    end

    def cooldown_expired?
      return false unless open?
      return true unless opened_at

      opened_at + cooldown_seconds.seconds <= Time.current
    end

    def trip!(reason: "failure_threshold_exceeded")
      return if open?

      record_transition!("open", reason)
    end

    def attempt_reset!
      return unless open? && cooldown_expired?

      record_transition!("half_open", "cooldown_expired")
    end

    def close!(reason: "success_threshold_reached")
      record_transition!("closed", reason)
    end

    def record_transition!(new_state, reason)
      old_state = state
      event = {
        timestamp: Time.current.iso8601,
        from_state: old_state,
        to_state: new_state,
        reason: reason
      }

      attrs = { state: new_state, history: (history || []).last(49) + [event] }
      attrs[:opened_at] = Time.current if new_state == "open"
      attrs[:half_opened_at] = Time.current if new_state == "half_open"
      attrs[:failure_count] = 0 if new_state == "closed"
      attrs[:success_count] = 0 if new_state == "open"

      update!(attrs)
    end
  end
end
