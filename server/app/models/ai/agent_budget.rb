# frozen_string_literal: true

module Ai
  class AgentBudget < ApplicationRecord
    self.table_name = "ai_agent_budgets"

    # ==========================================
    # Constants
    # ==========================================
    PERIOD_TYPES = %w[daily weekly monthly total].freeze
    CURRENCIES = %w[USD EUR GBP].freeze
    UTILIZATION_THRESHOLDS = { warning: 75, danger: 90, exhausted: 100 }.freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"
    belongs_to :parent_budget, class_name: "Ai::AgentBudget", foreign_key: "parent_budget_id", optional: true

    has_many :child_budgets, class_name: "Ai::AgentBudget", foreign_key: "parent_budget_id", dependent: :nullify
    has_many :budget_transactions, class_name: "Ai::BudgetTransaction", foreign_key: "ai_agent_budget_id", dependent: :destroy

    # ==========================================
    # Validations
    # ==========================================
    validates :total_budget_cents, presence: true, numericality: { greater_than: 0 }
    validates :spent_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :reserved_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :currency, inclusion: { in: CURRENCIES }
    validates :period_type, inclusion: { in: PERIOD_TYPES }
    validate :child_budget_within_parent

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where("period_end IS NULL OR period_end > ?", Time.current) }
    scope :expired, -> { where("period_end IS NOT NULL AND period_end <= ?", Time.current) }
    scope :for_period, ->(type) { where(period_type: type) }
    scope :root_budgets, -> { where(parent_budget_id: nil) }
    scope :over_budget, -> { where("spent_cents >= total_budget_cents") }
    scope :at_threshold, ->(pct) { where("(spent_cents::float / NULLIF(total_budget_cents, 0)) * 100 >= ?", pct) }

    # ==========================================
    # Core budget operations (row-locked, audited)
    # ==========================================

    # Debit budget for an execution cost
    # @param amount_cents [Integer] Amount to debit
    # @param execution [Ai::AgentExecution, nil] Associated execution (optional for manual adjustments)
    # @param metadata [Hash] Additional context (provider, model, tokens, reason)
    # @return [Ai::BudgetTransaction] The created transaction
    def debit!(amount_cents, execution: nil, metadata: {})
      transaction do
        lock!
        new_spent = spent_cents + amount_cents
        update_columns(spent_cents: new_spent, updated_at: Time.current)

        txn = budget_transactions.create!(
          account: account,
          agent_execution: execution,
          transaction_type: "debit",
          amount_cents: amount_cents,
          running_balance_cents: total_budget_cents - new_spent - reserved_cents,
          metadata: metadata
        )

        check_threshold_alerts!
        txn
      end
    end

    # Credit budget (manual adjustment or refund)
    # @param amount_cents [Integer] Amount to credit
    # @param reason [String] Reason for credit
    # @param metadata [Hash] Additional context
    # @return [Ai::BudgetTransaction] The created transaction
    def credit!(amount_cents, reason: "manual_adjustment", metadata: {})
      transaction do
        lock!
        new_spent = [spent_cents - amount_cents, 0].max
        update_columns(spent_cents: new_spent, updated_at: Time.current)

        budget_transactions.create!(
          account: account,
          transaction_type: "credit",
          amount_cents: amount_cents,
          running_balance_cents: total_budget_cents - new_spent - reserved_cents,
          metadata: metadata.merge(reason: reason)
        )
      end
    end

    # Reserve budget for an upcoming operation
    # @param amount_cents [Integer] Amount to reserve
    # @param metadata [Hash] Additional context
    # @return [Ai::BudgetTransaction, false] Transaction or false if insufficient
    def reserve!(amount_cents, metadata: {})
      transaction do
        lock!
        return false if remaining_cents < amount_cents

        new_reserved = reserved_cents + amount_cents
        update_columns(reserved_cents: new_reserved, updated_at: Time.current)

        budget_transactions.create!(
          account: account,
          transaction_type: "reservation",
          amount_cents: amount_cents,
          running_balance_cents: total_budget_cents - spent_cents - new_reserved,
          metadata: metadata
        )
      end
    end

    # Spend from reserved budget (legacy compatibility + transaction recording)
    def spend!(amount_cents, execution: nil, metadata: {})
      transaction do
        lock!
        release_amount = [amount_cents, reserved_cents].min
        new_reserved = reserved_cents - release_amount
        new_spent = spent_cents + amount_cents
        update_columns(spent_cents: new_spent, reserved_cents: new_reserved, updated_at: Time.current)

        txn = budget_transactions.create!(
          account: account,
          agent_execution: execution,
          transaction_type: "debit",
          amount_cents: amount_cents,
          running_balance_cents: total_budget_cents - new_spent - new_reserved,
          metadata: metadata
        )

        check_threshold_alerts!
        txn
      end
    end

    # Release reserved budget
    # @param amount_cents [Integer] Amount to release
    # @param metadata [Hash] Additional context
    # @return [Ai::BudgetTransaction]
    def release_reservation!(amount_cents, metadata: {})
      transaction do
        lock!
        release_amount = [amount_cents, reserved_cents].min
        new_reserved = reserved_cents - release_amount
        update_columns(reserved_cents: new_reserved, updated_at: Time.current)

        budget_transactions.create!(
          account: account,
          transaction_type: "release",
          amount_cents: release_amount,
          running_balance_cents: total_budget_cents - spent_cents - new_reserved,
          metadata: metadata
        )
      end
    end

    # Auto-rollover: create new period budget, record rollover transaction on old one
    # @return [Ai::AgentBudget] The new budget for the next period
    def auto_rollover!
      return nil if period_type == "total"
      return nil unless period_end.present? && period_end <= Time.current

      transaction do
        lock!
        # Record rollover transaction on the old budget
        budget_transactions.create!(
          account: account,
          transaction_type: "rollover",
          amount_cents: 0,
          running_balance_cents: remaining_cents,
          metadata: { rolled_over_at: Time.current.iso8601, final_spent: spent_cents, final_remaining: remaining_cents }
        )

        # Calculate new period
        new_start = period_end
        new_end = calculate_next_period_end(new_start)

        # Create new budget (no carryover per user decision)
        self.class.create!(
          account: account,
          agent: agent,
          total_budget_cents: total_budget_cents,
          spent_cents: 0,
          reserved_cents: 0,
          currency: currency,
          period_type: period_type,
          period_start: new_start,
          period_end: new_end,
          parent_budget_id: parent_budget_id
        )
      end
    end

    # Allocate a child budget
    def allocate_child(agent:, amount_cents:, period_type: self.period_type)
      return nil if remaining_cents < amount_cents

      transaction do
        reserve!(amount_cents, metadata: { reason: "child_allocation", child_agent_id: agent.id })
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

    # ==========================================
    # Query methods
    # ==========================================

    def remaining_cents
      total_budget_cents - spent_cents - reserved_cents
    end

    def utilization_percentage
      return 0 if total_budget_cents.zero?

      ((spent_cents.to_f / total_budget_cents) * 100).round(2)
    end

    def utilization_ratio
      return 0.0 if total_budget_cents.zero?

      (spent_cents.to_f / total_budget_cents).round(4)
    end

    def over_budget?
      spent_cents >= total_budget_cents
    end

    def exceeded?
      over_budget?
    end

    def nearly_exceeded?(threshold: 0.9)
      spent_cents >= (total_budget_cents * threshold)
    end

    private

    def check_threshold_alerts!
      pct = utilization_percentage
      return unless pct >= UTILIZATION_THRESHOLDS[:warning]

      level = if pct >= UTILIZATION_THRESHOLDS[:exhausted]
                :critical
              elsif pct >= UTILIZATION_THRESHOLDS[:danger]
                :warning
              else
                :info
              end

      Rails.logger.info(
        "[AgentBudget] Threshold alert: budget=#{id} agent=#{agent_id} " \
        "utilization=#{pct}% level=#{level}"
      )

      notify_threshold_breach!(level, pct) if level == :critical || level == :warning
    end

    def notify_threshold_breach!(level, pct)
      NotificationService.send_system_alert(
        account: account,
        type: "budget_threshold",
        level: level,
        title: "Agent budget #{level == :critical ? 'exhausted' : 'warning'}",
        message: "Budget for agent '#{agent&.name}' is at #{pct.round(1)}% utilization.",
        details: { budget_id: id, agent_id: agent_id, utilization_pct: pct, remaining_cents: remaining_cents }
      )
    rescue StandardError => e
      Rails.logger.error("[AgentBudget] Failed to send threshold notification: #{e.message}")
    end

    def calculate_next_period_end(start_time)
      case period_type
      when "daily" then start_time + 1.day
      when "weekly" then start_time + 1.week
      when "monthly" then start_time + 1.month
      else nil
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
