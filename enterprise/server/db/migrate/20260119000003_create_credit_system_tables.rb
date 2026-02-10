# frozen_string_literal: true

# Credit System Tables - Prepaid AI Credits with Reseller Support
#
# Revenue Model: Prepaid credits + reseller margins
# - Credit packs: 1K ($99), 10K ($899), 100K ($7,999)
# - Reseller margin: 15-30% based on volume
# - Credit marketplace for B2B trading
# - Enterprise credit agreements
#
class CreateCreditSystemTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # CREDIT PACKS - Available credit packages for purchase
    # ==========================================================================
    create_table :ai_credit_packs, id: :uuid do |t|
      t.string :name, null: false
      t.string :description
      t.string :pack_type, null: false, default: "standard"
      t.integer :credits, null: false
      t.decimal :price_usd, precision: 10, scale: 2, null: false
      t.decimal :bonus_credits, precision: 10, scale: 2, default: 0
      t.decimal :effective_price_per_credit, precision: 10, scale: 6
      t.boolean :is_active, null: false, default: true
      t.boolean :is_featured, null: false, default: false
      t.integer :min_purchase_quantity, default: 1
      t.integer :max_purchase_quantity
      t.jsonb :metadata, default: {}
      t.datetime :valid_from
      t.datetime :valid_until
      t.integer :sort_order, default: 0

      t.timestamps
    end

    add_index :ai_credit_packs, :pack_type
    add_index :ai_credit_packs, :is_active
    add_index :ai_credit_packs, [ :is_active, :sort_order ]

    # ==========================================================================
    # ACCOUNT CREDITS - Credit balance per account
    # ==========================================================================
    create_table :ai_account_credits, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.decimal :balance, precision: 15, scale: 4, null: false, default: 0
      t.decimal :reserved_balance, precision: 15, scale: 4, null: false, default: 0
      t.decimal :lifetime_credits_purchased, precision: 15, scale: 4, default: 0
      t.decimal :lifetime_credits_used, precision: 15, scale: 4, default: 0
      t.decimal :lifetime_credits_expired, precision: 15, scale: 4, default: 0
      t.decimal :lifetime_credits_transferred_in, precision: 15, scale: 4, default: 0
      t.decimal :lifetime_credits_transferred_out, precision: 15, scale: 4, default: 0
      t.boolean :is_reseller, null: false, default: false
      t.decimal :reseller_discount_percentage, precision: 5, scale: 2, default: 0
      t.decimal :credit_limit, precision: 15, scale: 4
      t.boolean :allow_negative_balance, null: false, default: false
      t.datetime :last_purchase_at
      t.datetime :last_usage_at
      t.jsonb :settings, default: {}

      t.timestamps
    end

    add_index :ai_account_credits, :is_reseller
    add_index :ai_account_credits, :balance

    # ==========================================================================
    # CREDIT TRANSACTIONS - All credit movements (double-entry ledger)
    # ==========================================================================
    create_table :ai_credit_transactions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :account_credit, null: false, foreign_key: { to_table: :ai_account_credits }, type: :uuid
      t.string :transaction_type, null: false
      t.string :reference_type
      t.uuid :reference_id
      t.decimal :amount, precision: 15, scale: 4, null: false
      t.decimal :balance_before, precision: 15, scale: 4, null: false
      t.decimal :balance_after, precision: 15, scale: 4, null: false
      t.string :description
      t.string :status, null: false, default: "completed"
      t.references :credit_pack, foreign_key: { to_table: :ai_credit_packs }, type: :uuid
      t.references :initiated_by, foreign_key: { to_table: :users }, type: :uuid
      t.uuid :related_transaction_id
      t.string :external_reference
      t.jsonb :metadata, default: {}
      t.datetime :expires_at
      t.datetime :processed_at

      t.timestamps
    end

    add_index :ai_credit_transactions, [ :account_id, :created_at ]
    add_index :ai_credit_transactions, [ :account_id, :transaction_type ]
    add_index :ai_credit_transactions, [ :reference_type, :reference_id ]
    add_index :ai_credit_transactions, :status
    add_index :ai_credit_transactions, :expires_at
    add_index :ai_credit_transactions, :related_transaction_id
    add_index :ai_credit_transactions, :created_at

    # ==========================================================================
    # CREDIT PURCHASES - Purchase records for credits
    # ==========================================================================
    create_table :ai_credit_purchases, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :credit_pack, null: false, foreign_key: { to_table: :ai_credit_packs }, type: :uuid
      t.references :user, foreign_key: true, type: :uuid
      t.integer :quantity, null: false, default: 1
      t.decimal :credits_purchased, precision: 15, scale: 4, null: false
      t.decimal :bonus_credits, precision: 15, scale: 4, default: 0
      t.decimal :total_credits, precision: 15, scale: 4, null: false
      t.decimal :unit_price_usd, precision: 10, scale: 2, null: false
      t.decimal :total_price_usd, precision: 10, scale: 2, null: false
      t.decimal :discount_percentage, precision: 5, scale: 2, default: 0
      t.decimal :discount_amount_usd, precision: 10, scale: 2, default: 0
      t.decimal :final_price_usd, precision: 10, scale: 2, null: false
      t.string :payment_method
      t.string :payment_reference
      t.string :status, null: false, default: "pending"
      t.datetime :paid_at
      t.datetime :credits_applied_at
      t.datetime :expires_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_credit_purchases, [ :account_id, :created_at ]
    add_index :ai_credit_purchases, :status
    add_index :ai_credit_purchases, :payment_reference

    # ==========================================================================
    # CREDIT TRANSFERS - B2B credit transfers between accounts
    # ==========================================================================
    create_table :ai_credit_transfers, id: :uuid do |t|
      t.references :from_account, null: false, foreign_key: { to_table: :accounts }, type: :uuid
      t.references :to_account, null: false, foreign_key: { to_table: :accounts }, type: :uuid
      t.references :initiated_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.decimal :amount, precision: 15, scale: 4, null: false
      t.decimal :fee_percentage, precision: 5, scale: 2, default: 0
      t.decimal :fee_amount, precision: 15, scale: 4, default: 0
      t.decimal :net_amount, precision: 15, scale: 4, null: false
      t.string :status, null: false, default: "pending"
      t.string :description
      t.string :reference_code, null: false
      t.uuid :from_transaction_id
      t.uuid :to_transaction_id
      t.datetime :approved_at
      t.references :approved_by, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.string :cancellation_reason
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_credit_transfers, [ :from_account_id, :created_at ]
    add_index :ai_credit_transfers, [ :to_account_id, :created_at ]
    add_index :ai_credit_transfers, :status
    add_index :ai_credit_transfers, :reference_code, unique: true

    # ==========================================================================
    # CREDIT USAGE RATES - Cost per operation type
    # ==========================================================================
    create_table :ai_credit_usage_rates, id: :uuid do |t|
      t.string :operation_type, null: false
      t.string :provider_type
      t.string :model_name
      t.decimal :credits_per_1k_input_tokens, precision: 10, scale: 6
      t.decimal :credits_per_1k_output_tokens, precision: 10, scale: 6
      t.decimal :credits_per_request, precision: 10, scale: 6
      t.decimal :credits_per_minute, precision: 10, scale: 6
      t.decimal :credits_per_gb_storage, precision: 10, scale: 6
      t.decimal :base_credits, precision: 10, scale: 6, default: 0
      t.boolean :is_active, null: false, default: true
      t.datetime :effective_from, null: false
      t.datetime :effective_until
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_credit_usage_rates, [ :operation_type, :provider_type, :model_name ], name: "idx_credit_rates_operation_provider_model"
    add_index :ai_credit_usage_rates, [ :is_active, :effective_from ]

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE ai_credit_packs
      ADD CONSTRAINT check_credit_pack_type
      CHECK (pack_type IN ('standard', 'bulk', 'enterprise', 'promotional', 'reseller'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_credit_transactions
      ADD CONSTRAINT check_credit_transaction_type
      CHECK (transaction_type IN ('purchase', 'usage', 'refund', 'transfer_in', 'transfer_out', 'bonus', 'adjustment', 'expiration', 'reservation', 'release'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_credit_transactions
      ADD CONSTRAINT check_credit_transaction_status
      CHECK (status IN ('pending', 'completed', 'failed', 'reversed', 'expired'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_credit_purchases
      ADD CONSTRAINT check_credit_purchase_status
      CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded', 'partially_refunded'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_credit_transfers
      ADD CONSTRAINT check_credit_transfer_status
      CHECK (status IN ('pending', 'approved', 'completed', 'rejected', 'cancelled', 'failed'))
    SQL
  end
end
