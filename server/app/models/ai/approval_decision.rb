# frozen_string_literal: true

module Ai
  class ApprovalDecision < ApplicationRecord
    self.table_name = "ai_approval_decisions"

    # WHERE a decision came from (MCP identity plan R2). A request flagged
    # requires_human_session is decided only from REST_SESSION.
    #   REST_SESSION  a person's own JWT session (HumanSession#own_human_session?)
    #   REST_OTHER    a REST session that is not a person's own: impersonation,
    #                 an account-switch delegation
    #   the Ai::Tools::CallOrigin values: a tool door (MCP, agent bridge, recipe)
    REST_SESSION = "rest_session"
    REST_OTHER   = "rest"
    ORIGINS = ([ REST_SESSION, REST_OTHER ] + ::Ai::Tools::CallOrigin::ALL).freeze

    def self.human_session_origin?(origin)
      origin.to_s == REST_SESSION
    end

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
