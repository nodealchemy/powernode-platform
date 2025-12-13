# frozen_string_literal: true

class CreateBillingSubscriptionSystem < ActiveRecord::Migration[8.0]
  def change
    # Create plans table - Subscription plans
    create_table :plans, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false, limit: 100
      t.string :slug, null: false, limit: 100
      t.text :description
      t.integer :price_cents, null: false, default: 0
      t.string :billing_interval, null: false, default: 'monthly', limit: 20
      t.string :billing_cycle, null: false, default: 'monthly', limit: 20
      t.string :status, null: false, default: 'active', limit: 20
      t.integer :trial_period_days, default: 0
      t.integer :trial_days, default: 0
      t.decimal :annual_discount_percent, precision: 5, scale: 2, default: 0.0
      t.decimal :promotional_discount_percent, precision: 5, scale: 2, default: 0.0
      t.string :promotional_discount_code
      t.datetime :promotional_discount_start
      t.datetime :promotional_discount_end
      t.boolean :is_active, default: true, null: false
      t.boolean :is_public, default: true, null: false
      t.jsonb :features, default: {}
      t.jsonb :limits, default: {}
      t.jsonb :metadata, default: {}
      t.jsonb :default_roles, default: []
      t.jsonb :volume_discount_tiers, default: []
      t.boolean :has_annual_discount, null: false, default: false
      t.boolean :has_volume_discount, null: false, default: false
      t.boolean :has_promotional_discount, null: false, default: false
      t.string :paypal_plan_id
      t.string :currency, limit: 3, default: 'USD'
      t.timestamps null: false

      t.index [ :slug ], unique: true, name: 'idx_plans_on_slug_unique'
      t.index [ :is_active ], name: 'idx_plans_on_is_active'
      t.index [ :is_public ], name: 'idx_plans_on_is_public'
      t.index [ :billing_interval ], name: 'idx_plans_on_billing_interval'
    end

    # Create subscriptions table
    create_table :subscriptions, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :plan, null: false, foreign_key: true, type: :uuid
      t.integer :quantity, null: false, default: 1
      t.string :status, null: false, limit: 50
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :trial_start
      t.datetime :trial_end
      t.datetime :canceled_at
      t.datetime :ended_at
      t.string :stripe_subscription_id, limit: 100
      t.string :paypal_subscription_id, limit: 100
      t.string :paypal_agreement_id
      t.string :paypal_plan_id
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :status ], name: 'idx_subscriptions_on_status'
      t.index [ :current_period_end ], name: 'idx_subscriptions_on_current_period_end'
      t.index [ :trial_end ], name: 'idx_subscriptions_on_trial_end'
      t.index [ :stripe_subscription_id ], unique: true, where: "stripe_subscription_id IS NOT NULL", name: 'idx_subscriptions_on_stripe_id_unique'
      t.index [ :paypal_subscription_id ], unique: true, where: "paypal_subscription_id IS NOT NULL", name: 'idx_subscriptions_on_paypal_id_unique'
    end

    # Create payment_methods table
    create_table :payment_methods, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :gateway, null: false, limit: 50
      t.string :external_id, null: false
      t.string :payment_type, null: false, limit: 50
      t.string :last_four, limit: 4
      t.string :brand, limit: 50
      t.integer :exp_month
      t.integer :exp_year
      t.string :cardholder_name
      t.boolean :is_default, default: false
      t.boolean :is_active, default: true
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :account_id, :is_default ], unique: true, where: "is_default = true", name: 'idx_payment_methods_on_account_default_unique'
      t.index [ :gateway, :external_id ], unique: true, name: 'idx_payment_methods_on_gateway_external_id_unique'
      t.index [ :is_active ], name: 'idx_payment_methods_on_is_active'
    end

    # Create payments table
    create_table :payments, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :subscription, null: true, foreign_key: true, type: :uuid
      t.references :payment_method, null: true, foreign_key: true, type: :uuid
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: 'usd', limit: 3
      t.string :status, null: false, limit: 50
      t.string :gateway, null: false, limit: 50
      t.string :external_id
      t.string :transaction_type, limit: 50
      t.text :failure_reason
      t.datetime :processed_at
      t.datetime :failed_at
      t.jsonb :gateway_response, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :status ], name: 'idx_payments_on_status'
      t.index [ :gateway, :external_id ], unique: true, where: "external_id IS NOT NULL", name: 'idx_payments_on_gateway_external_id_unique'
      t.index [ :processed_at ], name: 'idx_payments_on_processed_at'
      t.index [ :transaction_type ], name: 'idx_payments_on_transaction_type'
    end

    # Create invoices table
    create_table :invoices, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :subscription, null: true, foreign_key: true, type: :uuid
      t.string :invoice_number, null: false
      t.string :status, null: false, limit: 50
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.decimal :tax_rate, precision: 5, scale: 4, default: 0.0
      t.integer :total_cents, null: false, default: 0
      t.string :currency, null: false, default: 'usd', limit: 3
      t.datetime :issued_at
      t.datetime :due_at
      t.datetime :paid_at
      t.string :stripe_invoice_id, limit: 100
      t.string :paypal_invoice_id, limit: 100
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :invoice_number ], unique: true, name: 'idx_invoices_on_invoice_number_unique'
      t.index [ :status ], name: 'idx_invoices_on_status'
      t.index [ :issued_at ], name: 'idx_invoices_on_issued_at'
      t.index [ :due_at ], name: 'idx_invoices_on_due_at'
      t.index [ :paid_at ], name: 'idx_invoices_on_paid_at'
      t.index [ :stripe_invoice_id ], unique: true, where: "stripe_invoice_id IS NOT NULL", name: 'idx_invoices_on_stripe_id_unique'
      t.index [ :paypal_invoice_id ], unique: true, where: "paypal_invoice_id IS NOT NULL", name: 'idx_invoices_on_paypal_id_unique'
    end

    # Create invoice_line_items table
    create_table :invoice_line_items, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :invoice, null: false, foreign_key: true, type: :uuid
      t.references :plan, null: true, foreign_key: true, type: :uuid
      t.string :description, null: false
      t.string :line_type, null: false, default: 'subscription'
      t.integer :quantity, null: false, default: 1
      t.integer :unit_amount_cents, null: false
      t.integer :total_amount_cents, null: false
      t.datetime :period_start
      t.datetime :period_end
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :invoice_id ], name: 'idx_invoice_line_items_on_invoice_id'
      t.index [ :plan_id ], name: 'idx_invoice_line_items_on_plan_id'
    end

    # Add invoice reference to payments table after invoices table exists
    add_reference :payments, :invoice, type: :uuid, null: true, foreign_key: true

    # Create revenue_snapshots table - For analytics
    create_table :revenue_snapshots, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: true, foreign_key: true, type: :uuid
      t.date :snapshot_date, null: false
      t.string :period_type, null: false, limit: 20
      t.integer :mrr_cents, default: 0
      t.integer :arr_cents, default: 0
      t.integer :total_revenue_cents, default: 0
      t.integer :new_revenue_cents, default: 0
      t.integer :churned_revenue_cents, default: 0
      t.integer :active_subscriptions, default: 0
      t.integer :new_subscriptions, default: 0
      t.integer :churned_subscriptions, default: 0
      t.integer :total_customers_count, default: 0
      t.integer :new_customers_count, default: 0
      t.integer :churned_customers_count, default: 0
      t.integer :arpu_cents, default: 0
      t.integer :ltv_cents, default: 0
      t.decimal :growth_rate_percentage, precision: 5, scale: 2, default: 0
      t.decimal :customer_churn_rate_percentage, precision: 5, scale: 2, default: 0
      t.decimal :revenue_churn_rate_percentage, precision: 5, scale: 2, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :account_id, :snapshot_date, :period_type ], unique: true, name: 'index_revenue_snapshots_unique'
      t.index [ :snapshot_date ], name: 'idx_revenue_snapshots_on_snapshot_date'
      t.index [ :period_type ], name: 'idx_revenue_snapshots_on_period_type'
    end

    # Create gateway_configurations table
    create_table :gateway_configurations, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :provider, null: false, limit: 50
      t.string :key_name, null: false, limit: 100
      t.text :encrypted_value, null: false
      t.timestamps null: false

      t.index [ :provider, :key_name ], unique: true, name: 'idx_gateway_configurations_on_provider_key_unique'
      t.index [ :provider ], name: 'idx_gateway_configurations_on_provider'
    end

    # Create missing_payment_logs table - For reconciliation
    create_table :missing_payment_logs, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :gateway, null: false
      t.string :external_payment_id, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: 'usd'
      t.datetime :gateway_created_at
      t.datetime :detected_at, null: false
      t.string :status, default: 'pending'
      t.jsonb :gateway_data, default: {}
      t.timestamps null: false

      t.index [ :gateway, :external_payment_id ], unique: true, name: 'idx_missing_payment_logs_on_gateway_external_id_unique'
      t.index [ :status ], name: 'idx_missing_payment_logs_on_status'
      t.index [ :detected_at ], name: 'idx_missing_payment_logs_on_detected_at'
    end

    # Add check constraints
    add_check_constraint :plans, "billing_interval IN ('monthly', 'yearly', 'one_time')", name: 'valid_billing_interval'
    add_check_constraint :plans, "price_cents >= 0", name: 'valid_price'
    add_check_constraint :subscriptions, "status IN ('active', 'trialing', 'past_due', 'canceled', 'unpaid', 'incomplete', 'incomplete_expired', 'paused')", name: 'valid_subscription_status'
    add_check_constraint :payment_methods, "gateway IN ('stripe', 'paypal')", name: 'valid_payment_gateway'
    add_check_constraint :payment_methods, "payment_type IN ('card', 'bank', 'paypal', 'apple_pay', 'google_pay')", name: 'valid_payment_type'
    add_check_constraint :payments, "amount_cents >= 0", name: 'valid_payment_amount'
    add_check_constraint :payments, "status IN ('pending', 'processing', 'succeeded', 'failed', 'canceled', 'refunded', 'partially_refunded')", name: 'valid_payment_status'
    add_check_constraint :payments, "gateway IN ('stripe', 'paypal')", name: 'valid_payment_gateway'
    add_check_constraint :invoices, "status IN ('draft', 'open', 'paid', 'void', 'uncollectible')", name: 'valid_invoice_status'
    add_check_constraint :invoices, "subtotal_cents >= 0 AND tax_cents >= 0 AND total_cents >= 0", name: 'valid_invoice_amounts'
    add_check_constraint :invoices, "tax_rate >= 0 AND tax_rate < 1", name: 'valid_tax_rate'
    add_check_constraint :revenue_snapshots, "period_type IN ('daily', 'weekly', 'monthly', 'yearly')", name: 'valid_period_type'
    add_check_constraint :missing_payment_logs, "amount_cents > 0", name: 'valid_missing_payment_amount'
  end
end
