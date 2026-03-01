# frozen_string_literal: true

module Ai
  class AgentEscalation < ApplicationRecord
    self.table_name = "ai_agent_escalations"

    ESCALATION_TYPES = %w[
      stuck error budget_exceeded approval_timeout
      quality_concern security_issue
    ].freeze

    SEVERITIES = %w[low medium high critical].freeze
    STATUSES = %w[open acknowledged in_progress resolved auto_resolved].freeze

    SEVERITY_TIMEOUTS = {
      "critical" => 1,
      "high" => 4,
      "medium" => 12,
      "low" => 24
    }.freeze

    # Associations
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
    belongs_to :escalated_to_user, class_name: "User", optional: true

    # Validations
    validates :title, presence: true
    validates :escalation_type, presence: true, inclusion: { in: ESCALATION_TYPES }
    validates :severity, presence: true, inclusion: { in: SEVERITIES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # JSON columns
    attribute :context, :json, default: -> { {} }
    attribute :escalation_chain, :json, default: -> { [] }

    # Scopes
    scope :open_or_active, -> { where(status: %w[open acknowledged in_progress]) }
    scope :unacknowledged, -> { where(status: "open") }
    scope :overdue, -> { open_or_active.where("next_escalation_at IS NOT NULL AND next_escalation_at < ?", Time.current) }
    scope :by_severity, -> { order(Arel.sql("CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 END")) }

    # Callbacks
    before_validation :set_timeout, on: :create

    def acknowledge!(user = nil)
      update!(
        status: "acknowledged",
        escalated_to_user: user || escalated_to_user,
        acknowledged_at: Time.current
      )
    end

    def resolve!(status: "resolved")
      update!(
        status: status,
        resolved_at: Time.current
      )
    end

    def escalate_to_next_level!
      next_level = current_level + 1
      chain = escalation_chain

      if next_level < chain.size
        next_user_id = chain[next_level]["user_id"]
        update!(
          current_level: next_level,
          escalated_to_user_id: next_user_id,
          next_escalation_at: calculate_next_escalation
        )
      else
        # No more levels — mark as needing manual attention
        update!(
          current_level: next_level,
          next_escalation_at: nil
        )
      end
    end

    def active?
      %w[open acknowledged in_progress].include?(status)
    end

    private

    def set_timeout
      self.timeout_hours ||= SEVERITY_TIMEOUTS[severity] || 12
      self.next_escalation_at ||= calculate_next_escalation
    end

    def calculate_next_escalation
      (timeout_hours || 12).hours.from_now
    end
  end
end
