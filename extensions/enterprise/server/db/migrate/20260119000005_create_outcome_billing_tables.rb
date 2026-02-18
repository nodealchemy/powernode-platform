# frozen_string_literal: true

# Outcome Billing Tables - Success-based billing with SLA guarantees
#
# Revenue Model: Success fees + SLA premiums
# - Per-successful-outcome pricing ($0.01-$5.00 based on complexity)
# - SLA tiers: 99% ($X), 99.9% ($2X), 99.99% ($5X)
# - Refund credits for SLA breaches
# - Volume discounts for enterprise commitments
#
class CreateOutcomeBillingTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # OUTCOME DEFINITIONS - Define what constitutes a billable outcome
    # ==========================================================================
    create_table :ai_outcome_definitions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.text :description
      t.string :outcome_type, null: false
      t.string :category

      # Success criteria
      t.jsonb :success_criteria, null: false, default: {}
      t.string :validation_method, null: false, default: "automatic"
      t.decimal :quality_threshold, precision: 5, scale: 4
      t.integer :timeout_seconds, default: 300

      # Pricing
      t.decimal :base_price_usd, precision: 10, scale: 4, null: false
      t.decimal :price_per_token, precision: 15, scale: 10
      t.decimal :price_per_minute, precision: 10, scale: 4
      t.decimal :min_charge_usd, precision: 10, scale: 4
      t.decimal :max_charge_usd, precision: 10, scale: 4

      # Volume discounts
      t.jsonb :volume_tiers, default: []
      t.integer :free_tier_count, default: 0

      # SLA configuration
      t.boolean :sla_enabled, null: false, default: false
      t.decimal :sla_target_percentage, precision: 6, scale: 4
      t.decimal :sla_credit_percentage, precision: 5, scale: 2
      t.integer :sla_measurement_window_hours, default: 720

      # Status
      t.boolean :is_active, null: false, default: true
      t.boolean :is_system, null: false, default: false
      t.datetime :effective_from
      t.datetime :effective_until

      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_outcome_definitions, [ :account_id, :outcome_type ]
    add_index :ai_outcome_definitions, [ :account_id, :is_active ]
    add_index :ai_outcome_definitions, :outcome_type
    add_index :ai_outcome_definitions, :is_system

    # ==========================================================================
    # SLA CONTRACTS - Account-specific SLA agreements
    # ==========================================================================
    create_table :ai_sla_contracts, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :outcome_definition, foreign_key: { to_table: :ai_outcome_definitions }, type: :uuid
      t.string :name, null: false
      t.string :contract_type, null: false, default: "standard"
      t.string :status, null: false, default: "active"

      # SLA targets
      t.decimal :success_rate_target, precision: 6, scale: 4, null: false
      t.decimal :latency_p95_target_ms, precision: 10, scale: 2
      t.decimal :availability_target, precision: 6, scale: 4

      # Pricing and credits
      t.decimal :monthly_commitment_usd, precision: 10, scale: 2
      t.decimal :price_multiplier, precision: 5, scale: 2, default: 1.0
      t.decimal :breach_credit_percentage, precision: 5, scale: 2, null: false
      t.decimal :max_monthly_credit_percentage, precision: 5, scale: 2, default: 100

      # Measurement
      t.integer :measurement_window_hours, null: false, default: 720
      t.datetime :current_period_start
      t.datetime :current_period_end

      # Current metrics
      t.integer :current_period_total, default: 0
      t.integer :current_period_successful, default: 0
      t.decimal :current_success_rate, precision: 6, scale: 4
      t.boolean :current_period_breached, default: false

      t.datetime :activated_at
      t.datetime :expires_at
      t.datetime :cancelled_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_sla_contracts, [ :account_id, :status ]
    add_index :ai_sla_contracts, :status
    add_index :ai_sla_contracts, :current_period_end

    # ==========================================================================
    # OUTCOME BILLING RECORDS - Individual outcome billing events
    # ==========================================================================
    create_table :ai_outcome_billing_records, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :outcome_definition, null: false, foreign_key: { to_table: :ai_outcome_definitions }, type: :uuid
      t.references :sla_contract, foreign_key: { to_table: :ai_sla_contracts }, type: :uuid

      # Source reference
      t.string :source_type, null: false
      t.uuid :source_id, null: false
      t.string :source_name

      # Outcome details
      t.string :status, null: false, default: "pending"
      t.boolean :is_successful
      t.decimal :quality_score, precision: 5, scale: 4
      t.text :failure_reason
      t.integer :duration_ms
      t.integer :tokens_used
      t.integer :retry_count, default: 0

      # Billing
      t.decimal :base_charge_usd, precision: 10, scale: 4
      t.decimal :token_charge_usd, precision: 10, scale: 4
      t.decimal :time_charge_usd, precision: 10, scale: 4
      t.decimal :discount_usd, precision: 10, scale: 4, default: 0
      t.decimal :final_charge_usd, precision: 10, scale: 4
      t.boolean :is_billable, null: false, default: true
      t.boolean :is_billed, null: false, default: false
      t.datetime :billed_at
      t.uuid :invoice_line_item_id

      # SLA tracking
      t.boolean :counted_for_sla, null: false, default: true
      t.boolean :met_sla_criteria

      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :validated_at
      t.references :validated_by, foreign_key: { to_table: :users }, type: :uuid
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_outcome_billing_records, [ :account_id, :created_at ]
    add_index :ai_outcome_billing_records, [ :outcome_definition_id, :created_at ]
    add_index :ai_outcome_billing_records, [ :source_type, :source_id ]
    add_index :ai_outcome_billing_records, :status
    add_index :ai_outcome_billing_records, [ :is_billable, :is_billed ]
    add_index :ai_outcome_billing_records, :created_at

    # ==========================================================================
    # SLA VIOLATIONS - Track SLA breaches for credit calculation
    # ==========================================================================
    create_table :ai_sla_violations, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sla_contract, null: false, foreign_key: { to_table: :ai_sla_contracts }, type: :uuid
      t.string :violation_type, null: false
      t.string :severity, null: false, default: "minor"
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false

      # Violation details
      t.decimal :target_value, precision: 10, scale: 4, null: false
      t.decimal :actual_value, precision: 10, scale: 4, null: false
      t.decimal :deviation_percentage, precision: 10, scale: 4
      t.integer :affected_outcomes_count

      # Credit calculation
      t.decimal :credit_percentage, precision: 5, scale: 2, null: false
      t.decimal :credit_amount_usd, precision: 10, scale: 2, null: false
      t.string :credit_status, null: false, default: "pending"
      t.datetime :credit_applied_at
      t.uuid :credit_transaction_id

      t.text :description
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_sla_violations, [ :account_id, :created_at ]
    add_index :ai_sla_violations, [ :sla_contract_id, :period_start ]
    add_index :ai_sla_violations, :credit_status
    add_index :ai_sla_violations, :violation_type

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE ai_outcome_definitions
      ADD CONSTRAINT check_outcome_type
      CHECK (outcome_type IN ('task_completion', 'quality_threshold', 'classification', 'extraction', 'generation', 'conversation', 'workflow', 'custom'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_outcome_definitions
      ADD CONSTRAINT check_validation_method
      CHECK (validation_method IN ('automatic', 'human_review', 'hybrid', 'api_callback'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_sla_contracts
      ADD CONSTRAINT check_sla_contract_status
      CHECK (status IN ('draft', 'pending_approval', 'active', 'suspended', 'expired', 'cancelled'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_outcome_billing_records
      ADD CONSTRAINT check_outcome_billing_status
      CHECK (status IN ('pending', 'processing', 'successful', 'failed', 'timeout', 'cancelled', 'refunded'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_sla_violations
      ADD CONSTRAINT check_sla_violation_type
      CHECK (violation_type IN ('success_rate', 'latency', 'availability', 'quality'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_sla_violations
      ADD CONSTRAINT check_sla_credit_status
      CHECK (credit_status IN ('pending', 'approved', 'applied', 'rejected', 'waived'))
    SQL
  end
end
