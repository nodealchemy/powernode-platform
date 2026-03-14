# frozen_string_literal: true

class ReconciliationFlag < ApplicationRecord
  include AASM

  belongs_to :reconciliation_report
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :flag_type, presence: true, inclusion: {
    in: %w[missing_payment duplicate_payment amount_mismatch status_mismatch unknown_transaction]
  }
  validates :description, presence: true
  validates :status, presence: true
  validates :severity, inclusion: { in: %w[low medium high critical] }, allow_nil: true

  scope :pending, -> { where(status: "open") }
  scope :resolved, -> { where(status: "resolved") }

  aasm column: :status do
    state :open, initial: true
    state :investigating
    state :resolved
    state :dismissed

    event :start_investigation do
      transitions from: :open, to: :investigating
    end

    event :resolve do
      transitions from: [ :open, :investigating ], to: :resolved
      after do
        self.resolved_at = Time.current
      end
    end

    event :dismiss do
      transitions from: [ :open, :investigating ], to: :dismissed
      after do
        self.resolved_at = Time.current
      end
    end
  end

  def high_priority?
    %w[missing_payment amount_mismatch].include?(flag_type)
  end
end
