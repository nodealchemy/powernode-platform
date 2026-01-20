# frozen_string_literal: true

module BaaS
  class Tenant < ApplicationRecord
    self.table_name = "baas_tenants"

    # Associations
    belongs_to :account
    has_one :billing_configuration, class_name: "BaaS::BillingConfiguration", foreign_key: :baas_tenant_id, dependent: :destroy
    has_many :api_keys, class_name: "BaaS::ApiKey", foreign_key: :baas_tenant_id, dependent: :destroy
    has_many :usage_records, class_name: "BaaS::UsageRecord", foreign_key: :baas_tenant_id, dependent: :destroy
    has_many :customers, class_name: "BaaS::Customer", foreign_key: :baas_tenant_id, dependent: :destroy
    has_many :subscriptions, class_name: "BaaS::Subscription", foreign_key: :baas_tenant_id, dependent: :destroy
    has_many :invoices, class_name: "BaaS::Invoice", foreign_key: :baas_tenant_id, dependent: :destroy

    # Validations
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
    validates :status, presence: true, inclusion: { in: %w[pending active suspended terminated] }
    validates :tier, presence: true, inclusion: { in: %w[free starter pro enterprise] }
    validates :environment, presence: true, inclusion: { in: %w[development staging production] }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :by_tier, ->(tier) { where(tier: tier) }

    # Callbacks
    before_validation :generate_slug, on: :create
    after_create :create_default_billing_configuration

    # Tier limits
    TIER_LIMITS = {
      "free" => { max_customers: 25, max_subscriptions: 50, max_api_requests_per_day: 1000 },
      "starter" => { max_customers: 100, max_subscriptions: 500, max_api_requests_per_day: 10_000 },
      "pro" => { max_customers: 1000, max_subscriptions: 5000, max_api_requests_per_day: 100_000 },
      "enterprise" => { max_customers: nil, max_subscriptions: nil, max_api_requests_per_day: nil }
    }.freeze

    # Instance methods
    def active?
      status == "active"
    end

    def suspended?
      status == "suspended"
    end

    def can_create_customer?
      return true if tier == "enterprise" || max_customers.nil?
      total_customers < max_customers
    end

    def can_create_subscription?
      return true if tier == "enterprise" || max_subscriptions.nil?
      total_subscriptions < max_subscriptions
    end

    def can_make_api_request?
      reset_api_requests_if_needed
      return true if tier == "enterprise" || max_api_requests_per_day.nil?
      api_requests_today < max_api_requests_per_day
    end

    def record_api_request!
      reset_api_requests_if_needed
      increment!(:api_requests_today)
    end

    def increment_customer_count!
      increment!(:total_customers)
    end

    def decrement_customer_count!
      decrement!(:total_customers) if total_customers > 0
    end

    def increment_subscription_count!
      increment!(:total_subscriptions)
    end

    def decrement_subscription_count!
      decrement!(:total_subscriptions) if total_subscriptions > 0
    end

    def increment_invoice_count!
      increment!(:total_invoices)
    end

    def record_revenue(amount)
      update!(total_revenue_processed: total_revenue_processed + amount)
    end

    def apply_tier_limits!
      limits = TIER_LIMITS[tier]
      return unless limits

      update!(
        max_customers: limits[:max_customers],
        max_subscriptions: limits[:max_subscriptions],
        max_api_requests_per_day: limits[:max_api_requests_per_day]
      )
    end

    def summary
      {
        id: id,
        name: name,
        slug: slug,
        status: status,
        tier: tier,
        environment: environment,
        total_customers: total_customers,
        total_subscriptions: total_subscriptions,
        total_invoices: total_invoices,
        total_revenue_processed: total_revenue_processed,
        created_at: created_at
      }
    end

    private

    def generate_slug
      return if slug.present?
      base_slug = name.to_s.parameterize
      self.slug = base_slug
      counter = 1
      while self.class.exists?(slug: slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def create_default_billing_configuration
      create_billing_configuration! unless billing_configuration
    end

    def reset_api_requests_if_needed
      if api_requests_reset_date.nil? || api_requests_reset_date < Date.current
        update!(api_requests_today: 0, api_requests_reset_date: Date.current)
      end
    end
  end
end
