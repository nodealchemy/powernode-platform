# frozen_string_literal: true

module Ai
  class SecurityAuditTrail < ApplicationRecord
    self.table_name = "ai_security_audit_trails"

    # ==========================================
    # Constants
    # ==========================================
    OUTCOMES = %w[allowed denied blocked quarantined escalated].freeze
    SEVERITIES = %w[info warning critical].freeze
    ASI_REFERENCES = (1..10).map { |n| "ASI#{n.to_s.rjust(2, '0')}" }.freeze
    CSA_PILLARS = %w[identity behavior data_governance segmentation incident_response].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account

    # ==========================================
    # Validations
    # ==========================================
    validates :action, presence: true
    validates :outcome, presence: true, inclusion: { in: OUTCOMES }
    validates :asi_reference, inclusion: { in: ASI_REFERENCES }, allow_nil: true
    validates :csa_pillar, inclusion: { in: CSA_PILLARS }, allow_nil: true
    validates :severity, inclusion: { in: SEVERITIES }, allow_nil: true
    validates :risk_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

    # ==========================================
    # Scopes
    # ==========================================
    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :by_asi, ->(ref) { where(asi_reference: ref) }
    scope :by_outcome, ->(outcome) { where(outcome: outcome) }
    scope :by_severity, ->(severity) { where(severity: severity) }
    scope :by_action, ->(action) { where(action: action) }
    scope :by_pillar, ->(pillar) { where(csa_pillar: pillar) }
    scope :by_source, ->(source) { where(source_service: source) }
    scope :recent, ->(duration = 30.days) { where("ai_security_audit_trails.created_at >= ?", duration.ago) }
    scope :denied_or_blocked, -> { where(outcome: %w[denied blocked]) }
    scope :high_risk, -> { where("risk_score >= ?", 0.7) }
    scope :critical_severity, -> { where(severity: "critical") }

    # ==========================================
    # Class Methods
    # ==========================================
    def self.log!(action:, outcome:, account: nil, agent_id: nil, user_id: nil,
                  asi_reference: nil, csa_pillar: nil, risk_score: nil,
                  context: {}, details: {}, source_service: nil,
                  severity: "info", ip_address: nil)
      create!(
        account: account,
        agent_id: agent_id,
        user_id: user_id,
        action: action,
        outcome: outcome,
        asi_reference: asi_reference,
        csa_pillar: csa_pillar,
        risk_score: risk_score,
        context: context,
        details: details,
        source_service: source_service,
        severity: severity,
        ip_address: ip_address
      )
    rescue StandardError => e
      Rails.logger.error "[SecurityAuditTrail] Failed to log: #{e.message}"
      nil
    end

    # ==========================================
    # Methods
    # ==========================================
    def allowed?
      outcome == "allowed"
    end

    def denied?
      outcome == "denied"
    end

    def blocked?
      outcome == "blocked"
    end

    def high_risk?
      risk_score.present? && risk_score >= 0.7
    end
  end
end
