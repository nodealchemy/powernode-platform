# frozen_string_literal: true

class PaymentMethod < ApplicationRecord
  belongs_to :account

  validates :gateway, presence: true, inclusion: { in: %w[stripe paypal] }
  validates :external_id, presence: true
  validates :payment_type, presence: true, inclusion: {
    in: %w[card bank paypal apple_pay google_pay]
  }

  scope :for_gateway, ->(gateway) { where(gateway: gateway) }

  def stripe?
    gateway == "stripe"
  end

  def paypal?
    gateway == "paypal"
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

  def apple_pay?
    payment_type == "apple_pay"
  end

  def google_pay?
    payment_type == "google_pay"
  end

  def display_name
    case payment_type
    when "card"
      "Card •••• #{last_four}"
    when "bank"
      "Bank Account •••• #{last_four}"
    when "paypal"
      "PayPal"
    when "apple_pay"
      "Apple Pay"
    when "google_pay"
      "Google Pay"
    else
      "Payment Method"
    end
  end

  def can_be_used_for_recurring?
    case gateway
    when "stripe"
      %w[card bank apple_pay google_pay].include?(payment_type)
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