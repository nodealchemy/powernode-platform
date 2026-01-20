# frozen_string_literal: true

class CreateResellerSystem < ActiveRecord::Migration[8.0]
  def change
    # Reseller profiles - partner program
    create_table :resellers, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :account, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.references :primary_user, type: :uuid, null: false, foreign_key: { to_table: :users }

      # Partner details
      t.string :company_name, null: false
      t.string :contact_email, null: false
      t.string :contact_phone
      t.string :website_url
      t.string :tax_id

      # Partner tier
      t.string :tier, null: false, default: "bronze"
      t.string :status, null: false, default: "pending"

      # Commission settings
      t.decimal :commission_percentage, precision: 5, scale: 2, null: false, default: 10.0
      t.decimal :lifetime_earnings, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :pending_payout, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :total_paid_out, precision: 15, scale: 2, null: false, default: 0.0

      # Statistics
      t.integer :total_referrals, null: false, default: 0
      t.integer :active_referrals, null: false, default: 0
      t.decimal :total_revenue_generated, precision: 15, scale: 2, null: false, default: 0.0

      # Payout settings
      t.string :payout_method, default: "bank_transfer"
      t.jsonb :payout_details, default: {}

      # Branding
      t.string :referral_code, null: false
      t.jsonb :branding, default: {}

      # Approval
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.datetime :activated_at

      t.timestamps
    end

    add_index :resellers, :referral_code, unique: true
    add_index :resellers, :tier
    add_index :resellers, :status
    add_index :resellers, [:status, :tier]

    # Reseller commissions - earnings tracking
    create_table :reseller_commissions, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :reseller, type: :uuid, null: false, foreign_key: true
      t.references :referred_account, type: :uuid, null: false, foreign_key: { to_table: :accounts }

      # Commission source
      t.string :commission_type, null: false # signup_bonus, recurring, one_time
      t.string :source_type, null: false # subscription, payment, credit_purchase
      t.uuid :source_id

      # Amounts
      t.decimal :gross_amount, precision: 15, scale: 2, null: false
      t.decimal :commission_percentage, precision: 5, scale: 2, null: false
      t.decimal :commission_amount, precision: 15, scale: 2, null: false

      # Status
      t.string :status, null: false, default: "pending"
      t.datetime :earned_at, null: false
      t.datetime :available_at # When it becomes payable (after hold period)
      t.datetime :paid_at

      t.uuid :payout_id

      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :reseller_commissions, :commission_type
    add_index :reseller_commissions, :status
    add_index :reseller_commissions, [:reseller_id, :status]
    add_index :reseller_commissions, [:reseller_id, :earned_at]
    add_index :reseller_commissions, [:source_type, :source_id]

    # Reseller payouts - payment processing
    create_table :reseller_payouts, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :reseller, type: :uuid, null: false, foreign_key: true

      # Payout details
      t.string :payout_reference, null: false
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.decimal :fee, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :net_amount, precision: 15, scale: 2, null: false
      t.string :currency, null: false, default: "USD"

      # Status
      t.string :status, null: false, default: "pending"
      t.string :payout_method, null: false

      # Processing
      t.references :processed_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :requested_at, null: false
      t.datetime :processed_at
      t.datetime :completed_at
      t.datetime :failed_at

      # Payment provider details
      t.string :provider_reference
      t.text :failure_reason

      t.jsonb :payout_details, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :reseller_payouts, :payout_reference, unique: true
    add_index :reseller_payouts, :status
    add_index :reseller_payouts, [:reseller_id, :status]
    add_index :reseller_payouts, :requested_at

    # Add the payout foreign key now that reseller_payouts exists
    add_foreign_key :reseller_commissions, :reseller_payouts, column: :payout_id
    add_index :reseller_commissions, :payout_id

    # Reseller referrals - track referred accounts
    create_table :reseller_referrals, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :reseller, type: :uuid, null: false, foreign_key: true
      t.references :referred_account, type: :uuid, null: false, foreign_key: { to_table: :accounts }, index: { unique: true }

      # Referral tracking
      t.string :referral_code_used, null: false
      t.string :status, null: false, default: "active"

      # Revenue tracking
      t.decimal :total_revenue, precision: 15, scale: 2, null: false, default: 0.0
      t.decimal :total_commission_earned, precision: 15, scale: 2, null: false, default: 0.0

      t.datetime :referred_at, null: false
      t.datetime :first_payment_at
      t.datetime :churned_at

      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :reseller_referrals, [:reseller_id, :status]
    add_index :reseller_referrals, :referral_code_used

    # Add CHECK constraints
    execute <<-SQL
      ALTER TABLE resellers
      ADD CONSTRAINT check_reseller_tier
      CHECK (tier IN ('bronze', 'silver', 'gold', 'platinum'));

      ALTER TABLE resellers
      ADD CONSTRAINT check_reseller_status
      CHECK (status IN ('pending', 'approved', 'active', 'suspended', 'terminated'));

      ALTER TABLE resellers
      ADD CONSTRAINT check_reseller_payout_method
      CHECK (payout_method IN ('bank_transfer', 'paypal', 'stripe', 'check', 'wire'));

      ALTER TABLE reseller_commissions
      ADD CONSTRAINT check_commission_type
      CHECK (commission_type IN ('signup_bonus', 'recurring', 'one_time', 'upgrade_bonus'));

      ALTER TABLE reseller_commissions
      ADD CONSTRAINT check_commission_source_type
      CHECK (source_type IN ('subscription', 'payment', 'credit_purchase', 'plan_upgrade'));

      ALTER TABLE reseller_commissions
      ADD CONSTRAINT check_commission_status
      CHECK (status IN ('pending', 'available', 'paid', 'cancelled', 'clawed_back'));

      ALTER TABLE reseller_payouts
      ADD CONSTRAINT check_payout_status
      CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled'));

      ALTER TABLE reseller_referrals
      ADD CONSTRAINT check_referral_status
      CHECK (status IN ('active', 'churned', 'cancelled'));
    SQL
  end
end
