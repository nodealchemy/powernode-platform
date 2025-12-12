# frozen_string_literal: true

class Payment < ApplicationRecord
  include AASM

  # Associations
  belongs_to :account
  belongs_to :invoice
  belongs_to :payment_method, optional: true

  # Delegated associations for convenience
  has_one :subscription, through: :invoice

  # Validations
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP] }
  validates :status, presence: true, inclusion: {
    in: %w[pending processing succeeded failed canceled refunded partially_refunded]
  }
  validates :gateway, presence: true, inclusion: { in: %w[stripe paypal] }
  validate :account_matches_invoice_account

  # Note: metadata is a native JSON column - no serialization needed in Rails 8

  # PayPal helper methods
  def paypal?
    gateway == "paypal"
  end

  def add_metadata(key, value)
    self.metadata = (metadata || {}).merge(key => value)
    save! if persisted?
  end

  def metadata_parsed
    metadata || {}
  end

  # Scopes
  scope :succeeded, -> { where(status: "succeeded") }
  scope :failed, -> { where(status: "failed") }
  scope :pending, -> { where(status: "pending") }
  scope :by_gateway, ->(gateway) { where(gateway: gateway) }
  scope :stripe_payments, -> { where(gateway: "stripe") }
  scope :paypal_payments, -> { where(gateway: "paypal") }

  # Callbacks
  before_validation :normalize_currency
  after_initialize :set_defaults

  # Money attributes (removed monetize for now due to validation conflicts)

  # State Machine
  aasm column: :status do
    state :pending, initial: true
    state :processing
    state :succeeded
    state :failed
    state :canceled
    state :refunded
    state :partially_refunded

    event :process do
      transitions from: :pending, to: :processing
    end

    event :succeed do
      transitions from: [ :pending, :processing ], to: :succeeded
      after do
        self.processed_at = Time.current
        invoice.mark_paid! if invoice.open? || invoice.uncollectible?
      end
    end

    event :fail do
      transitions from: [ :pending, :processing ], to: :failed
      after do
        self.failed_at = Time.current
      end
    end

    event :cancel do
      transitions from: [ :pending, :processing ], to: :canceled
    end

    event :refund do
      transitions from: :succeeded, to: :refunded
    end

    event :partially_refund do
      transitions from: :succeeded, to: :partially_refunded
    end
  end

  # Instance methods
  def amount
    Money.new(amount_cents, currency)
  end

  def gateway_fee
    # Gateway fees stored in metadata if available
    fee_cents = metadata.dig("gateway_fee_cents") || 0
    Money.new(fee_cents.to_i, currency)
  end

  def net_amount
    # Calculate net amount by subtracting gateway fees from gross amount
    net_cents = amount_cents - gateway_fee.cents
    Money.new(net_cents, currency)
  end

  def provider
    gateway
  end

  def gateway_transaction_id
    case provider
    when "stripe"
      metadata["stripe_payment_intent_id"] || metadata["stripe_charge_id"]
    when "paypal"
      metadata["paypal_order_id"] || metadata["paypal_capture_id"]
    else
      nil
    end
  end

  def processing_time
    return nil unless processed_at && created_at
    processed_at - created_at
  end

  def can_be_refunded?
    succeeded? && !refunded? && !partially_refunded?
  end

  def refundable_amount
    return Money.new(0, currency) unless can_be_refunded?
    amount
  end

  private

  def account_matches_invoice_account
    return unless invoice && account

    if invoice.account_id != account_id
      errors.add(:account, "must match the invoice's account")
    end
  end

  def set_defaults
    self.metadata ||= {}
    # Always inherit currency from invoice if available
    if invoice&.currency.present?
      self.currency = invoice.currency
    else
      self.currency ||= "USD"
    end
    # Always normalize currency to uppercase
    self.currency = currency&.upcase if currency.present?
  end

  def normalize_currency
    self.currency = currency&.upcase if currency.present?
  end
end
