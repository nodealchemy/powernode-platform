# frozen_string_literal: true

# Account Credit Model - Credit balance per account
#
# Manages the credit balance for each account with support for:
# - Balance tracking (available, reserved)
# - Lifetime statistics
# - Reseller features
# - Credit limits and overdraft settings
#
module Ai
  class AccountCredit < ApplicationRecord
    self.table_name = "ai_account_credits"

    # Associations
    belongs_to :account
    has_many :credit_transactions, class_name: "Ai::CreditTransaction", dependent: :destroy

    # Validations
    validates :account_id, presence: true, uniqueness: true
    validates :balance, presence: true, numericality: true
    validates :reserved_balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :reseller_discount_percentage, numericality: {
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    }, allow_nil: true

    # Scopes
    scope :with_balance, -> { where("balance > 0") }
    scope :resellers, -> { where(is_reseller: true) }
    scope :low_balance, ->(threshold = 100) { where("balance < ?", threshold) }

    # Instance methods
    def available_balance
      balance - reserved_balance
    end

    def effective_balance
      if allow_negative_balance && credit_limit
        available_balance + credit_limit
      else
        available_balance
      end
    end

    def can_afford?(amount)
      effective_balance >= amount
    end

    def reserve_credits(amount, description: nil)
      return false unless can_afford?(amount)

      transaction do
        self.reserved_balance += amount
        save!

        credit_transactions.create!(
          account: account,
          transaction_type: "reservation",
          amount: -amount,
          balance_before: balance,
          balance_after: balance,
          description: description || "Credit reservation",
          status: "completed"
        )
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def release_reservation(amount, description: nil)
      return false if amount > reserved_balance

      transaction do
        self.reserved_balance -= amount
        save!

        credit_transactions.create!(
          account: account,
          transaction_type: "release",
          amount: amount,
          balance_before: balance,
          balance_after: balance,
          description: description || "Credit release",
          status: "completed"
        )
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def add_credits(amount, transaction_type: "purchase", description: nil, credit_pack: nil, initiated_by: nil, metadata: {})
      return false unless amount.positive?

      transaction do
        old_balance = balance
        self.balance += amount

        case transaction_type
        when "purchase"
          self.lifetime_credits_purchased += amount
          self.last_purchase_at = Time.current
        when "transfer_in"
          self.lifetime_credits_transferred_in += amount
        when "bonus", "adjustment", "refund"
          # Just update balance
        end

        save!

        credit_transactions.create!(
          account: account,
          transaction_type: transaction_type,
          amount: amount,
          balance_before: old_balance,
          balance_after: balance,
          description: description,
          credit_pack: credit_pack,
          initiated_by: initiated_by,
          status: "completed",
          metadata: metadata,
          processed_at: Time.current
        )
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def deduct_credits(amount, transaction_type: "usage", description: nil, reference_type: nil, reference_id: nil, metadata: {})
      return false unless amount.positive?
      return false unless can_afford?(amount)

      transaction do
        old_balance = balance
        self.balance -= amount

        case transaction_type
        when "usage"
          self.lifetime_credits_used += amount
          self.last_usage_at = Time.current
        when "transfer_out"
          self.lifetime_credits_transferred_out += amount
        when "expiration"
          self.lifetime_credits_expired += amount
        end

        save!

        credit_transactions.create!(
          account: account,
          transaction_type: transaction_type,
          amount: -amount,
          balance_before: old_balance,
          balance_after: balance,
          description: description,
          reference_type: reference_type,
          reference_id: reference_id,
          status: "completed",
          metadata: metadata,
          processed_at: Time.current
        )
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def usage_rate
      return 0 if lifetime_credits_purchased.zero?
      (lifetime_credits_used / lifetime_credits_purchased * 100).round(2)
    end

    def summary
      {
        id: id,
        account_id: account_id,
        balance: balance.to_f,
        reserved_balance: reserved_balance.to_f,
        available_balance: available_balance.to_f,
        is_reseller: is_reseller,
        reseller_discount_percentage: reseller_discount_percentage&.to_f,
        lifetime: {
          purchased: lifetime_credits_purchased.to_f,
          used: lifetime_credits_used.to_f,
          expired: lifetime_credits_expired.to_f,
          transferred_in: lifetime_credits_transferred_in.to_f,
          transferred_out: lifetime_credits_transferred_out.to_f
        },
        last_purchase_at: last_purchase_at,
        last_usage_at: last_usage_at
      }
    end
  end
end
