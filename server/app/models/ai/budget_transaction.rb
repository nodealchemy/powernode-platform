# frozen_string_literal: true

module Ai
  class BudgetTransaction < ApplicationRecord
    self.table_name = "ai_budget_transactions"

    # ==========================================
    # Constants
    # ==========================================
    TRANSACTION_TYPES = %w[debit credit reservation release rollover adjustment].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :agent_budget, class_name: "Ai::AgentBudget", foreign_key: "ai_agent_budget_id"
    belongs_to :agent_execution, class_name: "Ai::AgentExecution", foreign_key: "ai_agent_execution_id", optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :transaction_type, presence: true, inclusion: { in: TRANSACTION_TYPES }
    validates :amount_cents, presence: true
    validates :running_balance_cents, presence: true

    # ==========================================
    # Scopes
    # ==========================================
    scope :debits, -> { where(transaction_type: "debit") }
    scope :credits, -> { where(transaction_type: "credit") }
    scope :reservations, -> { where(transaction_type: "reservation") }
    scope :releases, -> { where(transaction_type: "release") }
    scope :rollovers, -> { where(transaction_type: "rollover") }
    scope :adjustments, -> { where(transaction_type: "adjustment") }
    scope :for_period, ->(start_at, end_at) { where(created_at: start_at..end_at) }
    scope :by_model, ->(model) { where("metadata->>'model' = ?", model) }
    scope :by_provider, ->(provider) { where("metadata->>'provider' = ?", provider) }
    scope :recent, -> { order(created_at: :desc) }

    # ==========================================
    # Callbacks
    # ==========================================
    attribute :metadata, :json, default: -> { {} }
  end
end
