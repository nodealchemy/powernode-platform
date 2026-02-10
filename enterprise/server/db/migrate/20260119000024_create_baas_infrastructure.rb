# frozen_string_literal: true

class CreateBaaSInfrastructure < ActiveRecord::Migration[8.0]
  def change
    # BaaS Tenants - External customers using billing-as-a-service
    create_table :baas_tenants, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "active"
      t.string :tier, null: false, default: "starter"
      t.string :environment, null: false, default: "production"

      # Tenant settings
      t.string :webhook_url
      t.string :webhook_secret
      t.string :default_currency, default: "usd"
      t.string :timezone, default: "UTC"

      # Branding
      t.jsonb :branding, default: {}

      # Limits based on tier
      t.integer :max_customers, default: 100
      t.integer :max_subscriptions, default: 500
      t.integer :max_api_requests_per_day, default: 10000
      t.integer :api_requests_today, default: 0
      t.date :api_requests_reset_date

      # Usage tracking
      t.bigint :total_customers, default: 0
      t.bigint :total_subscriptions, default: 0
      t.bigint :total_invoices, default: 0
      t.decimal :total_revenue_processed, precision: 15, scale: 2, default: 0

      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :slug, unique: true
      t.index :status
      t.index :tier
      t.check_constraint "status IN ('pending', 'active', 'suspended', 'terminated')", name: "baas_tenants_status_check"
      t.check_constraint "tier IN ('free', 'starter', 'pro', 'enterprise')", name: "baas_tenants_tier_check"
      t.check_constraint "environment IN ('development', 'staging', 'production')", name: "baas_tenants_environment_check"
    end

    # BaaS Billing Configurations - Tenant-specific billing settings
    create_table :baas_billing_configurations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :baas_tenant, type: :uuid, null: false, foreign_key: true, index: true

      # Payment gateway settings
      t.string :stripe_account_id
      t.string :stripe_account_status, default: "not_connected"
      t.boolean :stripe_connected, default: false
      t.string :paypal_merchant_id
      t.boolean :paypal_connected, default: false

      # Invoice settings
      t.string :invoice_prefix, default: "INV"
      t.integer :invoice_due_days, default: 30
      t.boolean :auto_invoice, default: true
      t.boolean :auto_charge, default: true

      # Tax settings
      t.boolean :tax_enabled, default: false
      t.string :tax_provider
      t.string :default_tax_rate_id

      # Dunning settings
      t.boolean :dunning_enabled, default: true
      t.integer :dunning_attempts, default: 3
      t.integer :dunning_interval_days, default: 3

      # Revenue share (platform takes a percentage)
      t.decimal :platform_fee_percentage, precision: 5, scale: 2, default: 2.9

      # Feature flags
      t.boolean :usage_billing_enabled, default: false
      t.boolean :metered_billing_enabled, default: false
      t.boolean :trial_enabled, default: true
      t.integer :default_trial_days, default: 14

      t.jsonb :settings, default: {}
      t.timestamps

      t.index :stripe_account_id, unique: true, where: "stripe_account_id IS NOT NULL"
    end

    # BaaS API Keys - Authentication for BaaS API
    create_table :baas_api_keys, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :baas_tenant, type: :uuid, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :key_prefix, null: false
      t.string :key_hash, null: false
      t.string :key_type, null: false, default: "secret"
      t.string :environment, null: false, default: "production"
      t.string :status, null: false, default: "active"

      # Permissions/scopes
      t.text :scopes, array: true, default: []

      # Rate limiting
      t.integer :rate_limit_per_minute, default: 100
      t.integer :rate_limit_per_day, default: 10000

      # Usage tracking
      t.bigint :total_requests, default: 0
      t.datetime :last_used_at

      # Expiration
      t.datetime :expires_at

      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :key_hash, unique: true
      t.index :key_prefix
      t.index :status
      t.index [ :baas_tenant_id, :environment ]
      t.check_constraint "key_type IN ('secret', 'publishable', 'restricted')", name: "baas_api_keys_key_type_check"
      t.check_constraint "status IN ('active', 'revoked', 'expired')", name: "baas_api_keys_status_check"
      t.check_constraint "environment IN ('development', 'staging', 'production')", name: "baas_api_keys_environment_check"
    end

    # BaaS Usage Records - Usage event tracking for metered billing
    create_table :baas_usage_records, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :baas_tenant, type: :uuid, null: false, foreign_key: true, index: true
      t.string :customer_external_id, null: false
      t.string :subscription_external_id
      t.string :meter_id, null: false
      t.string :idempotency_key

      # Usage data
      t.decimal :quantity, precision: 15, scale: 4, null: false
      t.string :action, null: false, default: "increment"
      t.datetime :event_timestamp, null: false

      # Billing period
      t.date :billing_period_start
      t.date :billing_period_end

      # Processing status
      t.string :status, null: false, default: "pending"
      t.datetime :processed_at
      t.string :invoice_id

      t.jsonb :properties, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"
      t.index [ :baas_tenant_id, :customer_external_id ]
      t.index [ :baas_tenant_id, :meter_id, :event_timestamp ]
      t.index [ :baas_tenant_id, :status ]
      t.index :event_timestamp
      t.check_constraint "action IN ('set', 'increment')", name: "baas_usage_records_action_check"
      t.check_constraint "status IN ('pending', 'processed', 'invoiced', 'failed')", name: "baas_usage_records_status_check"
    end

    # BaaS Customers - External customers belonging to a tenant
    create_table :baas_customers, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :baas_tenant, type: :uuid, null: false, foreign_key: true, index: true
      t.string :external_id, null: false
      t.string :email
      t.string :name
      t.string :status, null: false, default: "active"

      # Payment info
      t.string :stripe_customer_id
      t.string :default_payment_method_id

      # Address
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :state
      t.string :postal_code
      t.string :country

      # Tax info
      t.string :tax_id
      t.string :tax_id_type
      t.boolean :tax_exempt, default: false

      # Billing info
      t.string :currency, default: "usd"
      t.integer :balance_cents, default: 0

      t.jsonb :metadata, default: {}
      t.timestamps

      t.index [ :baas_tenant_id, :external_id ], unique: true
      t.index [ :baas_tenant_id, :email ]
      t.index :stripe_customer_id, unique: true, where: "stripe_customer_id IS NOT NULL"
      t.check_constraint "status IN ('active', 'archived', 'deleted')", name: "baas_customers_status_check"
    end

    # BaaS Subscriptions - Subscriptions for BaaS customers
    create_table :baas_subscriptions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :baas_tenant, type: :uuid, null: false, foreign_key: true, index: true
      t.references :baas_customer, type: :uuid, null: false, foreign_key: true, index: true
      t.string :external_id, null: false
      t.string :plan_external_id, null: false
      t.string :status, null: false, default: "active"

      # Stripe integration
      t.string :stripe_subscription_id
      t.string :stripe_price_id

      # Billing cycle
      t.string :billing_interval, null: false, default: "month"
      t.integer :billing_interval_count, default: 1
      t.date :current_period_start
      t.date :current_period_end
      t.datetime :trial_end

      # Pricing
      t.decimal :unit_amount, precision: 10, scale: 2
      t.string :currency, default: "usd"
      t.integer :quantity, default: 1

      # Cancellation
      t.boolean :cancel_at_period_end, default: false
      t.datetime :canceled_at
      t.datetime :ended_at
      t.string :cancellation_reason

      t.jsonb :metadata, default: {}
      t.timestamps

      t.index [ :baas_tenant_id, :external_id ], unique: true
      t.index :stripe_subscription_id, unique: true, where: "stripe_subscription_id IS NOT NULL"
      t.index :status
      t.check_constraint "status IN ('incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'canceled', 'unpaid', 'paused')", name: "baas_subscriptions_status_check"
      t.check_constraint "billing_interval IN ('day', 'week', 'month', 'year')", name: "baas_subscriptions_billing_interval_check"
    end

    # BaaS Invoices - Invoices for BaaS customers
    create_table :baas_invoices, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :baas_tenant, type: :uuid, null: false, foreign_key: true, index: true
      t.references :baas_customer, type: :uuid, null: false, foreign_key: true, index: true
      t.references :baas_subscription, type: :uuid, foreign_key: true, index: true
      t.string :external_id, null: false
      t.string :number
      t.string :status, null: false, default: "draft"

      # Stripe integration
      t.string :stripe_invoice_id

      # Amounts (all in cents)
      t.integer :subtotal_cents, default: 0
      t.integer :tax_cents, default: 0
      t.integer :discount_cents, default: 0
      t.integer :total_cents, default: 0
      t.integer :amount_paid_cents, default: 0
      t.integer :amount_due_cents, default: 0
      t.string :currency, default: "usd"

      # Dates
      t.datetime :due_date
      t.datetime :paid_at
      t.datetime :voided_at

      # Billing period
      t.date :period_start
      t.date :period_end

      # PDF and hosted invoice
      t.string :invoice_pdf_url
      t.string :hosted_invoice_url

      t.jsonb :line_items, default: []
      t.jsonb :metadata, default: {}
      t.timestamps

      t.index [ :baas_tenant_id, :external_id ], unique: true
      t.index :stripe_invoice_id, unique: true, where: "stripe_invoice_id IS NOT NULL"
      t.index :number
      t.index :status
      t.check_constraint "status IN ('draft', 'open', 'paid', 'void', 'uncollectible')", name: "baas_invoices_status_check"
    end
  end
end
