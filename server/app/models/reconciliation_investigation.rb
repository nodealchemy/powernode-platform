# frozen_string_literal: true

class ReconciliationInvestigation < ApplicationRecord
  include AASM

  belongs_to :reconciliation_flag
  belongs_to :investigator, class_name: "User"

  validates :started_at, presence: true
  validates :status, presence: true

  scope :open_investigations, -> { where(status: "open") }
  scope :in_progress, -> { where(status: "in_progress") }
  scope :completed, -> { where(status: "completed") }
  scope :escalated, -> { where(status: "escalated") }

  aasm column: :status do
    state :open, initial: true
    state :in_progress
    state :completed
    state :escalated

    event :start_work do
      transitions from: :open, to: :in_progress
    end

    event :complete do
      transitions from: [ :open, :in_progress ], to: :completed
      after do
        self.completed_at = Time.current
      end
    end

    event :escalate do
      transitions from: [ :open, :in_progress ], to: :escalated
    end
  end

  def add_finding(finding_type, description, metadata = {})
    current_findings = self.findings || {}
    entries = current_findings["entries"] || []
    entries << {
      type: finding_type,
      description: description,
      metadata: metadata,
      found_at: Time.current.iso8601
    }
    current_findings["entries"] = entries

    update!(findings: current_findings)
  end
end
