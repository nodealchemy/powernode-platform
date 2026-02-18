# frozen_string_literal: true

module BaaS
  class Customer < ApplicationRecord
    self.table_name = "baas_customers"

    # Associations
    belongs_to :baas_tenant, class_name: "BaaS::Tenant"
    has_many :subscriptions, class_name: "BaaS::Subscription", foreign_key: :baas_customer_id, dependent: :destroy
    has_many :invoices, class_name: "BaaS::Invoice", foreign_key: :baas_customer_id, dependent: :destroy

    # Validations
    validates :external_id, presence: true, uniqueness: { scope: :baas_tenant_id }
    validates :status, presence: true, inclusion: { in: %w[active archived deleted] }
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :archived, -> { where(status: "archived") }

    # Callbacks
    after_create :increment_tenant_counter
    after_destroy :decrement_tenant_counter

    # Instance methods
    def active?
      status == "active"
    end

    def archived?
      status == "archived"
    end

    def archive!
      update!(status: "archived")
    end

    def reactivate!
      update!(status: "active")
    end

    def has_active_subscriptions?
      subscriptions.where(status: "active").exists?
    end

    def total_spent
      invoices.where(status: "paid").sum(:total_cents) / 100.0
    end

    def add_balance(amount_cents)
      increment!(:balance_cents, amount_cents)
    end

    def deduct_balance(amount_cents)
      new_balance = [ balance_cents - amount_cents, 0 ].max
      update!(balance_cents: new_balance)
    end

    def full_address
      [ address_line1, address_line2, city, state, postal_code, country ]
        .compact
        .reject(&:blank?)
        .join(", ")
    end

    def summary
      {
        id: id,
        external_id: external_id,
        email: email,
        name: name,
        status: status,
        currency: currency,
        balance_cents: balance_cents,
        stripe_customer_id: stripe_customer_id,
        active_subscriptions: subscriptions.where(status: "active").count,
        total_invoices: invoices.count,
        created_at: created_at
      }
    end

    private

    def increment_tenant_counter
      baas_tenant.increment_customer_count!
    end

    def decrement_tenant_counter
      baas_tenant.decrement_customer_count!
    end
  end
end
