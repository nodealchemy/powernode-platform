# frozen_string_literal: true

module Ai
  class GovernanceReport < ApplicationRecord
    self.table_name = "ai_governance_reports"

    REPORT_TYPES = %w[policy_violation anomaly resource_abuse collusion_suspicion pattern_drift safety_concern].freeze
    SEVERITIES = %w[info warning critical].freeze
    STATUSES = %w[open investigating confirmed dismissed remediated].freeze

    belongs_to :account
    belongs_to :monitor_agent, class_name: "Ai::Agent", foreign_key: "monitor_agent_id", optional: true
    belongs_to :subject_agent, class_name: "Ai::Agent", foreign_key: "subject_agent_id", optional: true
    belongs_to :subject_team, class_name: "Ai::AgentTeam", foreign_key: "subject_team_id", optional: true

    validates :report_type, presence: true, inclusion: { in: REPORT_TYPES }
    validates :severity, presence: true, inclusion: { in: SEVERITIES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    attribute :evidence, :json, default: -> { {} }
    attribute :recommended_actions, :json, default: -> { [] }

    scope :open_reports, -> { where(status: %w[open investigating]) }
    scope :critical, -> { where(severity: "critical") }
    scope :for_agent, ->(agent_id) { where(subject_agent_id: agent_id) }
    scope :for_team, ->(team_id) { where(subject_team_id: team_id) }
    scope :unresolved, -> { where(status: %w[open investigating confirmed]) }
    scope :recent, -> { order(created_at: :desc) }

    def resolve!(status:, remediation_notes: nil)
      update!(
        status: status,
        evidence: evidence.merge("resolution" => { "status" => status, "notes" => remediation_notes, "at" => Time.current.iso8601 })
      )
    end
  end
end
