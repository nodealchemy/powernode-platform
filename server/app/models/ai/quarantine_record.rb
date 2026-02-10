# frozen_string_literal: true

module Ai
  class QuarantineRecord < ApplicationRecord
    self.table_name = "ai_quarantine_records"

    # ==========================================
    # Constants
    # ==========================================
    SEVERITIES = %w[low medium high critical].freeze
    STATUSES = %w[active escalated restored expired].freeze
    TRIGGER_SOURCES = %w[anomaly_detection manual policy_violation budget_exceeded].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account

    # ==========================================
    # Validations
    # ==========================================
    validates :agent_id, presence: true
    validates :severity, presence: true, inclusion: { in: SEVERITIES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :trigger_reason, presence: true
    validates :trigger_source, inclusion: { in: TRIGGER_SOURCES }, allow_nil: true
    validates :cooldown_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where(status: "active") }
    scope :escalated, -> { where(status: "escalated") }
    scope :restored, -> { where(status: "restored") }
    scope :expired_status, -> { where(status: "expired") }
    scope :by_severity, ->(severity) { where(severity: severity) }
    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :critical, -> { where(severity: "critical") }
    scope :high_and_above, -> { where(severity: %w[high critical]) }
    scope :restorable, -> {
      active.where(
        "scheduled_restore_at IS NOT NULL AND scheduled_restore_at <= ?",
        Time.current
      )
    }
    scope :recent, ->(duration = 30.days) { where("created_at >= ?", duration.ago) }

    # ==========================================
    # Methods
    # ==========================================
    def active?
      status == "active"
    end

    def escalated?
      status == "escalated"
    end

    def restored?
      status == "restored"
    end

    def past_cooldown?
      return true unless cooldown_minutes.positive?

      created_at + cooldown_minutes.minutes <= Time.current
    end

    def auto_restorable?
      active? && scheduled_restore_at.present? && scheduled_restore_at <= Time.current
    end

    def severity_level
      SEVERITIES.index(severity) || 0
    end
  end
end
