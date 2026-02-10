# frozen_string_literal: true

# Credit Pack Model - Available credit packages for purchase
#
# Defines the credit packages available for purchase.
# Supports standard, bulk, enterprise, promotional, and reseller packs.
#
module Ai
  class CreditPack < ApplicationRecord
    self.table_name = "ai_credit_packs"

    # Associations
    has_many :credit_transactions, class_name: "Ai::CreditTransaction", dependent: :nullify
    has_many :credit_purchases, class_name: "Ai::CreditPurchase", dependent: :restrict_with_error

    # Validations
    validates :name, presence: true, length: { maximum: 100 }
    validates :pack_type, presence: true, inclusion: {
      in: %w[standard bulk enterprise promotional reseller]
    }
    validates :credits, presence: true, numericality: { greater_than: 0 }
    validates :price_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :bonus_credits, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :min_purchase_quantity, numericality: { greater_than: 0 }, allow_nil: true
    validates :max_purchase_quantity, numericality: { greater_than: 0 }, allow_nil: true

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :featured, -> { where(is_featured: true) }
    scope :by_type, ->(type) { where(pack_type: type) }
    scope :currently_valid, -> {
      now = Time.current
      where("valid_from IS NULL OR valid_from <= ?", now)
        .where("valid_until IS NULL OR valid_until >= ?", now)
    }
    scope :ordered, -> { order(sort_order: :asc, price_usd: :asc) }
    scope :for_display, -> { active.currently_valid.ordered }

    # Callbacks
    before_save :calculate_effective_price

    # Instance methods
    def total_credits
      credits + (bonus_credits || 0)
    end

    def price_per_credit
      return 0 if total_credits.zero?
      price_usd / total_credits
    end

    def calculate_effective_price
      self.effective_price_per_credit = price_per_credit
    end

    def currently_valid?
      now = Time.current
      (valid_from.nil? || valid_from <= now) &&
        (valid_until.nil? || valid_until >= now)
    end

    def available_for_purchase?
      is_active? && currently_valid?
    end

    def can_purchase_quantity?(quantity)
      return false unless available_for_purchase?
      return false if min_purchase_quantity && quantity < min_purchase_quantity
      return false if max_purchase_quantity && quantity > max_purchase_quantity
      true
    end

    def calculate_price(quantity)
      {
        quantity: quantity,
        credits_per_pack: credits,
        bonus_per_pack: bonus_credits || 0,
        total_credits: total_credits * quantity,
        unit_price: price_usd,
        total_price: price_usd * quantity,
        effective_price_per_credit: price_per_credit
      }
    end

    def summary
      {
        id: id,
        name: name,
        description: description,
        pack_type: pack_type,
        credits: credits,
        bonus_credits: bonus_credits,
        total_credits: total_credits,
        price_usd: price_usd.to_f,
        price_per_credit: price_per_credit.to_f,
        is_active: is_active,
        is_featured: is_featured
      }
    end
  end
end
