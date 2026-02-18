# frozen_string_literal: true

module Ai
  class ApprovalDecision < ApplicationRecord
    self.table_name = "ai_approval_decisions"

    # Associations
    belongs_to :approval_request, class_name: "Ai::ApprovalRequest"
    belongs_to :approver, class_name: "User"

    # Validations
    validates :step_number, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :decision, presence: true, inclusion: { in: %w[approved rejected delegated abstained] }

    # Scopes
    scope :approved, -> { where(decision: "approved") }
    scope :rejected, -> { where(decision: "rejected") }
    scope :for_step, ->(step) { where(step_number: step) }
    scope :by_approver, ->(user) { where(approver: user) }
    scope :recent, -> { order(created_at: :desc) }

    # Methods
    def approved?
      decision == "approved"
    end

    def rejected?
      decision == "rejected"
    end

    def has_conditions?
      conditions.present? && conditions.any?
    end
  end
end
