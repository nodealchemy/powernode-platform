# frozen_string_literal: true

class Invoice < ApplicationRecord
  include AASM

  # Associations
  belongs_to :subscription
  has_one :account, through: :subscription
  has_many :invoice_line_items, dependent: :destroy
  has_many :payments, dependent: :destroy

  # Validations
  validates :invoice_number, presence: true, uniqueness: true
  validates :subtotal_cents, :tax_cents, :total_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP] }
  validates :status, presence: true, inclusion: { in: %w[draft open paid void uncollectible] }
  validates :tax_rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than: 1 }

  # Note: metadata and billing_address are native JSON columns - no serialization needed in Rails 8

  # Scopes
  scope :draft, -> { where(status: "draft") }
  scope :open, -> { where(status: "open") }
  scope :paid, -> { where(status: "paid") }
  scope :overdue, -> { where(status: "open").where("due_date < ?", Time.current) }
  scope :due_soon, -> { where(status: "open").where(due_date: Time.current..7.days.from_now) }

  # Callbacks
  before_validation :generate_invoice_number, on: :create
  before_save :calculate_totals
  after_initialize :set_defaults

  # Money attributes
  monetize :subtotal_cents, :tax_cents, :total_cents

  # State Machine
  aasm column: :status do
    state :draft, initial: true
    state :open
    state :paid
    state :void
    state :uncollectible

    event :finalize do
      transitions from: :draft, to: :open
      after do
        self.due_date ||= 30.days.from_now
      end
    end

    event :mark_paid do
      transitions from: [ :open, :uncollectible ], to: :paid
      after do
        self.paid_at = Time.current
      end
    end

    event :void do
      transitions from: [ :draft, :open ], to: :void
    end

    event :mark_uncollectible do
      transitions from: :open, to: :uncollectible
    end
  end

  # Instance methods
  def paid?
    status == "paid"
  end

  def overdue?
    status == "open" && due_date.present? && due_date < Time.current
  end

  def days_overdue
    return 0 unless overdue?
    (Time.current.to_date - due_date.to_date).to_i
  end

  def days_until_due
    return 0 unless due_date && status == "open"
    (due_date.to_date - Time.current.to_date).to_i
  end

  def subtotal
    Money.new(subtotal_cents, currency)
  end

  def tax_amount
    Money.new(tax_cents, currency)
  end

  def total
    Money.new(total_cents, currency)
  end

  def payment_provider
    return "stripe" if stripe_invoice_id.present?
    return "paypal" if paypal_invoice_id.present?
    "none"
  end

  def add_line_item(description:, quantity: 1, unit_price_cents: 0, **options)
    invoice_line_items.build(
      description: description,
      quantity: quantity,
      unit_price_cents: unit_price_cents,
      total_cents: quantity * unit_price_cents,
      **options
    )
  end

  def add_subscription_line_item(plan, quantity = 1, period_start = nil, period_end = nil)
    add_line_item(
      description: "#{plan.name} (#{plan.billing_cycle})",
      quantity: quantity,
      unit_price_cents: plan.price_cents,
      line_type: "subscription",
      period_start: period_start || subscription.current_period_start,
      period_end: period_end || subscription.current_period_end
    )
  end

  private

  def generate_invoice_number
    return if invoice_number.present?

    date_prefix = Time.current.strftime("%Y%m")
    last_invoice = Invoice.where("invoice_number LIKE ?", "INV-#{date_prefix}%")
                         .order(:invoice_number)
                         .last

    if last_invoice
      sequence = last_invoice.invoice_number.split("-").last.to_i + 1
    else
      sequence = 1
    end

    self.invoice_number = "INV-#{date_prefix}-#{sequence.to_s.rjust(4, '0')}"
  end

  def calculate_totals
    self.subtotal_cents = invoice_line_items.sum(&:total_cents)
    self.tax_cents = (subtotal_cents * tax_rate).round
    self.total_cents = subtotal_cents + tax_cents
  end

  def set_defaults
    self.metadata ||= {}
    self.currency ||= subscription&.plan&.currency || "USD"
  end
end
