# frozen_string_literal: true

# Marketplace Monetization Tables - Enterprise publisher and transaction infrastructure
#
# Depends on core migration 20260119000008_create_agent_marketplace_tables.rb
# which creates ai_agent_templates, ai_agent_installations, ai_agent_reviews
#
class CreateMarketplaceMonetizationTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # PUBLISHER ACCOUNTS - Agent creators/publishers
    # ==========================================================================
    create_table :ai_publisher_accounts, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.references :primary_user, foreign_key: { to_table: :users }, type: :uuid
      t.string :publisher_name, null: false
      t.string :publisher_slug, null: false
      t.text :description
      t.string :website_url
      t.string :support_email
      t.string :status, null: false, default: "pending"
      t.string :verification_status, null: false, default: "unverified"
      t.integer :revenue_share_percentage, default: 70
      t.decimal :lifetime_earnings_usd, precision: 12, scale: 2, default: 0
      t.decimal :pending_payout_usd, precision: 12, scale: 2, default: 0
      t.integer :total_templates, default: 0
      t.integer :total_installations, default: 0
      t.float :average_rating
      t.jsonb :payout_settings, default: {}
      t.jsonb :branding, default: {}
      t.datetime :verified_at
      t.datetime :last_payout_at

      t.timestamps
    end

    add_index :ai_publisher_accounts, :publisher_slug, unique: true
    add_index :ai_publisher_accounts, :status
    add_index :ai_publisher_accounts, :verification_status

    # ==========================================================================
    # MARKETPLACE CATEGORIES - Category taxonomy
    # ==========================================================================
    create_table :ai_marketplace_categories, id: :uuid do |t|
      t.references :parent, foreign_key: { to_table: :ai_marketplace_categories }, type: :uuid
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :icon
      t.integer :display_order, default: 0
      t.boolean :is_active, null: false, default: true
      t.integer :template_count, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_marketplace_categories, :slug, unique: true
    add_index :ai_marketplace_categories, [ :parent_id, :display_order ]
    add_index :ai_marketplace_categories, :is_active

    # ==========================================================================
    # MARKETPLACE TRANSACTIONS - Purchase and commission tracking
    # ==========================================================================
    create_table :ai_marketplace_transactions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :publisher, null: false, foreign_key: { to_table: :ai_publisher_accounts }, type: :uuid
      t.references :agent_template, null: false, foreign_key: { to_table: :ai_agent_templates }, type: :uuid
      t.references :installation, foreign_key: { to_table: :ai_agent_installations }, type: :uuid
      t.string :transaction_type, null: false
      t.string :status, null: false, default: "pending"
      t.decimal :gross_amount_usd, precision: 10, scale: 2, null: false
      t.decimal :commission_amount_usd, precision: 10, scale: 2, null: false
      t.decimal :publisher_amount_usd, precision: 10, scale: 2, null: false
      t.integer :commission_percentage, null: false
      t.string :payment_reference
      t.jsonb :metadata, default: {}
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_marketplace_transactions, [ :account_id, :created_at ]
    add_index :ai_marketplace_transactions, [ :publisher_id, :status ]
    add_index :ai_marketplace_transactions, :transaction_type
    add_index :ai_marketplace_transactions, :status

    # ==========================================================================
    # FOREIGN KEY - Link core templates to enterprise publisher accounts
    # ==========================================================================
    add_foreign_key :ai_agent_templates, :ai_publisher_accounts, column: :publisher_id

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE ai_publisher_accounts
      ADD CONSTRAINT check_publisher_status
      CHECK (status IN ('pending', 'active', 'suspended', 'terminated'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_publisher_accounts
      ADD CONSTRAINT check_verification_status
      CHECK (verification_status IN ('unverified', 'pending', 'verified', 'rejected'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_marketplace_transactions
      ADD CONSTRAINT check_transaction_type
      CHECK (transaction_type IN ('purchase', 'subscription', 'renewal', 'refund', 'payout'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_marketplace_transactions
      ADD CONSTRAINT check_transaction_status
      CHECK (status IN ('pending', 'completed', 'failed', 'refunded', 'disputed'))
    SQL
  end
end
