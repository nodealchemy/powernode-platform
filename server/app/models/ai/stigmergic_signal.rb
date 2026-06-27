# frozen_string_literal: true

module Ai
  class StigmergicSignal < ApplicationRecord
    self.table_name = "ai_stigmergic_signals"

    # Base coordination categories used by core. Signal types are NOT limited to
    # these: core and other subsystems emit namespaced/semantic types (e.g.
    # "entry", "system.capacity_pressure") and perceivers query by exactly those,
    # so signal_type is an open, format-validated token — a new type needs no core
    # change. SIGNAL_TYPES is kept for documentation/reference of the base set.
    SIGNAL_TYPES = %w[pheromone pressure beacon warning discovery].freeze

    # Lowercase token, optionally dot-namespaced: "warning", "system.region_busy".
    SIGNAL_TYPE_FORMAT = /\A[a-z][a-z0-9_]*(\.[a-z0-9_]+)*\z/

    belongs_to :account
    belongs_to :emitter_agent, class_name: "Ai::Agent", foreign_key: "emitter_agent_id", optional: true
    belongs_to :memory_pool, class_name: "Ai::MemoryPool", foreign_key: "memory_pool_id", optional: true

    validates :signal_type, presence: true, format: { with: SIGNAL_TYPE_FORMAT }
    validates :signal_key, presence: true
    validates :strength, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :decay_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    attribute :payload, :json, default: -> { {} }
    attribute :reinforcements, :json, default: -> { [] }

    scope :active, -> { where("strength > 0.01 AND (expires_at IS NULL OR expires_at > ?)", Time.current) }
    scope :fading, -> { where("strength > 0.01 AND strength < 0.3") }
    scope :by_type, ->(type) { where(signal_type: type) }
    scope :by_key, ->(key) { where(signal_key: key) }
    scope :strongest, -> { order(strength: :desc) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }

    # T4 — autonomous team activation: any AgentTeam in this account that
    # opted in via activation_rules.on_event=[signal_key] gets dispatched.
    # Runs after_commit so the signal row is durably persisted before the
    # team execution starts (otherwise a rolled-back signal could leave a
    # stranded execution).
    after_create_commit :trigger_subscribed_teams

    def reinforce!(agent_id:, strength_delta: 0.1)
      new_strength = [strength + strength_delta, 1.0].min
      reinforcements << {
        "agent_id" => agent_id,
        "delta" => strength_delta,
        "at" => Time.current.iso8601
      }
      update!(
        strength: new_strength,
        reinforce_count: reinforce_count + 1,
        reinforcements: reinforcements
      )
    end

    def decay!
      return if strength <= 0.01

      new_strength = [strength * (1.0 - decay_rate), 0.0].max
      if new_strength <= 0.01
        update!(strength: 0.0)
      else
        update!(strength: new_strength.round(4))
      end
    end

    def perceive!(agent_id:)
      increment!(:perceive_count)
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def active?
      strength > 0.01 && !expired?
    end

    def fading?
      active? && strength < 0.3
    end

    private

    def trigger_subscribed_teams
      ::Ai::TeamEventDispatcher.dispatch(self)
    rescue StandardError => e
      Rails.logger.error("[StigmergicSignal] subscriber dispatch crashed: #{e.class}: #{e.message}")
    end
  end
end
