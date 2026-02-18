# frozen_string_literal: true

module Ai
  class PolicyViolation < ApplicationRecord
    self.table_name = "ai_policy_violations"

    # Associations
    belongs_to :account
    belongs_to :policy, class_name: "Ai::CompliancePolicy"
    belongs_to :detected_by, class_name: "User", optional: true
    belongs_to :resolved_by, class_name: "User", optional: true

    # Validations
    validates :violation_id, presence: true, uniqueness: true
    validates :severity, presence: true, inclusion: { in: %w[low medium high critical] }
    validates :status, presence: true, inclusion: { in: %w[open acknowledged investigating resolved dismissed escalated] }
    validates :description, presence: true
    validates :detected_at, presence: true

    # Scopes
    scope :open, -> { where(status: "open") }
    scope :unresolved, -> { where.not(status: %w[resolved dismissed]) }
    scope :resolved, -> { where(status: "resolved") }
    scope :critical, -> { where(severity: "critical") }
    scope :high_priority, -> { where(severity: %w[high critical]) }
    scope :by_severity, ->(severity) { where(severity: severity) }
    scope :for_source, ->(type, id) { where(source_type: type, source_id: id) }
    scope :for_period, ->(start_date, end_date) { where(detected_at: start_date..end_date) }
    scope :recent, -> { order(detected_at: :desc) }

    # Callbacks
    before_validation :set_violation_id, on: :create

    # Methods
    def open?
      status == "open"
    end

    def resolved?
      status == "resolved"
    end

    def critical?
      severity == "critical"
    end

    def acknowledge!(user = nil)
      return false unless open?

      update!(status: "acknowledged", acknowledged_at: Time.current, detected_by: user)
    end

    def investigate!(user = nil)
      update!(status: "investigating", detected_by: user || detected_by)
    end

    def resolve!(user:, notes: nil, action: nil)
      update!(
        status: "resolved",
        resolved_by: user,
        resolved_at: Time.current,
        resolution_notes: notes,
        resolution_action: action
      )
    end

    def dismiss!(user:, notes: nil)
      update!(
        status: "dismissed",
        resolved_by: user,
        resolved_at: Time.current,
        resolution_notes: notes,
        resolution_action: "dismissed"
      )
    end

    def escalate!
      update!(status: "escalated", escalated_at: Time.current)
    end

    def add_remediation_step(step)
      self.remediation_steps ||= []
      self.remediation_steps << step
      save!
    end

    private

    def set_violation_id
      self.violation_id ||= SecureRandom.uuid
    end
  end
end
