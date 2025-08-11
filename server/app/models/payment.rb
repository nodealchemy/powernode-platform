class Payment < ApplicationRecord
  include AASM

  # Associations
  belongs_to :invoice
  has_one :subscription, through: :invoice
  has_one :account, through: :subscription

  # Validations
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP] }
  validates :payment_method, presence: true, inclusion: {
    in: %w[stripe_card stripe_bank paypal bank_transfer check]
  }
  validates :status, presence: true, inclusion: {
    in: %w[pending processing succeeded failed canceled refunded partially_refunded]
  }

  # Serialization
  serialize :metadata, coder: JSON

  # PayPal helper methods
  def paypal?
    payment_method == 'paypal'
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
  scope :by_method, ->(method) { where(payment_method: method) }
  scope :stripe_payments, -> { where(payment_method: [ "stripe_card", "stripe_bank" ]) }
  scope :paypal_payments, -> { where(payment_method: "paypal") }

  # Callbacks
  before_save :calculate_net_amount
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
        invoice.mark_paid! if invoice.may_mark_paid?
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
    Money.new(gateway_fee_cents || 0, currency)
  end

  def net_amount
    Money.new(net_amount_cents || amount_cents, currency)
  end

  def provider
    case payment_method
    when "stripe_card", "stripe_bank"
      "stripe"
    when "paypal"
      "paypal"
    else
      "manual"
    end
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

  def calculate_net_amount
    if gateway_fee_cents.present?
      self.net_amount_cents = amount_cents - gateway_fee_cents
    else
      self.net_amount_cents = amount_cents
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
  end
end
