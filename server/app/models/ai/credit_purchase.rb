# frozen_string_literal: true

# Credit Purchase Model - Purchase records for credits
#
# Records credit pack purchases with payment tracking.
#
module Ai
  class CreditPurchase < ApplicationRecord
    self.table_name = "ai_credit_purchases"

    # Associations
    belongs_to :account
    belongs_to :credit_pack, class_name: "Ai::CreditPack"
    belongs_to :user, optional: true

    # Validations
    validates :quantity, presence: true, numericality: { greater_than: 0 }
    validates :credits_purchased, presence: true, numericality: { greater_than: 0 }
    validates :total_credits, presence: true, numericality: { greater_than: 0 }
    validates :unit_price_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :total_price_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :final_price_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :status, presence: true, inclusion: {
      in: %w[pending processing completed failed refunded partially_refunded]
    }

    # Scopes
    scope :completed, -> { where(status: "completed") }
    scope :pending, -> { where(status: "pending") }
    scope :for_account, ->(account) { where(account: account) }
    scope :recent, ->(period = 30.days) { where("created_at >= ?", period.ago) }
    scope :ordered_by_time, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :calculate_totals, on: :create

    # Instance methods
    def calculate_totals
      return unless credit_pack

      self.credits_purchased ||= credit_pack.credits * quantity
      self.bonus_credits ||= (credit_pack.bonus_credits || 0) * quantity
      self.total_credits ||= credits_purchased + bonus_credits
      self.unit_price_usd ||= credit_pack.price_usd
      self.total_price_usd ||= unit_price_usd * quantity
      self.discount_amount_usd ||= total_price_usd * (discount_percentage || 0) / 100
      self.final_price_usd ||= total_price_usd - discount_amount_usd
    end

    def complete!(payment_reference: nil)
      return false unless status == "pending" || status == "processing"

      transaction do
        update!(
          status: "completed",
          payment_reference: payment_reference,
          paid_at: Time.current,
          credits_applied_at: Time.current
        )

        # Add credits to account
        account_credit = account.ai_account_credits.first_or_create!
        account_credit.add_credits(
          total_credits,
          transaction_type: "purchase",
          description: "Purchase: #{credit_pack.name} x#{quantity}",
          credit_pack: credit_pack,
          initiated_by: user,
          metadata: { purchase_id: id }
        )

        true
      end
    rescue ActiveRecord::RecordInvalid
      false
    end

    def refund!(amount: nil, reason: nil)
      return false unless status == "completed"

      refund_amount = amount || final_price_usd
      refund_credits = (total_credits * refund_amount / final_price_usd).round(4)

      transaction do
        new_status = refund_amount >= final_price_usd ? "refunded" : "partially_refunded"
        update!(status: new_status)

        # Deduct credits from account
        account_credit = account.ai_account_credits.first
        if account_credit && account_credit.balance >= refund_credits
          account_credit.deduct_credits(
            refund_credits,
            transaction_type: "refund",
            description: "Refund: #{reason || 'Purchase refund'}",
            reference_type: "CreditPurchase",
            reference_id: id
          )
        end

        true
      end
    rescue ActiveRecord::RecordInvalid
      false
    end

    def summary
      {
        id: id,
        account_id: account_id,
        credit_pack: credit_pack&.summary,
        quantity: quantity,
        credits_purchased: credits_purchased.to_f,
        bonus_credits: bonus_credits.to_f,
        total_credits: total_credits.to_f,
        unit_price_usd: unit_price_usd.to_f,
        total_price_usd: total_price_usd.to_f,
        discount_percentage: discount_percentage.to_f,
        discount_amount_usd: discount_amount_usd.to_f,
        final_price_usd: final_price_usd.to_f,
        status: status,
        paid_at: paid_at,
        created_at: created_at
      }
    end
  end
end
