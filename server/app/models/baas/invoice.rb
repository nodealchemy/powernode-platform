# frozen_string_literal: true

module BaaS
  class Invoice < ApplicationRecord
    self.table_name = "baas_invoices"

    # Associations
    belongs_to :baas_tenant, class_name: "BaaS::Tenant"
    belongs_to :baas_customer, class_name: "BaaS::Customer"
    belongs_to :baas_subscription, class_name: "BaaS::Subscription", optional: true

    # Validations
    validates :external_id, presence: true, uniqueness: { scope: :baas_tenant_id }
    validates :status, presence: true, inclusion: { in: %w[draft open paid void uncollectible] }

    # Scopes
    scope :draft, -> { where(status: "draft") }
    scope :open, -> { where(status: "open") }
    scope :paid, -> { where(status: "paid") }
    scope :void, -> { where(status: "void") }
    scope :uncollectible, -> { where(status: "uncollectible") }
    scope :unpaid, -> { where(status: %w[open]) }
    scope :overdue, -> { open.where("due_date < ?", Time.current) }
    scope :for_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

    # Callbacks
    before_validation :generate_number, on: :create
    after_create :increment_tenant_counter

    # Instance methods
    def draft?
      status == "draft"
    end

    def open?
      status == "open"
    end

    def paid?
      status == "paid"
    end

    def void?
      status == "void"
    end

    def overdue?
      open? && due_date.present? && due_date < Time.current
    end

    def finalize!
      return false unless draft?
      update!(status: "open")
    end

    def mark_paid!(payment_reference: nil)
      return false unless open?
      update!(
        status: "paid",
        paid_at: Time.current,
        amount_paid_cents: total_cents,
        amount_due_cents: 0
      )

      # Record revenue for tenant
      baas_tenant.record_revenue(total_cents / 100.0)
    end

    def void!(reason: nil)
      return false if paid?
      update!(
        status: "void",
        voided_at: Time.current,
        metadata: metadata.merge(void_reason: reason)
      )
    end

    def add_line_item(description:, amount_cents:, quantity: 1, metadata: {})
      item = {
        id: SecureRandom.uuid,
        description: description,
        unit_amount_cents: amount_cents,
        quantity: quantity,
        amount_cents: amount_cents * quantity,
        metadata: metadata
      }

      self.line_items = (line_items || []) << item
      recalculate_totals!
      item
    end

    def remove_line_item(item_id)
      self.line_items = line_items.reject { |item| item["id"] == item_id }
      recalculate_totals!
    end

    def recalculate_totals!
      self.subtotal_cents = line_items.sum { |item| item["amount_cents"] || 0 }
      self.total_cents = subtotal_cents + tax_cents - discount_cents
      self.amount_due_cents = total_cents - amount_paid_cents
      save!
    end

    def subtotal
      subtotal_cents / 100.0
    end

    def total
      total_cents / 100.0
    end

    def amount_due
      amount_due_cents / 100.0
    end

    def amount_paid
      amount_paid_cents / 100.0
    end

    def days_until_due
      return nil unless due_date
      ((due_date - Time.current) / 1.day).ceil
    end

    def summary
      {
        id: id,
        external_id: external_id,
        number: number,
        customer_id: baas_customer.external_id,
        subscription_id: baas_subscription&.external_id,
        status: status,
        currency: currency,
        subtotal_cents: subtotal_cents,
        tax_cents: tax_cents,
        discount_cents: discount_cents,
        total_cents: total_cents,
        amount_paid_cents: amount_paid_cents,
        amount_due_cents: amount_due_cents,
        due_date: due_date,
        paid_at: paid_at,
        period: {
          start: period_start,
          end: period_end
        },
        line_items_count: line_items.size,
        invoice_pdf_url: invoice_pdf_url,
        hosted_invoice_url: hosted_invoice_url,
        created_at: created_at
      }
    end

    private

    def generate_number
      return if number.present?
      return unless baas_tenant.present?

      config = baas_tenant.billing_configuration
      prefix = config&.invoice_prefix || "INV"
      sequence = baas_tenant.total_invoices + 1

      self.number = "#{prefix}-#{sequence.to_s.rjust(6, '0')}"
    end

    def increment_tenant_counter
      baas_tenant.increment_invoice_count!
    end
  end
end
