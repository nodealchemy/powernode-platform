# frozen_string_literal: true

class PaymentMethod < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :provider, presence: true, inclusion: { in: %w[stripe paypal] }
  validates :external_id, presence: true
  validates :payment_type, presence: true, inclusion: {
    in: %w[card bank paypal apple_pay google_pay]
  }

  scope :for_provider, ->(provider) { where(provider: provider) }

  def stripe?
    provider == "stripe"
  end

  def paypal?
    provider == "paypal"
  end

  def card?
    payment_type == "card"
  end

  def bank_account?
    payment_type == "bank"
  end

  def paypal_account?
    payment_type == "paypal"
  end

  def display_name
    case payment_type
    when "card"
      "Card •••• #{last_four}"
    when "bank"
      "Bank Account •••• #{last_four}"
    when "paypal"
      "PayPal"
    else
      "Payment Method"
    end
  end

  def can_be_used_for_recurring?
    case provider
    when "stripe"
      %w[card bank].include?(payment_type)
    when "paypal"
      paypal_account?
    else
      false
    end
  end

  def deactivate!
    update!(is_default: false)
  end
end
