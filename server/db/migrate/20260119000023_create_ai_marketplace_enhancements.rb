# frozen_string_literal: true

class CreateAiMarketplaceEnhancements < ActiveRecord::Migration[8.0]
  def change
    # Marketplace moderation queue
    create_table :ai_marketplace_moderations, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :agent_template, type: :uuid, null: false, foreign_key: { to_table: :ai_agent_templates }
      t.references :submitted_by, type: :uuid, null: false, foreign_key: { to_table: :users }

      # Review status
      t.string :status, null: false, default: "pending" # pending, in_review, approved, rejected, revision_requested
      t.string :review_type, null: false, default: "initial" # initial, update, reinstatement

      # Submission details
      t.datetime :submitted_at, null: false
      t.text :submission_notes

      # Review details
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text :review_notes
      t.string :rejection_reason

      # Revision tracking
      t.integer :revision_number, null: false, default: 1
      t.jsonb :changes_summary, default: {}

      # Automated checks
      t.boolean :passed_automated_checks, null: false, default: false
      t.jsonb :automated_check_results, default: {}
      t.datetime :automated_checks_at

      t.timestamps
    end

    add_index :ai_marketplace_moderations, :status
    add_index :ai_marketplace_moderations, [:agent_template_id, :status]
    add_index :ai_marketplace_moderations, :submitted_at

    # Template usage metrics for analytics
    create_table :ai_template_usage_metrics, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :agent_template, type: :uuid, null: false, foreign_key: { to_table: :ai_agent_templates }

      # Time period
      t.date :metric_date, null: false

      # Usage metrics
      t.integer :total_installations, null: false, default: 0
      t.integer :new_installations, null: false, default: 0
      t.integer :uninstallations, null: false, default: 0
      t.integer :active_installations, null: false, default: 0
      t.integer :total_executions, null: false, default: 0

      # Revenue metrics
      t.decimal :gross_revenue, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :publisher_revenue, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :platform_commission, precision: 15, scale: 2, null: false, default: 0.0

      # Engagement metrics
      t.integer :page_views, null: false, default: 0
      t.integer :unique_visitors, null: false, default: 0
      t.decimal :conversion_rate, precision: 5, scale: 2

      # Rating metrics
      t.decimal :average_rating, precision: 3, scale: 2
      t.integer :new_reviews, null: false, default: 0
      t.integer :total_reviews, null: false, default: 0

      t.timestamps
    end

    add_index :ai_template_usage_metrics, [:agent_template_id, :metric_date], unique: true, name: "idx_template_metrics_date"
    add_index :ai_template_usage_metrics, :metric_date

    # Marketplace purchases (one-time purchases separate from subscriptions)
    create_table :ai_marketplace_purchases, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, foreign_key: true
      t.references :agent_template, type: :uuid, null: false, foreign_key: { to_table: :ai_agent_templates }
      t.references :installation, type: :uuid, foreign_key: { to_table: :ai_agent_installations }

      # Purchase details
      t.string :purchase_type, null: false, default: "one_time" # one_time, subscription, credit
      t.string :status, null: false, default: "pending"

      # Pricing
      t.decimal :price, precision: 15, scale: 2, null: false
      t.decimal :discount_amount, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :final_price, precision: 15, scale: 2, null: false
      t.string :currency, null: false, default: "USD"

      # Payment
      t.string :payment_method # credit_card, credits, paypal
      t.string :payment_reference
      t.datetime :paid_at

      # Refund
      t.boolean :is_refunded, null: false, default: false
      t.decimal :refund_amount, precision: 15, scale: 2
      t.datetime :refunded_at
      t.text :refund_reason

      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :ai_marketplace_purchases, [:account_id, :agent_template_id]
    add_index :ai_marketplace_purchases, :status
    add_index :ai_marketplace_purchases, :created_at

    # Publisher earnings snapshots for analytics
    create_table :ai_publisher_earnings_snapshots, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :publisher, type: :uuid, null: false, foreign_key: { to_table: :ai_publisher_accounts }

      # Time period
      t.date :snapshot_date, null: false

      # Earnings
      t.decimal :gross_earnings, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :net_earnings, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :pending_payout, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :paid_out, precision: 15, scale: 2, null: false, default: 0.0

      # Sales metrics
      t.integer :total_sales, null: false, default: 0
      t.integer :new_customers, null: false, default: 0
      t.integer :returning_customers, null: false, default: 0

      # Template performance
      t.integer :total_templates, null: false, default: 0
      t.integer :active_templates, null: false, default: 0
      t.decimal :average_rating, precision: 3, scale: 2

      t.timestamps
    end

    add_index :ai_publisher_earnings_snapshots, [:publisher_id, :snapshot_date], unique: true, name: "idx_publisher_earnings_date"
    add_index :ai_publisher_earnings_snapshots, :snapshot_date

    # Add Stripe Connect fields to publisher accounts
    add_column :ai_publisher_accounts, :stripe_account_id, :string
    add_column :ai_publisher_accounts, :stripe_account_status, :string, default: "pending"
    add_column :ai_publisher_accounts, :stripe_onboarding_completed, :boolean, default: false
    add_column :ai_publisher_accounts, :stripe_payout_enabled, :boolean, default: false

    add_index :ai_publisher_accounts, :stripe_account_id, unique: true

    # Add CHECK constraints
    execute <<-SQL
      ALTER TABLE ai_marketplace_moderations
      ADD CONSTRAINT check_moderation_status
      CHECK (status IN ('pending', 'in_review', 'approved', 'rejected', 'revision_requested'));

      ALTER TABLE ai_marketplace_moderations
      ADD CONSTRAINT check_review_type
      CHECK (review_type IN ('initial', 'update', 'reinstatement', 'appeal'));

      ALTER TABLE ai_marketplace_purchases
      ADD CONSTRAINT check_purchase_type
      CHECK (purchase_type IN ('one_time', 'subscription', 'credit', 'upgrade'));

      ALTER TABLE ai_marketplace_purchases
      ADD CONSTRAINT check_purchase_status
      CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded', 'cancelled'));
    SQL
  end
end
