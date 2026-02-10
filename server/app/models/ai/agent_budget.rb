# frozen_string_literal: true

module Ai
  class AgentBudget < ApplicationRecord
    self.table_name = "ai_agent_budgets"

    # ==========================================
    # Constants
    # ==========================================
    PERIOD_TYPES = %w[daily weekly monthly total].freeze
    CURRENCIES = %w[USD EUR GBP].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"
    belongs_to :parent_budget, class_name: "Ai::AgentBudget", optional: true

    has_many :child_budgets, class_name: "Ai::AgentBudget", foreign_key: "parent_budget_id", dependent: :nullify

    # ==========================================
    # Validations
    # ==========================================
    validates :total_budget_cents, presence: true, numericality: { greater_than: 0 }
    validates :spent_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :reserved_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :currency, inclusion: { in: CURRENCIES }
    validates :period_type, inclusion: { in: PERIOD_TYPES }
    validate :spent_within_budget
    validate :child_budget_within_parent

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where("period_end IS NULL OR period_end > ?", Time.current) }
    scope :expired, -> { where("period_end IS NOT NULL AND period_end <= ?", Time.current) }
    scope :for_period, ->(type) { where(period_type: type) }
    scope :root_budgets, -> { where(parent_budget_id: nil) }

    # ==========================================
    # Methods
    # ==========================================

    def remaining_cents
      total_budget_cents - spent_cents - reserved_cents
    end

    def utilization_percentage
      return 0 if total_budget_cents.zero?

      ((spent_cents.to_f / total_budget_cents) * 100).round(2)
    end

    def exceeded?
      spent_cents >= total_budget_cents
    end

    def nearly_exceeded?(threshold: 0.9)
      spent_cents >= (total_budget_cents * threshold)
    end

    # Reserve budget for an upcoming operation
    def reserve!(amount_cents)
      return false if remaining_cents < amount_cents

      increment!(:reserved_cents, amount_cents)
      true
    end

    # Spend from reserved budget
    def spend!(amount_cents)
      transaction do
        decrement!(:reserved_cents, [amount_cents, reserved_cents].min)
        increment!(:spent_cents, amount_cents)
      end
    end

    # Release reserved budget
    def release_reservation!(amount_cents)
      decrement!(:reserved_cents, [amount_cents, reserved_cents].min)
    end

    # Allocate a child budget
    def allocate_child(agent:, amount_cents:, period_type: self.period_type)
      return nil if remaining_cents < amount_cents

      transaction do
        reserve!(amount_cents)
        child_budgets.create!(
          account: account,
          agent: agent,
          total_budget_cents: amount_cents,
          currency: currency,
          period_type: period_type,
          period_start: Time.current,
          period_end: period_end
        )
      end
    end

    private

    def spent_within_budget
      return unless spent_cents.present? && total_budget_cents.present?

      if spent_cents > total_budget_cents
        errors.add(:spent_cents, "cannot exceed total budget")
      end
    end

    def child_budget_within_parent
      return unless parent_budget.present? && total_budget_cents.present?

      if total_budget_cents > parent_budget.remaining_cents + total_budget_cents_was.to_i
        errors.add(:total_budget_cents, "cannot exceed parent budget remaining balance")
      end
    end
  end
end
