# frozen_string_literal: true

# Credit Transaction Model - All credit movements (double-entry ledger)
#
# Records all credit movements with full audit trail.
# Supports: purchase, usage, refund, transfer, bonus, adjustment, expiration
#
module Ai
  class CreditTransaction < ApplicationRecord
    self.table_name = "ai_credit_transactions"

    # Associations
    belongs_to :account
    belongs_to :account_credit, class_name: "Ai::AccountCredit"
    belongs_to :credit_pack, class_name: "Ai::CreditPack", optional: true
    belongs_to :initiated_by, class_name: "User", optional: true
    belongs_to :related_transaction, class_name: "Ai::CreditTransaction", optional: true

    # Validations
    validates :transaction_type, presence: true, inclusion: {
      in: %w[purchase usage refund transfer_in transfer_out bonus adjustment expiration reservation release]
    }
    validates :amount, presence: true, numericality: true
    validates :balance_before, presence: true, numericality: true
    validates :balance_after, presence: true, numericality: true
    validates :status, presence: true, inclusion: {
      in: %w[pending completed failed reversed expired]
    }

    # Scopes
    scope :completed, -> { where(status: "completed") }
    scope :pending, -> { where(status: "pending") }
    scope :by_type, ->(type) { where(transaction_type: type) }
    scope :credits_added, -> { where("amount > 0") }
    scope :credits_deducted, -> { where("amount < 0") }
    scope :for_reference, ->(type, id) { where(reference_type: type, reference_id: id) }
    scope :recent, ->(period = 30.days) { where("created_at >= ?", period.ago) }
    scope :expiring_soon, ->(within = 7.days) {
      where("expires_at IS NOT NULL AND expires_at <= ?", within.from_now)
        .where(status: "completed")
    }
    scope :ordered_by_time, -> { order(created_at: :desc) }

    # Class methods
    class << self
      def total_for_period(start_date, end_date)
        where(created_at: start_date..end_date)
          .completed
          .sum(:amount)
      end

      def usage_for_period(start_date, end_date)
        where(created_at: start_date..end_date)
          .completed
          .by_type("usage")
          .sum("ABS(amount)")
      end

      def purchases_for_period(start_date, end_date)
        where(created_at: start_date..end_date)
          .completed
          .by_type("purchase")
          .sum(:amount)
      end
    end

    # Instance methods
    def credit?
      amount.positive?
    end

    def debit?
      amount.negative?
    end

    def absolute_amount
      amount.abs
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def expiring_soon?(within = 7.days)
      expires_at.present? && expires_at <= within.from_now && !expired?
    end

    def can_reverse?
      status == "completed" && %w[purchase bonus adjustment].include?(transaction_type)
    end

    def reverse!(reason: nil, initiated_by: nil)
      return false unless can_reverse?

      transaction do
        # Create reversal transaction
        reversal = self.class.create!(
          account: account,
          account_credit: account_credit,
          transaction_type: "adjustment",
          amount: -amount,
          balance_before: account_credit.balance,
          balance_after: account_credit.balance - amount,
          description: "Reversal: #{reason || description}",
          status: "completed",
          related_transaction_id: id,
          initiated_by: initiated_by,
          metadata: { reversed_transaction_id: id, reason: reason }
        )

        # Update account credit balance
        if amount.positive?
          account_credit.deduct_credits(amount, transaction_type: "adjustment", description: "Reversal")
        else
          account_credit.add_credits(amount.abs, transaction_type: "adjustment", description: "Reversal")
        end

        # Mark this transaction as reversed
        update!(status: "reversed")

        reversal
      end
    rescue ActiveRecord::RecordInvalid
      false
    end

    def summary
      {
        id: id,
        transaction_type: transaction_type,
        amount: amount.to_f,
        balance_before: balance_before.to_f,
        balance_after: balance_after.to_f,
        description: description,
        status: status,
        reference_type: reference_type,
        reference_id: reference_id,
        credit_pack_id: credit_pack_id,
        initiated_by_id: initiated_by_id,
        expires_at: expires_at,
        created_at: created_at
      }
    end
  end
end
