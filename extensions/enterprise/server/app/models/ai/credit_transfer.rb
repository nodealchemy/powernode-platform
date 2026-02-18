# frozen_string_literal: true

# Credit Transfer Model - B2B credit transfers between accounts
#
# Enables reseller model with credit transfers between accounts.
#
module Ai
  class CreditTransfer < ApplicationRecord
    self.table_name = "ai_credit_transfers"

    # Associations
    belongs_to :from_account, class_name: "Account"
    belongs_to :to_account, class_name: "Account"
    belongs_to :initiated_by, class_name: "User"
    belongs_to :approved_by, class_name: "User", optional: true

    # Validations
    validates :amount, presence: true, numericality: { greater_than: 0 }
    validates :net_amount, presence: true, numericality: { greater_than: 0 }
    validates :reference_code, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: {
      in: %w[pending approved completed rejected cancelled failed]
    }
    validate :different_accounts
    validate :sufficient_balance, on: :create

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :completed, -> { where(status: "completed") }
    scope :for_account, ->(account) {
      where(from_account: account).or(where(to_account: account))
    }
    scope :outgoing, ->(account) { where(from_account: account) }
    scope :incoming, ->(account) { where(to_account: account) }
    scope :recent, ->(period = 30.days) { where("created_at >= ?", period.ago) }

    # Callbacks
    before_validation :generate_reference_code, on: :create
    before_validation :calculate_fee, on: :create

    # Instance methods
    def approve!(approved_by_user)
      return false unless status == "pending"

      update!(
        status: "approved",
        approved_by: approved_by_user,
        approved_at: Time.current
      )
    end

    def complete!
      return false unless status == "approved" || status == "pending"

      transaction do
        from_credit = from_account.ai_account_credits
        to_credit = to_account.ai_account_credits || to_account.create_ai_account_credits!

        return false unless from_credit&.can_afford?(amount)

        # Deduct from sender
        from_credit.deduct_credits(
          amount,
          transaction_type: "transfer_out",
          description: "Transfer to #{to_account.name}",
          reference_type: "CreditTransfer",
          reference_id: id,
          metadata: { to_account_id: to_account_id, reference_code: reference_code }
        )

        # Add to receiver (minus fee)
        to_credit.add_credits(
          net_amount,
          transaction_type: "transfer_in",
          description: "Transfer from #{from_account.name}",
          initiated_by: initiated_by,
          metadata: { from_account_id: from_account_id, reference_code: reference_code, fee: fee_amount }
        )

        update!(
          status: "completed",
          completed_at: Time.current
        )

        true
      end
    rescue ActiveRecord::RecordInvalid
      update(status: "failed")
      false
    end

    def cancel!(reason: nil)
      return false unless %w[pending approved].include?(status)

      update!(
        status: "cancelled",
        cancelled_at: Time.current,
        cancellation_reason: reason
      )
    end

    def reject!(reason: nil)
      return false unless status == "pending"

      update!(
        status: "rejected",
        cancellation_reason: reason
      )
    end

    def summary
      {
        id: id,
        reference_code: reference_code,
        from_account_id: from_account_id,
        from_account_name: from_account.name,
        to_account_id: to_account_id,
        to_account_name: to_account.name,
        amount: amount.to_f,
        fee_percentage: fee_percentage.to_f,
        fee_amount: fee_amount.to_f,
        net_amount: net_amount.to_f,
        status: status,
        description: description,
        initiated_by_id: initiated_by_id,
        approved_at: approved_at,
        completed_at: completed_at,
        created_at: created_at
      }
    end

    private

    def generate_reference_code
      self.reference_code ||= "TRF-#{SecureRandom.hex(8).upcase}"
    end

    def calculate_fee
      self.fee_percentage ||= 0
      self.fee_amount = (amount * fee_percentage / 100).round(4)
      self.net_amount = amount - fee_amount
    end

    def different_accounts
      if from_account_id == to_account_id
        errors.add(:to_account, "must be different from source account")
      end
    end

    def sufficient_balance
      return unless from_account

      from_credit = from_account.ai_account_credits
      unless from_credit&.can_afford?(amount)
        errors.add(:amount, "exceeds available balance")
      end
    end
  end
end
