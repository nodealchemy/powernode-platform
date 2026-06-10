# frozen_string_literal: true

module Ai
  class MissionApproval < ApplicationRecord
    self.table_name = "ai_mission_approvals"

    GATES = %w[feature_selection prd_review code_review merge_approval plan_review handoff fleet_review].freeze
    DECISIONS = %w[approved rejected].freeze

    # Canonical phase-name → gate-name mapping. Mission phase pipelines
    # use verb-object naming (review_plan, capture_intent, …) but the
    # approval-gate vocabulary is object-noun (plan_review). This is the
    # single source of truth — controllers, services, and tests all use
    # `gate_for_phase` so the mapping doesn't drift across layers.
    #
    # Resolution order (most specific → most general):
    #   1. Mission's custom_phases / mission_template.phases — per-phase
    #      `gate_name` override defined in the template (already used by
    #      OrchestratorService#gate_for_phase before this consolidation).
    #   2. PHASE_GATE_ALIASES — static defaults for the common case where
    #      a phase name isn't a valid GATES value but maps cleanly.
    #   3. The phase as-is — used when phase IS already a valid gate
    #      (e.g. handoff phase → handoff gate).
    PHASE_GATE_ALIASES = {
      "review_plan"  => "plan_review",
      "plan_review"  => "plan_review",
      "handoff"      => "handoff",
      "feature_selection" => "feature_selection",
      "prd_review"   => "prd_review",
      "code_review"  => "code_review",
      "merge_approval" => "merge_approval"
    }.freeze

    # @param phase [String, Symbol] mission phase or gate name
    # @param mission [Ai::Mission, nil] when present, the template's
    #   per-phase config takes precedence over PHASE_GATE_ALIASES
    # @return [String] a value guaranteed to be in GATES, or the input
    #   unchanged if no mapping exists (caller validates)
    def self.gate_for_phase(phase, mission: nil)
      return nil if phase.blank?
      phase_str = phase.to_s

      if mission
        config = template_phase_config(mission, phase_str)
        gate = config&.dig("gate_name")
        return gate if gate.present?
      end

      PHASE_GATE_ALIASES[phase_str] || phase_str
    end

    def self.template_phase_config(mission, phase)
      phases = if mission.respond_to?(:custom_phases) && mission.custom_phases.present?
                 mission.custom_phases
               elsif mission.respond_to?(:mission_template) && mission.mission_template
                 mission.mission_template.phases
               end
      return nil unless phases.is_a?(Array)
      phases.find { |p| p["key"].to_s == phase.to_s }
    end

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
