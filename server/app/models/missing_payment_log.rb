# frozen_string_literal: true

class MissingPaymentLog < ApplicationRecord
  belongs_to :account

  validates :gateway, presence: true
  validates :external_payment_id, presence: true
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :detected_at, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending resolved matched ignored] }

  scope :pending, -> { where(status: "pending") }
  scope :resolved, -> { where(status: "resolved") }
  scope :recent, -> { order(detected_at: :desc) }

  def resolved?
    status == "resolved"
  end

  def days_pending
    return 0 if resolved?
    ((Time.current - detected_at) / 1.day).round
  end
end
